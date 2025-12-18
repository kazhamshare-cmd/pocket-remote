import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_webrtc/flutter_webrtc.dart';

/// WebRTC Data Channelを使った低遅延画面受信
class WebRTCService {
  RTCPeerConnection? _peerConnection;
  RTCDataChannel? _dataChannel;

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

    print('[WebRTC] Initialized');
  }

  void _setupDataChannel(RTCDataChannel channel) {
    print('[WebRTC] Setting up data channel: ${channel.label}');

    channel.onMessage = (RTCDataChannelMessage message) {
      if (message.isBinary) {
        // バイナリデータ（フレーム）を受信
        final frameData = Uint8List.fromList(message.binary);
        onFrame?.call(frameData);
      }
    };

    channel.onDataChannelState = (RTCDataChannelState state) {
      print('[WebRTC] Data channel state: $state');
    };
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
    print('[WebRTC] Closed');
  }

  /// 接続状態
  bool get isConnected {
    return _peerConnection?.connectionState ==
        RTCPeerConnectionState.RTCPeerConnectionStateConnected;
  }
}
