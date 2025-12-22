import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/services.dart';

/// H.264 Decoder using native platform APIs
/// iOS: VideoToolbox
/// Android: MediaCodec
class H264DecoderService {
  static const MethodChannel _methodChannel =
      MethodChannel('com.pocketremote/h264_decoder');
  static const EventChannel _eventChannel =
      EventChannel('com.pocketremote/h264_decoder_frames');

  StreamSubscription? _frameSubscription;
  Function(Uint8List data, int width, int height)? onFrame;

  bool _isInitialized = false;

  /// Initialize the decoder and start listening for frames
  Future<void> initialize() async {
    if (_isInitialized) return;

    _frameSubscription = _eventChannel.receiveBroadcastStream().listen(
      (event) {
        if (event is Map) {
          final data = event['data'] as Uint8List?;
          final width = event['width'] as int?;
          final height = event['height'] as int?;

          if (data != null && width != null && height != null) {
            onFrame?.call(data, width, height);
          }
        }
      },
      onError: (error) {
        print('[H264DecoderService] Stream error: $error');
      },
    );

    _isInitialized = true;
    print('[H264DecoderService] Initialized');
  }

  /// Decode H.264 data
  /// Returns true if decoding was successful
  Future<bool> decode(Uint8List h264Data) async {
    try {
      final result = await _methodChannel.invokeMethod<bool>('decode', h264Data);
      return result ?? false;
    } catch (e) {
      print('[H264DecoderService] Decode error: $e');
      return false;
    }
  }

  /// Reset the decoder state
  Future<void> reset() async {
    try {
      await _methodChannel.invokeMethod('reset');
      print('[H264DecoderService] Reset');
    } catch (e) {
      print('[H264DecoderService] Reset error: $e');
    }
  }

  /// Dispose resources
  void dispose() {
    _frameSubscription?.cancel();
    _frameSubscription = null;
    _isInitialized = false;
    print('[H264DecoderService] Disposed');
  }
}
