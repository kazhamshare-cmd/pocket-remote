import Foundation
import VideoToolbox
import Flutter

/// H.264 Decoder using VideoToolbox
class H264Decoder: NSObject {
    private var formatDescription: CMVideoFormatDescription?
    private var decompressionSession: VTDecompressionSession?

    private var sps: Data?
    private var pps: Data?

    var decodedFrameCallback: ((Data, Int, Int) -> Void)?

    // NAL unit types
    private let NAL_TYPE_SPS: UInt8 = 7
    private let NAL_TYPE_PPS: UInt8 = 8
    private let NAL_TYPE_IDR: UInt8 = 5
    private let NAL_TYPE_NON_IDR: UInt8 = 1

    override init() {
        super.init()
    }

    deinit {
        cleanup()
    }

    func setFrameCallback(_ callback: @escaping (Data, Int, Int) -> Void) {
        decodedFrameCallback = callback
    }

    /// Decode H.264 data (can contain multiple NAL units)
    func decode(_ h264Data: Data) -> Bool {
        // Parse NAL units from the data
        let nalUnits = parseNALUnits(h264Data)

        for nalUnit in nalUnits {
            if !processNALUnit(nalUnit) {
                return false
            }
        }

        return true
    }

    /// Parse NAL units from H.264 bitstream
    private func parseNALUnits(_ data: Data) -> [Data] {
        var nalUnits: [Data] = []
        var currentIndex = 0
        let bytes = [UInt8](data)

        while currentIndex < bytes.count - 4 {
            // Look for start code (0x00 0x00 0x00 0x01 or 0x00 0x00 0x01)
            var startCodeLength = 0

            if currentIndex + 4 <= bytes.count &&
               bytes[currentIndex] == 0x00 &&
               bytes[currentIndex + 1] == 0x00 &&
               bytes[currentIndex + 2] == 0x00 &&
               bytes[currentIndex + 3] == 0x01 {
                startCodeLength = 4
            } else if currentIndex + 3 <= bytes.count &&
                      bytes[currentIndex] == 0x00 &&
                      bytes[currentIndex + 1] == 0x00 &&
                      bytes[currentIndex + 2] == 0x01 {
                startCodeLength = 3
            }

            if startCodeLength > 0 {
                let nalStart = currentIndex + startCodeLength
                var nalEnd = bytes.count

                // Find next start code
                for i in nalStart..<(bytes.count - 3) {
                    if (bytes[i] == 0x00 && bytes[i + 1] == 0x00 && bytes[i + 2] == 0x00 && bytes[i + 3] == 0x01) ||
                       (bytes[i] == 0x00 && bytes[i + 1] == 0x00 && bytes[i + 2] == 0x01) {
                        nalEnd = i
                        break
                    }
                }

                if nalEnd > nalStart {
                    let nalData = Data(bytes[nalStart..<nalEnd])
                    nalUnits.append(nalData)
                }

                currentIndex = nalEnd
            } else {
                currentIndex += 1
            }
        }

        return nalUnits
    }

    /// Process a single NAL unit
    private func processNALUnit(_ nalUnit: Data) -> Bool {
        guard nalUnit.count > 0 else { return false }

        let nalType = nalUnit[0] & 0x1F

        switch nalType {
        case NAL_TYPE_SPS:
            sps = nalUnit
            return createFormatDescription()

        case NAL_TYPE_PPS:
            pps = nalUnit
            return createFormatDescription()

        case NAL_TYPE_IDR, NAL_TYPE_NON_IDR:
            return decodeFrame(nalUnit, isKeyframe: nalType == NAL_TYPE_IDR)

        default:
            // Other NAL types (SEI, etc.) - ignore
            return true
        }
    }

    /// Create format description from SPS and PPS
    private func createFormatDescription() -> Bool {
        guard let spsData = sps, let ppsData = pps else {
            return true // Not ready yet, but not an error
        }

        // Convert Data to [UInt8] arrays
        let spsArray = [UInt8](spsData)
        let ppsArray = [UInt8](ppsData)

        var newFormatDescription: CMVideoFormatDescription?

        // Use withUnsafeBufferPointer to safely access the arrays
        let status = spsArray.withUnsafeBufferPointer { spsPointer in
            ppsArray.withUnsafeBufferPointer { ppsPointer in
                var parameterSetPointers: [UnsafePointer<UInt8>] = [
                    spsPointer.baseAddress!,
                    ppsPointer.baseAddress!
                ]
                var parameterSetSizes: [Int] = [spsArray.count, ppsArray.count]

                return CMVideoFormatDescriptionCreateFromH264ParameterSets(
                    allocator: kCFAllocatorDefault,
                    parameterSetCount: 2,
                    parameterSetPointers: &parameterSetPointers,
                    parameterSetSizes: &parameterSetSizes,
                    nalUnitHeaderLength: 4,
                    formatDescriptionOut: &newFormatDescription
                )
            }
        }

        if status != noErr {
            return false
        }

        formatDescription = newFormatDescription

        return createDecompressionSession()
    }

    /// Create decompression session
    private func createDecompressionSession() -> Bool {
        guard let formatDesc = formatDescription else { return false }

        // Clean up existing session
        if let session = decompressionSession {
            VTDecompressionSessionInvalidate(session)
            decompressionSession = nil
        }

        // Destination image buffer attributes
        let destinationAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferMetalCompatibilityKey as String: true
        ]

        // Callback for decoded frames
        var callbackRecord = VTDecompressionOutputCallbackRecord(
            decompressionOutputCallback: decompressionCallback,
            decompressionOutputRefCon: Unmanaged.passUnretained(self).toOpaque()
        )

        var session: VTDecompressionSession?
        let status = VTDecompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            formatDescription: formatDesc,
            decoderSpecification: nil,
            imageBufferAttributes: destinationAttributes as CFDictionary,
            outputCallback: &callbackRecord,
            decompressionSessionOut: &session
        )

        if status != noErr {
            return false
        }

        decompressionSession = session
        return true
    }

    /// Decode a video frame
    private func decodeFrame(_ nalUnit: Data, isKeyframe: Bool) -> Bool {
        guard let session = decompressionSession, let formatDesc = formatDescription else {
            return false
        }

        // Create sample buffer with AVCC format (4-byte length prefix)
        var blockBuffer: CMBlockBuffer?

        // Convert to AVCC format (replace start code with length)
        var avccData = Data()
        let length = UInt32(nalUnit.count).bigEndian
        withUnsafeBytes(of: length) { avccData.append(contentsOf: $0) }
        avccData.append(nalUnit)

        let dataLength = avccData.count
        var status = avccData.withUnsafeMutableBytes { pointer -> OSStatus in
            CMBlockBufferCreateWithMemoryBlock(
                allocator: kCFAllocatorDefault,
                memoryBlock: pointer.baseAddress,
                blockLength: dataLength,
                blockAllocator: kCFAllocatorNull,
                customBlockSource: nil,
                offsetToData: 0,
                dataLength: dataLength,
                flags: 0,
                blockBufferOut: &blockBuffer
            )
        }

        if status != noErr {
            return false
        }

        // Create sample buffer
        var sampleBuffer: CMSampleBuffer?
        var sampleSizeArray = [dataLength]

        status = CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: blockBuffer,
            formatDescription: formatDesc,
            sampleCount: 1,
            sampleTimingEntryCount: 0,
            sampleTimingArray: nil,
            sampleSizeEntryCount: 1,
            sampleSizeArray: &sampleSizeArray,
            sampleBufferOut: &sampleBuffer
        )

        if status != noErr {
            return false
        }

        guard let sample = sampleBuffer else { return false }

        // Decode
        var flagsOut: VTDecodeInfoFlags = []
        status = VTDecompressionSessionDecodeFrame(
            session,
            sampleBuffer: sample,
            flags: [._EnableAsynchronousDecompression],
            frameRefcon: nil,
            infoFlagsOut: &flagsOut
        )

        if status != noErr {
            return false
        }

        return true
    }

    /// Cleanup resources
    func cleanup() {
        if let session = decompressionSession {
            VTDecompressionSessionInvalidate(session)
            decompressionSession = nil
        }
        formatDescription = nil
        sps = nil
        pps = nil
    }
}

/// Decompression callback
private func decompressionCallback(
    decompressionOutputRefCon: UnsafeMutableRawPointer?,
    sourceFrameRefCon: UnsafeMutableRawPointer?,
    status: OSStatus,
    infoFlags: VTDecodeInfoFlags,
    imageBuffer: CVImageBuffer?,
    presentationTimeStamp: CMTime,
    presentationDuration: CMTime
) {
    guard status == noErr else { return }
    guard let pixelBuffer = imageBuffer else { return }
    guard let refCon = decompressionOutputRefCon else { return }
    let decoder = Unmanaged<H264Decoder>.fromOpaque(refCon).takeUnretainedValue()

    // Convert CVPixelBuffer to JPEG
    guard let jpegData = pixelBufferToJPEG(pixelBuffer: pixelBuffer, quality: 0.8) else { return }

    let width = CVPixelBufferGetWidth(pixelBuffer)
    let height = CVPixelBufferGetHeight(pixelBuffer)

    // Call the callback on main thread
    DispatchQueue.main.async {
        decoder.decodedFrameCallback?(jpegData, width, height)
    }
}

/// Convert CVPixelBuffer to JPEG Data
private func pixelBufferToJPEG(pixelBuffer: CVPixelBuffer, quality: CGFloat) -> Data? {
    let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
    let context = CIContext()

    guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
        return nil
    }

    let uiImage = UIImage(cgImage: cgImage)
    return uiImage.jpegData(compressionQuality: quality)
}

/// Flutter Platform Channel Handler
class H264DecoderPlugin: NSObject, FlutterPlugin {
    private let decoder = H264Decoder()
    private var eventSink: FlutterEventSink?

    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "com.pocketremote/h264_decoder",
            binaryMessenger: registrar.messenger()
        )

        let eventChannel = FlutterEventChannel(
            name: "com.pocketremote/h264_decoder_frames",
            binaryMessenger: registrar.messenger()
        )

        let instance = H264DecoderPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
        eventChannel.setStreamHandler(instance)
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "decode":
            if let args = call.arguments as? FlutterStandardTypedData {
                let success = decoder.decode(args.data)
                result(success)
            } else {
                result(FlutterError(code: "INVALID_ARGUMENT", message: "Expected Uint8List", details: nil))
            }

        case "reset":
            decoder.cleanup()
            result(true)

        default:
            result(FlutterMethodNotImplemented)
        }
    }
}

extension H264DecoderPlugin: FlutterStreamHandler {
    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        eventSink = events

        decoder.setFrameCallback { [weak self] data, width, height in
            guard let sink = self?.eventSink else { return }

            // Send frame data as map
            let frameInfo: [String: Any] = [
                "data": FlutterStandardTypedData(bytes: data),
                "width": width,
                "height": height
            ]
            sink(frameInfo)
        }

        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSink = nil
        decoder.setFrameCallback { _, _, _ in }
        return nil
    }
}
