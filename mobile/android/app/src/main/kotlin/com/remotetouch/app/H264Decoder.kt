package com.remotetouch.app

import android.graphics.Bitmap
import android.graphics.ImageFormat
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.atomic.AtomicBoolean

/**
 * H.264 Decoder using Android MediaCodec
 */
class H264Decoder {
    companion object {
        private const val TAG = "H264Decoder"
        private const val MIME_TYPE = "video/avc"
        private const val NAL_TYPE_SPS: Int = 7
        private const val NAL_TYPE_PPS: Int = 8
        private const val NAL_TYPE_IDR: Int = 5
        private const val NAL_TYPE_NON_IDR: Int = 1
    }

    private var decoder: MediaCodec? = null
    private var sps: ByteArray? = null
    private var pps: ByteArray? = null
    private var isConfigured = false
    private var width = 0
    private var height = 0

    private var frameCallback: ((ByteArray, Int, Int) -> Unit)? = null
    private val isRunning = AtomicBoolean(false)
    private var decoderThread: Thread? = null
    private val inputQueue = LinkedBlockingQueue<ByteArray>()

    fun setFrameCallback(callback: (ByteArray, Int, Int) -> Unit) {
        frameCallback = callback
    }

    /**
     * Decode H.264 data (can contain multiple NAL units)
     */
    fun decode(h264Data: ByteArray): Boolean {
        // Parse NAL units
        val nalUnits = parseNALUnits(h264Data)

        for (nalUnit in nalUnits) {
            if (!processNALUnit(nalUnit)) {
                return false
            }
        }

        return true
    }

    /**
     * Parse NAL units from H.264 bitstream
     */
    private fun parseNALUnits(data: ByteArray): List<ByteArray> {
        val nalUnits = mutableListOf<ByteArray>()
        var currentIndex = 0

        while (currentIndex < data.size - 4) {
            var startCodeLength = 0

            // Look for start code (0x00 0x00 0x00 0x01 or 0x00 0x00 0x01)
            if (currentIndex + 4 <= data.size &&
                data[currentIndex] == 0x00.toByte() &&
                data[currentIndex + 1] == 0x00.toByte() &&
                data[currentIndex + 2] == 0x00.toByte() &&
                data[currentIndex + 3] == 0x01.toByte()
            ) {
                startCodeLength = 4
            } else if (currentIndex + 3 <= data.size &&
                data[currentIndex] == 0x00.toByte() &&
                data[currentIndex + 1] == 0x00.toByte() &&
                data[currentIndex + 2] == 0x01.toByte()
            ) {
                startCodeLength = 3
            }

            if (startCodeLength > 0) {
                val nalStart = currentIndex + startCodeLength
                var nalEnd = data.size

                // Find next start code
                for (i in nalStart until (data.size - 3)) {
                    if ((data[i] == 0x00.toByte() && data[i + 1] == 0x00.toByte() &&
                                data[i + 2] == 0x00.toByte() && data[i + 3] == 0x01.toByte()) ||
                        (data[i] == 0x00.toByte() && data[i + 1] == 0x00.toByte() &&
                                data[i + 2] == 0x01.toByte())
                    ) {
                        nalEnd = i
                        break
                    }
                }

                if (nalEnd > nalStart) {
                    val nalData = data.copyOfRange(nalStart, nalEnd)
                    nalUnits.add(nalData)
                }

                currentIndex = nalEnd
            } else {
                currentIndex++
            }
        }

        return nalUnits
    }

    /**
     * Process a single NAL unit
     */
    private fun processNALUnit(nalUnit: ByteArray): Boolean {
        if (nalUnit.isEmpty()) return false

        val nalType = nalUnit[0].toInt() and 0x1F

        return when (nalType) {
            NAL_TYPE_SPS -> {
                sps = nalUnit
                Log.d(TAG, "SPS received: ${nalUnit.size} bytes")
                parseSpsDimensions(nalUnit)
                tryConfigureDecoder()
            }
            NAL_TYPE_PPS -> {
                pps = nalUnit
                Log.d(TAG, "PPS received: ${nalUnit.size} bytes")
                tryConfigureDecoder()
            }
            NAL_TYPE_IDR, NAL_TYPE_NON_IDR -> {
                decodeFrame(nalUnit)
            }
            else -> {
                // Other NAL types - ignore
                true
            }
        }
    }

    /**
     * Parse SPS to get video dimensions
     */
    private fun parseSpsDimensions(sps: ByteArray) {
        // Simple SPS parsing to extract dimensions
        // For a more robust solution, use a proper SPS parser
        // Default to 1920x1080 if parsing fails
        width = 1920
        height = 1080

        try {
            if (sps.size > 4) {
                // Very basic extraction - in practice you'd want a proper SPS parser
                // This is a simplified approximation
                Log.d(TAG, "Using default dimensions: ${width}x${height}")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to parse SPS: ${e.message}")
        }
    }

    /**
     * Try to configure the decoder with SPS and PPS
     */
    private fun tryConfigureDecoder(): Boolean {
        val currentSps = sps ?: return true
        val currentPps = pps ?: return true

        if (isConfigured) return true

        try {
            decoder?.release()

            val format = MediaFormat.createVideoFormat(MIME_TYPE, width, height)
            format.setInteger(MediaFormat.KEY_COLOR_FORMAT,
                MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420Flexible)

            // Set SPS and PPS as codec-specific data
            format.setByteBuffer("csd-0", ByteBuffer.wrap(
                byteArrayOf(0x00, 0x00, 0x00, 0x01) + currentSps
            ))
            format.setByteBuffer("csd-1", ByteBuffer.wrap(
                byteArrayOf(0x00, 0x00, 0x00, 0x01) + currentPps
            ))

            decoder = MediaCodec.createDecoderByType(MIME_TYPE).apply {
                configure(format, null, null, 0)
                start()
            }

            isConfigured = true
            isRunning.set(true)
            startDecoderThread()

            Log.d(TAG, "Decoder configured: ${width}x${height}")
            return true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to configure decoder: ${e.message}")
            return false
        }
    }

    /**
     * Start the decoder output thread
     */
    private fun startDecoderThread() {
        decoderThread = Thread {
            val bufferInfo = MediaCodec.BufferInfo()

            while (isRunning.get()) {
                try {
                    val decoder = this.decoder ?: break

                    // Get output buffer
                    val outputIndex = decoder.dequeueOutputBuffer(bufferInfo, 10000)

                    when {
                        outputIndex >= 0 -> {
                            val image = decoder.getOutputImage(outputIndex)
                            if (image != null) {
                                // Convert YUV to JPEG
                                val jpegData = yuvImageToJpeg(image)
                                if (jpegData != null) {
                                    frameCallback?.invoke(jpegData, image.width, image.height)
                                }
                                image.close()
                            }
                            decoder.releaseOutputBuffer(outputIndex, false)
                        }
                        outputIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                            val newFormat = decoder.outputFormat
                            width = newFormat.getInteger(MediaFormat.KEY_WIDTH)
                            height = newFormat.getInteger(MediaFormat.KEY_HEIGHT)
                            Log.d(TAG, "Output format changed: ${width}x${height}")
                        }
                    }
                } catch (e: Exception) {
                    if (isRunning.get()) {
                        Log.e(TAG, "Decoder thread error: ${e.message}")
                    }
                }
            }
        }.apply { start() }
    }

    /**
     * Convert YUV Image to JPEG
     */
    private fun yuvImageToJpeg(image: android.media.Image): ByteArray? {
        return try {
            val yBuffer = image.planes[0].buffer
            val uBuffer = image.planes[1].buffer
            val vBuffer = image.planes[2].buffer

            val ySize = yBuffer.remaining()
            val uSize = uBuffer.remaining()
            val vSize = vBuffer.remaining()

            val nv21 = ByteArray(ySize + uSize + vSize)

            yBuffer.get(nv21, 0, ySize)
            vBuffer.get(nv21, ySize, vSize)
            uBuffer.get(nv21, ySize + vSize, uSize)

            val yuvImage = android.graphics.YuvImage(
                nv21,
                ImageFormat.NV21,
                image.width,
                image.height,
                null
            )

            val outputStream = ByteArrayOutputStream()
            yuvImage.compressToJpeg(
                android.graphics.Rect(0, 0, image.width, image.height),
                80,
                outputStream
            )

            outputStream.toByteArray()
        } catch (e: Exception) {
            Log.e(TAG, "Failed to convert YUV to JPEG: ${e.message}")
            null
        }
    }

    /**
     * Decode a video frame
     */
    private fun decodeFrame(nalUnit: ByteArray): Boolean {
        val decoder = this.decoder
        if (decoder == null || !isConfigured) {
            Log.d(TAG, "Decoder not ready")
            return false
        }

        try {
            val inputIndex = decoder.dequeueInputBuffer(10000)
            if (inputIndex >= 0) {
                val inputBuffer = decoder.getInputBuffer(inputIndex)
                inputBuffer?.clear()

                // Add start code
                val frameData = byteArrayOf(0x00, 0x00, 0x00, 0x01) + nalUnit
                inputBuffer?.put(frameData)

                decoder.queueInputBuffer(
                    inputIndex,
                    0,
                    frameData.size,
                    System.nanoTime() / 1000,
                    0
                )
                return true
            }
        } catch (e: Exception) {
            Log.e(TAG, "Decode error: ${e.message}")
        }

        return false
    }

    /**
     * Reset the decoder
     */
    fun reset() {
        isRunning.set(false)
        decoderThread?.interrupt()
        decoderThread = null

        try {
            decoder?.stop()
            decoder?.release()
        } catch (e: Exception) {
            Log.e(TAG, "Error releasing decoder: ${e.message}")
        }

        decoder = null
        sps = null
        pps = null
        isConfigured = false
        inputQueue.clear()

        Log.d(TAG, "Decoder reset")
    }
}

/**
 * Flutter Plugin for H.264 Decoder
 */
class H264DecoderPlugin(flutterEngine: FlutterEngine) {
    companion object {
        private const val METHOD_CHANNEL = "com.pocketremote/h264_decoder"
        private const val EVENT_CHANNEL = "com.pocketremote/h264_decoder_frames"
    }

    private val decoder = H264Decoder()
    private var eventSink: EventChannel.EventSink? = null

    init {
        // Method channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "decode" -> {
                        val data = call.arguments as? ByteArray
                        if (data != null) {
                            val success = decoder.decode(data)
                            result.success(success)
                        } else {
                            result.error("INVALID_ARGUMENT", "Expected byte array", null)
                        }
                    }
                    "reset" -> {
                        decoder.reset()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }

        // Event channel for decoded frames
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events

                    decoder.setFrameCallback { data, width, height ->
                        events?.success(mapOf(
                            "data" to data,
                            "width" to width,
                            "height" to height
                        ))
                    }
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                    decoder.setFrameCallback { _, _, _ -> }
                }
            })

        Log.d("H264DecoderPlugin", "Registered")
    }
}
