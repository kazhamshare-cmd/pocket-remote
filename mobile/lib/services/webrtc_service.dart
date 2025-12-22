import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'h264_decoder_service.dart';

/// WebRTC Data Channelを使った低遅延画面受信
class WebRTCService {
  RTCPeerConnection? _peerConnection;
  RTCDataChannel? _dataChannel;

  // H.264デコーダー
  final H264DecoderService _h264Decoder = H264DecoderService();
  bool _h264DecoderInitialized = false;

  // コールバック
  Function(String)? onIceCandidate;
  Function(String)? onAnswer;
  Function(Uint8List)? onFrame;
  Function(String)? onConnectionStateChange;

  /// WebRTC初期化
  Future<void> initialize() async {
    final configuration = <String, dynamic>{
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
        {'urls': 'stun:stun1.l.google.com:19302'},
      ],
    };

    _peerConnection = await createPeerConnection(configuration);

    // ICE候補イベント
    _peerConnection!.onIceCandidate = (RTCIceCandidate candidate) {
      print('[WebRTC] ICE candidate generated');
      if (onIceCandidate != null) {
        // JSON形式で送信
        onIceCandidate!(jsonEncode(candidate.toMap()));
      }
    };

    // 接続状態変更
    _peerConnection!.onConnectionState = (RTCPeerConnectionState state) {
      print('[WebRTC] Connection state: $state');
      onConnectionStateChange?.call(state.toString());
    };

    // Data Channel受信
    _peerConnection!.onDataChannel = (RTCDataChannel channel) {
      print('[WebRTC] Data channel received: ${channel.label}');
      _dataChannel = channel;
      _setupDataChannel(channel);
    };

    // H.264デコーダーを初期化
    await _initializeH264Decoder();

    print('[WebRTC] Initialized');
  }

  /// H.264デコーダーを初期化
  Future<void> _initializeH264Decoder() async {
    if (_h264DecoderInitialized) return;

    try {
      await _h264Decoder.initialize();

      // デコードされたフレームを受信
      _h264Decoder.onFrame = (data, width, height) {
        // BGRAデータをJPEGに変換して表示
        // (または直接Imageウィジェットで表示可能な形式に)
        _handleDecodedFrame(data, width, height);
      };

      _h264DecoderInitialized = true;
      print('[WebRTC] H.264 decoder initialized');
    } catch (e) {
      print('[WebRTC] Failed to initialize H.264 decoder: $e');
    }
  }

  /// デコードされたフレームを処理（ネイティブ側でJPEGに変換済み）
  void _handleDecodedFrame(Uint8List jpegData, int width, int height) {
    // ネイティブ側でJPEGに変換済みなのでそのまま渡す
    onFrame?.call(jpegData);
  }

  // H.264フラグメント再構成用バッファ
  final Map<int, Map<int, Uint8List>> _fragmentBuffers = {};

  void _setupDataChannel(RTCDataChannel channel) {
    print('[WebRTC] Setting up data channel: ${channel.label}');

    channel.onMessage = (RTCDataChannelMessage message) {
      if (message.isBinary && message.binary.isNotEmpty) {
        final data = Uint8List.fromList(message.binary);
        final codecType = data[0];

        switch (codecType) {
          case 0x00: // JPEG
            // 最初のバイト（コーデックマーカー）を除いて渡す
            if (data.length > 1) {
              onFrame?.call(data.sublist(1));
            }
            break;
          case 0x01: // H.264 single packet
            if (data.length > 1 && _h264DecoderInitialized) {
              _decodeH264(data.sublist(1));
            }
            break;
          case 0x02: // H.264 fragment
            if (data.length > 5) {
              _handleH264Fragment(data);
            }
            break;
          default:
            // 旧フォーマット（ヘッダーなし）の場合はそのまま渡す
            // JPEG画像はFFD8で始まる
            if (data.length > 2 && data[0] == 0xFF && data[1] == 0xD8) {
              onFrame?.call(data);
            }
        }
      }
    };

    channel.onDataChannelState = (RTCDataChannelState state) {
      print('[WebRTC] Data channel state: $state');
    };
  }

  /// H.264データをデコード
  Future<void> _decodeH264(Uint8List h264Data) async {
    if (!_h264DecoderInitialized) {
      print('[WebRTC] H.264 decoder not initialized');
      return;
    }

    final success = await _h264Decoder.decode(h264Data);
    if (!success) {
      print('[WebRTC] H.264 decode failed');
    }
  }

  void _handleH264Fragment(Uint8List data) {
    // ヘッダー: [0x02, fragment_index, total_fragments, frame_id(2bytes), ...]
    final fragmentIndex = data[1];
    final totalFragments = data[2];
    final frameId = (data[3] << 8) | data[4];
    final payload = data.sublist(5);

    // フレームIDごとにバッファを管理
    _fragmentBuffers.putIfAbsent(frameId, () => {});
    _fragmentBuffers[frameId]![fragmentIndex] = payload;

    // 全フラグメントが揃ったか確認
    if (_fragmentBuffers[frameId]!.length == totalFragments) {
      // フラグメントを結合
      final completeData = <int>[];
      for (int i = 0; i < totalFragments; i++) {
        if (_fragmentBuffers[frameId]![i] != null) {
          completeData.addAll(_fragmentBuffers[frameId]![i]!);
        }
      }
      _fragmentBuffers.remove(frameId);

      // 完全なH.264フレームをデコード
      if (_h264DecoderInitialized) {
        _decodeH264(Uint8List.fromList(completeData));
      }
    }

    // 古いフレームをクリーンアップ（3フレーム分のみ保持）
    if (_fragmentBuffers.length > 3) {
      final oldestFrameId = _fragmentBuffers.keys.reduce((a, b) => a < b ? a : b);
      _fragmentBuffers.remove(oldestFrameId);
    }
  }

  /// オファーを処理してアンサーを生成
  Future<String?> handleOffer(String sdp) async {
    if (_peerConnection == null) {
      print('[WebRTC] Peer connection not initialized');
      return null;
    }

    try {
      // オファーを設定
      final offer = RTCSessionDescription(sdp, 'offer');
      await _peerConnection!.setRemoteDescription(offer);
      print('[WebRTC] Remote description set');

      // アンサーを作成
      final answer = await _peerConnection!.createAnswer();
      await _peerConnection!.setLocalDescription(answer);
      print('[WebRTC] Answer created');

      return answer.sdp;
    } catch (e) {
      print('[WebRTC] Error handling offer: $e');
      return null;
    }
  }

  /// ICE候補を追加
  Future<void> addIceCandidate(Map<String, dynamic> candidateMap) async {
    if (_peerConnection == null) return;

    try {
      final candidate = RTCIceCandidate(
        candidateMap['candidate'] as String?,
        candidateMap['sdpMid'] as String?,
        candidateMap['sdpMLineIndex'] as int?,
      );
      await _peerConnection!.addCandidate(candidate);
      print('[WebRTC] ICE candidate added');
    } catch (e) {
      print('[WebRTC] Error adding ICE candidate: $e');
    }
  }

  /// 切断
  Future<void> close() async {
    _dataChannel?.close();
    _dataChannel = null;
    await _peerConnection?.close();
    _peerConnection = null;
    _h264Decoder.dispose();
    _h264DecoderInitialized = false;
    print('[WebRTC] Closed');
  }

  /// 接続状態
  bool get isConnected {
    return _peerConnection?.connectionState ==
        RTCPeerConnectionState.RTCPeerConnectionStateConnected;
  }
}
