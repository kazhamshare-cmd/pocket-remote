import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../services/websocket_service.dart';
import '../services/localization_service.dart';

class ScreenShareScreen extends ConsumerStatefulWidget {
  const ScreenShareScreen({super.key});

  @override
  ConsumerState<ScreenShareScreen> createState() => _ScreenShareScreenState();
}

class _ScreenShareScreenState extends ConsumerState<ScreenShareScreen> {
  final TextEditingController _textController = TextEditingController();
  final FocusNode _textFocusNode = FocusNode();
  Offset _lastFocalPoint = Offset.zero;
  bool _isDragging = false;
  AppWindowInfo? _focusedWindow; // ズーム中のウィンドウ
  Offset? _cursorPosition; // カーソル位置（ローカル座標）
  bool _showCursor = false; // カーソル表示フラグ
  bool _mouseMode = true; // マウス操作モード（true: マウス操作、false: 閲覧モード）
  bool _showKeyboardInput = false; // インライン入力表示フラグ
  bool _autoEnter = false; // 送信後にEnterを押すか
  bool _dragMode = false; // ドラッグモード（false: タップで移動、true: ドラッグ操作）
  DateTime? _lastTapTime; // ダブルタップ検出用
  bool _realtimeSync = false; // リアルタイム同期モード（日本語対応のためデフォルトオフ）
  Timer? _debounceTimer; // IME入力用debounceタイマー
  String _pendingText = ''; // debounce中の保留テキスト
  Timer? _scrollDebounceTimer; // スクロール停止検出用
  int _pointerCount = 0; // 2本指スクロール検出用
  Offset _lastScrollPosition = Offset.zero; // 2本指スクロール位置
  Offset _imageScrollOffset = Offset.zero; // 画像のスクロールオフセット
  String _lastSentText = ''; // 最後に送信したテキスト
  bool _useWebRTC = true; // WebRTCモード（常にWebRTC使用）

  @override
  void initState() {
    super.initState();
    // 画面共有開始 & アプリ一覧取得
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startScreenShare();
      ref.read(webSocketProvider.notifier).getRunningApps();
    });
    // 縦向き固定（パン・ズームで操作）
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
    // フルスクリーン
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  void _startScreenShare() {
    if (_useWebRTC) {
      // WebRTCモード（高速）
      ref.read(webSocketProvider.notifier).startWebRTCScreenShare();
    } else {
      // 従来のWebSocketモード
      ref.read(webSocketProvider.notifier).startScreenShare();
    }
  }

  void _stopScreenShare() {
    final state = ref.read(webSocketProvider);
    if (state.isWebRTCActive) {
      ref.read(webSocketProvider.notifier).stopWebRTCScreenShare();
    } else {
      ref.read(webSocketProvider.notifier).stopScreenShare();
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _scrollDebounceTimer?.cancel();
    _stopScreenShare();
    // 向きを元に戻す
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    // システムUIを元に戻す
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _textController.dispose();
    _textFocusNode.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails details, Size screenSize, ScreenInfo? screenInfo) {
    if (screenInfo == null || !_mouseMode) return;

    final now = DateTime.now();
    final isDoubleTap = _lastTapTime != null &&
        now.difference(_lastTapTime!).inMilliseconds < 300;

    // リモート座標を計算
    final remotePos = _screenToRemoteCoordinates(details.localPosition, screenSize, screenInfo);

    // デバッグログ
    print('[Touch] localPosition: ${details.localPosition}');
    print('[Touch] screenSize: $screenSize');
    print('[Touch] remotePos: $remotePos');
    print('[Touch] screenInfo: ${screenInfo.width}x${screenInfo.height}');
    if (_focusedWindow != null) {
      print('[Touch] focusedWindow: x=${_focusedWindow!.x}, y=${_focusedWindow!.y}, ${_focusedWindow!.width}x${_focusedWindow!.height}');
    }

    // カーソル位置を更新（画面表示エリアのtopPaddingを加算）
    final topPadding = MediaQuery.of(context).padding.top + 80;
    setState(() {
      _cursorPosition = Offset(details.localPosition.dx, details.localPosition.dy + topPadding);
      _showCursor = true;
    });

    if (isDoubleTap) {
      // ダブルタップ = クリック
      ref.read(webSocketProvider.notifier).sendMouseClick(
        remotePos.dx.toInt(),
        remotePos.dy.toInt(),
      );
      HapticFeedback.lightImpact();
      _lastTapTime = null;
    } else {
      // シングルタップ = マウス移動のみ
      ref.read(webSocketProvider.notifier).sendMouseMove(
        remotePos.dx.toInt(),
        remotePos.dy.toInt(),
      );
      _lastTapTime = now;
    }

    // カーソルを少し後に非表示にする
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted && !_isDragging) {
        setState(() {
          _showCursor = false;
        });
      }
    });
  }

  // 長押しで右クリック
  void _onLongPress(LongPressStartDetails details, Size screenSize, ScreenInfo? screenInfo) {
    if (screenInfo == null || !_mouseMode) return;

    final remotePos = _screenToRemoteCoordinates(details.localPosition, screenSize, screenInfo);

    // カーソル位置を更新（topPaddingを加算）
    final topPadding = MediaQuery.of(context).padding.top + 80;
    setState(() {
      _cursorPosition = Offset(details.localPosition.dx, details.localPosition.dy + topPadding);
      _showCursor = true;
    });

    // 右クリック
    ref.read(webSocketProvider.notifier).sendMouseClick(
      remotePos.dx.toInt(),
      remotePos.dy.toInt(),
      button: 'right',
    );

    // 触覚フィードバック
    HapticFeedback.mediumImpact();

    // カーソルを少し後に非表示にする
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted && !_isDragging) {
        setState(() {
          _showCursor = false;
        });
      }
    });
  }

  void _onPanStart(dynamic details, Size screenSize, ScreenInfo? screenInfo) {
    if (screenInfo == null || !_mouseMode) return;

    final localPos = details.localFocalPoint ?? details.localPosition;
    _lastFocalPoint = localPos;

    // カーソル位置を更新（topPaddingを加算）
    final topPadding = MediaQuery.of(context).padding.top + 80;
    setState(() {
      _cursorPosition = Offset(localPos.dx, localPos.dy + topPadding);
      _showCursor = true;
    });

    final remotePos = _screenToRemoteCoordinates(localPos, screenSize, screenInfo);

    if (_dragMode) {
      // ドラッグモード: マウスダウン
      _isDragging = true;
      ref.read(webSocketProvider.notifier).sendMouseDown(
        remotePos.dx.toInt(),
        remotePos.dy.toInt(),
      );
    } else {
      // 通常モード: マウス移動のみ
      ref.read(webSocketProvider.notifier).sendMouseMove(
        remotePos.dx.toInt(),
        remotePos.dy.toInt(),
      );
    }
  }

  void _onPanUpdate(dynamic details, Size screenSize, ScreenInfo? screenInfo) {
    if (screenInfo == null || !_mouseMode) return;

    final localPos = details.localFocalPoint ?? details.localPosition;

    // カーソル位置を更新（topPaddingを加算）
    final topPadding = MediaQuery.of(context).padding.top + 80;
    setState(() {
      _cursorPosition = Offset(localPos.dx, localPos.dy + topPadding);
    });

    final remotePos = _screenToRemoteCoordinates(localPos, screenSize, screenInfo);

    // 常にマウス移動を送信
    ref.read(webSocketProvider.notifier).sendMouseMove(
      remotePos.dx.toInt(),
      remotePos.dy.toInt(),
    );

    _lastFocalPoint = localPos;
  }

  void _onPanEnd(dynamic details, Size screenSize, ScreenInfo? screenInfo) {
    if (screenInfo == null || !_mouseMode) return;

    if (_dragMode && _isDragging) {
      // ドラッグモード: マウスアップ
      final remotePos = _screenToRemoteCoordinates(_lastFocalPoint, screenSize, screenInfo);
      ref.read(webSocketProvider.notifier).sendMouseUp(
        remotePos.dx.toInt(),
        remotePos.dy.toInt(),
      );
    }

    _isDragging = false;

    // カーソルを少し後に非表示にする
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) {
        setState(() {
          _showCursor = false;
        });
      }
    });
  }

  // 2本指スクロール処理（画像をパン）
  void _onTwoFingerScroll(Offset delta, Size displaySize, double actualImageHeight) {
    setState(() {
      // 新しいオフセットを計算
      var newOffset = _imageScrollOffset + delta;

      // 縦方向の制限（画像が表示エリアより大きい場合のみスクロール可能）
      if (actualImageHeight > displaySize.height) {
        final maxScrollY = actualImageHeight - displaySize.height;
        newOffset = Offset(
          0, // 横スクロールは無効
          newOffset.dy.clamp(-maxScrollY, 0),
        );
      } else {
        newOffset = Offset.zero;
      }

      _imageScrollOffset = newOffset;
    });
  }

  /// スクロール停止時の処理（高画質リクエストは廃止、シンプルにスクロール停止を待つだけ）
  void _scheduleHighQualityRequest(Size screenSize) {
    // 何もしない（PC側は常に同じ品質でキャプチャ）
    // 将来的に必要であれば、ここで高画質リクエストを送信
  }

  // 画像の実際の表示高さを計算
  double _calculateImageDisplayHeight(Uint8List imageData, double displayWidth) {
    // JPEG/PNGヘッダーから画像サイズを取得（簡易版）
    // JPEGの場合: FFD8で始まる
    // PNGの場合: 89504E47で始まる
    try {
      if (imageData.length > 24) {
        // PNGの場合
        if (imageData[0] == 0x89 && imageData[1] == 0x50) {
          // PNG IHDR chunk (width at offset 16-19, height at 20-23)
          final width = (imageData[16] << 24) | (imageData[17] << 16) | (imageData[18] << 8) | imageData[19];
          final height = (imageData[20] << 24) | (imageData[21] << 16) | (imageData[22] << 8) | imageData[23];
          if (width > 0 && height > 0) {
            final scale = displayWidth / width;
            return height * scale;
          }
        }
        // JPEGの場合 - SOF0/SOF2マーカーを探す
        else if (imageData[0] == 0xFF && imageData[1] == 0xD8) {
          for (int i = 2; i < imageData.length - 10; i++) {
            if (imageData[i] == 0xFF && (imageData[i + 1] == 0xC0 || imageData[i + 1] == 0xC2)) {
              final height = (imageData[i + 5] << 8) | imageData[i + 6];
              final width = (imageData[i + 7] << 8) | imageData[i + 8];
              if (width > 0 && height > 0) {
                final scale = displayWidth / width;
                return height * scale;
              }
            }
          }
        }
      }
    } catch (e) {
      // エラー時はデフォルト値を返す
    }
    // デフォルト: 16:9アスペクト比を仮定
    return displayWidth * 9 / 16;
  }

  Offset _getTransformedPosition(Offset localPosition) {
    // InteractiveViewerを削除したため、変換不要
    return localPosition;
  }

  // 画面タッチ位置からリモートPC座標に変換
  // スクロールオフセットとスケールを考慮
  Offset _screenToRemoteCoordinates(Offset screenPos, Size screenSize, ScreenInfo screenInfo) {
    // スクロールオフセットを考慮した画像内座標
    // _imageScrollOffset は負の値（スクロール = 画像が移動）
    final imageX = screenPos.dx - _imageScrollOffset.dx;
    final imageY = screenPos.dy - _imageScrollOffset.dy;

    if (_focusedWindow != null) {
      // フォーカスモード
      final window = _focusedWindow!;
      final pixelCount = window.width * window.height;

      // 送信される画像サイズを計算
      double sentWidth, sentHeight;
      if (pixelCount > 600000) {
        sentWidth = window.width / 2.0;
        sentHeight = window.height / 2.0;
      } else {
        sentWidth = window.width.toDouble();
        sentHeight = window.height.toDouble();
      }

      // 表示サイズを計算（高さに合わせてスケール）
      double displayScale = 1.0;
      if (sentHeight < screenSize.height) {
        displayScale = screenSize.height / sentHeight;
      }

      // 表示座標 → 送信画像座標 → リモート座標
      final sentImageX = imageX / displayScale;
      final sentImageY = imageY / displayScale;

      double remoteX, remoteY;
      if (pixelCount > 600000) {
        // Large window: 送信サイズの2倍がウィンドウサイズ
        remoteX = sentImageX * 2.0 + window.x;
        remoteY = sentImageY * 2.0 + window.y;
      } else {
        // Small/Medium window: 送信サイズ = ウィンドウサイズ
        remoteX = sentImageX + window.x;
        remoteY = sentImageY + window.y;
      }

      return Offset(
        remoteX.clamp(0, screenInfo.width.toDouble()),
        remoteY.clamp(0, screenInfo.height.toDouble()),
      );
    } else {
      // 通常モード: PC画面全体を1/2サイズで表示
      // 画像座標をPC座標に変換（2倍にスケールアップ）
      final remoteX = imageX * 2.0;
      final remoteY = imageY * 2.0;

      return Offset(
        remoteX.clamp(0, screenInfo.width.toDouble()),
        remoteY.clamp(0, screenInfo.height.toDouble()),
      );
    }
  }

  // PCのマウス座標を画像内のピクセル座標に変換（横幅100%表示用）
  Offset? _convertPcMouseToImageCoordinates(MousePosition? pcMouse, ScreenInfo? screenInfo) {
    if (pcMouse == null || screenInfo == null) return null;

    // フォーカスモードかどうかで処理を分岐
    if (_focusedWindow != null) {
      // フォーカスモード: ウィンドウ領域のみ表示（原寸）
      final window = _focusedWindow!;

      // PCマウスがウィンドウ領域外にある場合はnull
      if (pcMouse.x < window.x || pcMouse.x > window.x + window.width ||
          pcMouse.y < window.y || pcMouse.y > window.y + window.height) {
        return null;
      }

      // ウィンドウ内のピクセル座標（原寸なのでそのまま）
      final imageX = (pcMouse.x - window.x).toDouble();
      final imageY = (pcMouse.y - window.y).toDouble();

      return Offset(imageX, imageY);
    } else {
      // 通常モード: PC画面全体を1/2サイズで表示
      // PC座標を画像座標に変換（1/2スケール）
      final imageX = pcMouse.x / 2.0;
      final imageY = pcMouse.y / 2.0;

      return Offset(imageX, imageY);
    }
  }

  Offset _convertToRemoteCoordinates(Offset localPos, Size screenSize, ScreenInfo screenInfo) {
    // フォーカスモードかどうかで処理を分岐
    if (_focusedWindow != null) {
      // フォーカスモード: 画像はウィンドウ領域そのまま（縮小なし）
      final window = _focusedWindow!;
      final imagePixelWidth = window.width.toDouble();
      final imagePixelHeight = window.height.toDouble();

      // 画像の表示サイズを計算（BoxFit.contain）
      final aspectRatio = imagePixelWidth / imagePixelHeight;
      final screenAspectRatio = screenSize.width / screenSize.height;

      double displayWidth, displayHeight, offsetX, offsetY;

      if (aspectRatio > screenAspectRatio) {
        displayWidth = screenSize.width;
        displayHeight = screenSize.width / aspectRatio;
        offsetX = 0;
        offsetY = (screenSize.height - displayHeight) / 2;
      } else {
        displayHeight = screenSize.height;
        displayWidth = screenSize.height * aspectRatio;
        offsetX = (screenSize.width - displayWidth) / 2;
        offsetY = 0;
      }

      // 画像内の相対位置を計算（0.0〜1.0）
      final relativeX = (localPos.dx - offsetX) / displayWidth;
      final relativeY = (localPos.dy - offsetY) / displayHeight;

      // ウィンドウ内座標 + ウィンドウオフセット = 画面座標
      final remoteX = relativeX * imagePixelWidth + window.x;
      final remoteY = relativeY * imagePixelHeight + window.y;

      return Offset(
        remoteX.clamp(0, screenInfo.width.toDouble()),
        remoteY.clamp(0, screenInfo.height.toDouble()),
      );
    } else {
      // 通常モード: 画像は1/2サイズで受信
      // 画像のピクセルサイズ（受信したJPEGのサイズ）
      final imagePixelWidth = screenInfo.width / 2.0;
      final imagePixelHeight = screenInfo.height / 2.0;

      // 画像の表示サイズを計算（BoxFit.contain）
      final aspectRatio = imagePixelWidth / imagePixelHeight;
      final screenAspectRatio = screenSize.width / screenSize.height;

      double displayWidth, displayHeight, offsetX, offsetY;

      if (aspectRatio > screenAspectRatio) {
        // 画像は幅いっぱいに表示、上下に余白
        displayWidth = screenSize.width;
        displayHeight = screenSize.width / aspectRatio;
        offsetX = 0;
        offsetY = (screenSize.height - displayHeight) / 2;
      } else {
        // 画像は高さいっぱいに表示、左右に余白
        displayHeight = screenSize.height;
        displayWidth = screenSize.height * aspectRatio;
        offsetX = (screenSize.width - displayWidth) / 2;
        offsetY = 0;
      }

      // タッチ位置から画像内の相対位置を計算（0.0〜1.0）
      final relativeX = (localPos.dx - offsetX) / displayWidth;
      final relativeY = (localPos.dy - offsetY) / displayHeight;

      // 相対位置からリモートPC画面座標に変換
      // 画像は1/2サイズだが、screenInfoは元のサイズなので直接使える
      final remoteX = relativeX * screenInfo.width;
      final remoteY = relativeY * screenInfo.height;

      return Offset(
        remoteX.clamp(0, screenInfo.width.toDouble()),
        remoteY.clamp(0, screenInfo.height.toDouble()),
      );
    }
  }

  // 指定されたウィンドウにズーム（高解像度キャプチャ）
  void _zoomToWindow(AppWindowInfo windowInfo, Size screenSize, ScreenInfo? screenInfo) {
    if (screenInfo == null) return;

    print('[ZoomToWindow] === START ===');
    print('[ZoomToWindow] App: ${windowInfo.appName}');
    print('[ZoomToWindow] Window: x=${windowInfo.x}, y=${windowInfo.y}, ${windowInfo.width}x${windowInfo.height}');
    print('[ZoomToWindow] ScreenSize: ${screenSize.width}x${screenSize.height}');

    // 小さすぎるウィンドウはスキップ（サイドバーや補助ウィンドウの可能性）
    if (windowInfo.width < 100 || windowInfo.height < 100) {
      print('[ZoomToWindow] Window too small, skipping');
      return;
    }

    setState(() {
      _focusedWindow = windowInfo;
      _imageScrollOffset = Offset.zero; // スクロールをリセット
    });

    // ウィンドウ全体をキャプチャ（スマホでスクロールして閲覧）
    int captureX = windowInfo.x;
    int captureY = windowInfo.y;
    int captureWidth = windowInfo.width;
    int captureHeight = windowInfo.height;

    print('[ZoomToWindow] Capture region: x=$captureX, y=$captureY, ${captureWidth}x$captureHeight (full window)');

    // キャプチャ領域を設定（リサイズなし、即時反映）
    ref.read(webSocketProvider.notifier).setCaptureRegion(
      captureX,
      captureY,
      captureWidth,
      captureHeight,
    );
  }

  // ズームをリセット（全画面キャプチャに戻す）
  void _resetZoom() {
    setState(() {
      _focusedWindow = null;
      _imageScrollOffset = Offset.zero; // スクロールもリセット
    });

    // サーバーに全画面キャプチャに戻すよう指示
    ref.read(webSocketProvider.notifier).resetCaptureRegion();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(webSocketProvider);

    // 接続が切れたら戻る
    if (state.connectionState == WsConnectionState.disconnected ||
        state.connectionState == WsConnectionState.error) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go('/');
      });
    }

    // ヘッダー用の上部スペース（SafeArea + ヘッダー高さ）
    final topPadding = MediaQuery.of(context).padding.top + 80;
    // 画面表示エリアの固定高さ
    const double screenDisplayHeight = 380;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 画面表示（固定高さ）
          if (state.currentFrame != null)
            Positioned(
              top: topPadding,
              left: 0,
              right: 0,
              height: screenDisplayHeight,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final screenSize = Size(constraints.maxWidth, screenDisplayHeight);

                  // 画像サイズを計算
                  // デスクトップは600,000ピクセル以上のウィンドウを1/2サイズで送信
                  double imageWidth, imageHeight;
                  if (_focusedWindow != null) {
                    final pixelCount = _focusedWindow!.width * _focusedWindow!.height;
                    if (pixelCount > 600000) {
                      // Large window: 1/2サイズで送信される
                      imageWidth = _focusedWindow!.width / 2.0;
                      imageHeight = _focusedWindow!.height / 2.0;
                    } else {
                      // Small/Medium window: 原寸で送信される
                      imageWidth = _focusedWindow!.width.toDouble();
                      imageHeight = _focusedWindow!.height.toDouble();
                    }
                    // 画像が表示エリアより小さい場合はスケールアップ
                    if (imageHeight < screenDisplayHeight) {
                      final scale = screenDisplayHeight / imageHeight;
                      imageWidth = imageWidth * scale;
                      imageHeight = screenDisplayHeight;
                    }
                  } else {
                    // 通常モード: PC画面の1/2サイズ
                    imageWidth = (state.screenInfo?.width ?? 1920) / 2.0;
                    imageHeight = (state.screenInfo?.height ?? 1080) / 2.0;
                  }

                  // スクロール可能な最大量（画像が画面より大きい場合のみスクロール可能）
                  final maxScrollX = (imageWidth - screenSize.width).clamp(0.0, double.infinity);
                  final maxScrollY = (imageHeight - screenDisplayHeight).clamp(0.0, double.infinity);

                  // ウィンドウモード: 横スクロールはローカル（画面パン）、縦スクロールはPC
                  // 通常モード: 両方ローカルスクロール
                  final clampedScrollOffset = Offset(
                    _imageScrollOffset.dx.clamp(-maxScrollX, 0.0),
                    _focusedWindow != null
                        ? 0.0  // ウィンドウモードでは縦スクロールはPC側
                        : _imageScrollOffset.dy.clamp(-maxScrollY, 0.0),
                  );

                  return GestureDetector(
                    onTapDown: (details) => _onTapDown(details, screenSize, state.screenInfo),
                    onLongPressStart: (details) => _onLongPress(details, screenSize, state.screenInfo),
                    onScaleStart: (details) {
                      _pointerCount = details.pointerCount;
                      _lastScrollPosition = details.focalPoint;
                      if (details.pointerCount == 1) {
                        _onPanStart(details, screenSize, state.screenInfo);
                      }
                    },
                    onScaleUpdate: (details) {
                      if (details.pointerCount >= 2) {
                        // 2本指スクロール → PC側に直接送信（シンプル化）
                        final delta = details.focalPoint - _lastScrollPosition;
                        _lastScrollPosition = details.focalPoint;

                        if (_focusedWindow != null) {
                          // 横方向: ローカルパン（画面内を移動）
                          final currentDx = _imageScrollOffset.dx;
                          final newDx = currentDx + delta.dx;
                          final clampedDx = newDx.clamp(-maxScrollX, 0.0);
                          print('[HorizontalPan] delta.dx=${delta.dx.toStringAsFixed(1)}, currentDx=${currentDx.toStringAsFixed(1)}, newDx=${newDx.toStringAsFixed(1)}, maxScrollX=${maxScrollX.toStringAsFixed(1)}, clampedDx=${clampedDx.toStringAsFixed(1)}');
                          setState(() {
                            _imageScrollOffset = Offset(
                              clampedDx,
                              _imageScrollOffset.dy,
                            );
                          });

                          // 縦方向: PC側にスクロールを送信
                          // スクロール位置をリモート座標に変換してマウスを移動
                          final scrollPos = _screenToRemoteCoordinates(
                            details.localFocalPoint,
                            screenSize,
                            state.screenInfo!,
                          );
                          ref.read(webSocketProvider.notifier).sendMouseMove(
                            scrollPos.dx.toInt(),
                            scrollPos.dy.toInt(),
                          );

                          // Y方向のスクロール量をPC側に送信
                          // 指を上に動かす → 下を見る（コンテンツを上にスクロール）
                          // delta.dyを反転してナチュラルスクロールに
                          final scrollAmount = (-delta.dy * 5).toInt(); // 感度調整 + 方向反転
                          if (scrollAmount.abs() > 5) {
                            ref.read(webSocketProvider.notifier).sendScroll(0, scrollAmount);
                          }
                        } else {
                          // 通常モード: ローカルスクロール
                          final currentDx = _imageScrollOffset.dx;
                          final currentDy = _imageScrollOffset.dy;
                          final newDx = currentDx + delta.dx;
                          final newDy = currentDy + delta.dy;
                          setState(() {
                            _imageScrollOffset = Offset(
                              newDx.clamp(-maxScrollX, 0),
                              newDy.clamp(-maxScrollY, 0),
                            );
                          });
                        }
                      } else if (_pointerCount == 1) {
                        // 1本指はマウス操作
                        _onPanUpdate(details, screenSize, state.screenInfo);
                      }
                    },
                    onScaleEnd: (details) {
                      if (_pointerCount == 1) {
                        _onPanEnd(details, screenSize, state.screenInfo);
                      }
                      _pointerCount = 0;
                    },
                    child: Container(
                      width: screenSize.width,
                      height: screenDisplayHeight,
                      clipBehavior: Clip.hardEdge,
                      decoration: const BoxDecoration(),
                      child: Stack(
                        children: [
                          Positioned(
                            left: clampedScrollOffset.dx,
                            top: clampedScrollOffset.dy,
                            width: imageWidth,
                            height: imageHeight,
                            child: Image.memory(
                              state.currentFrame!,
                              gaplessPlayback: true,
                              fit: BoxFit.fill,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
          )
          else
            const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: Color(0xFFe94560)),
                  SizedBox(height: 16),
                  Text(
                    '画面を読み込み中...',
                    style: TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ),

          // PCマウスカーソル表示（画像の上にオーバーレイ）
          if (state.currentFrame != null && _mouseMode && state.pcMousePosition != null)
            Positioned(
              top: MediaQuery.of(context).padding.top + 80,
              left: 0,
              right: 0,
              height: screenDisplayHeight,
              child: IgnorePointer(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final screenSize = Size(constraints.maxWidth, screenDisplayHeight);
                    final pcMouse = state.pcMousePosition!;

                    // PCマウス座標を画面座標に変換（スケールとスクロールオフセット考慮）
                    double cursorX, cursorY;
                    if (_focusedWindow != null) {
                      final window = _focusedWindow!;
                      final pixelCount = window.width * window.height;
                      if (pixelCount > 600000) {
                        // Large window: 1/2サイズで表示
                        cursorX = (pcMouse.x - window.x) / 2.0 + _imageScrollOffset.dx;
                        cursorY = (pcMouse.y - window.y) / 2.0 + _imageScrollOffset.dy;
                      } else {
                        // Small/Medium window: 原寸
                        cursorX = (pcMouse.x - window.x) + _imageScrollOffset.dx;
                        cursorY = (pcMouse.y - window.y) + _imageScrollOffset.dy;
                      }
                    } else {
                      // 通常モード: PC座標/2（1/2サイズ画像）+ スクロールオフセット
                      cursorX = (pcMouse.x / 2.0) + _imageScrollOffset.dx;
                      cursorY = (pcMouse.y / 2.0) + _imageScrollOffset.dy;
                    }

                    // カーソルが表示範囲外なら表示しない
                    if (cursorX < 0 || cursorX > screenSize.width ||
                        cursorY < 0 || cursorY > screenDisplayHeight) {
                      return const SizedBox.shrink();
                    }

                    return Stack(
                      children: [
                        Positioned(
                          left: cursorX - 1,
                          top: cursorY - 1,
                          child: CustomPaint(
                            size: const Size(20, 24),
                            painter: _CursorPainter(),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),

          // タッチカーソル表示
          if (_showCursor && _cursorPosition != null)
            Positioned(
              left: _cursorPosition!.dx - 12,
              top: _cursorPosition!.dy - 12,
              child: IgnorePointer(
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.3),
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFFe94560), width: 2),
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.touch_app,
                      color: Color(0xFFe94560),
                      size: 14,
                    ),
                  ),
                ),
              ),
            ),

          // 上部コントロールバー
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Consumer(
              builder: (context, ref, _) {
                final l10n = ref.watch(l10nProvider);
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.85),
                        Colors.transparent,
                      ],
                    ),
                  ),
                  child: SafeArea(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // 上段: 戻るボタン、ステータス、更新
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            // 戻るボタン
                            IconButton(
                              icon: const Icon(Icons.arrow_back, color: Colors.white),
                              onPressed: () {
                                _stopScreenShare();
                                context.go('/commands');
                              },
                            ),
                            // ステータスインジケーター
                            Row(
                              children: [
                                // 接続状態
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: state.currentFrame != null ? Colors.green : Colors.orange,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '${state.screenInfo?.width ?? 0}x${state.screenInfo?.height ?? 0}',
                                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                                ),
                                const SizedBox(width: 12),
                                // モードインジケーター
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: _mouseMode
                                        ? const Color(0xFFe94560).withValues(alpha: 0.3)
                                        : Colors.white.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        _mouseMode ? Icons.mouse : Icons.visibility,
                                        color: _mouseMode ? const Color(0xFFe94560) : Colors.white70,
                                        size: 12,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        _mouseMode ? l10n.mouse : l10n.view,
                                        style: TextStyle(
                                          color: _mouseMode ? const Color(0xFFe94560) : Colors.white70,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        // 下段: 操作ガイド（マウスモード時のみ表示）
                        if (_mouseMode)
                          Container(
                            margin: const EdgeInsets.only(top: 4),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.4),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _operationHint(Icons.touch_app, _dragMode ? l10n.swipeToDrag : l10n.tapToMove),
                                const SizedBox(width: 12),
                                _operationHint(Icons.ads_click, l10n.doubleTapToClick),
                                const SizedBox(width: 12),
                                _operationHint(Icons.pan_tool, l10n.longPressForRightClick),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          // 下部ツールバー（キーボード入力時は非表示）
          if (!_showKeyboardInput)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Consumer(
              builder: (context, ref, _) {
                final l10n = ref.watch(l10nProvider);
                return Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.9),
                        Colors.transparent,
                      ],
                    ),
                  ),
                  child: SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          // 画面表示エリアの固定高さを使用（screenDisplayHeight = 380）
                          final screenSize = Size(constraints.maxWidth, screenDisplayHeight);
                          return SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                // アプリ切り替え
                                _toolbarButton(
                                  icon: Icons.apps,
                                  label: l10n.apps,
                                  onTap: () => _showAppsSheet(state.runningApps, screenSize, state.screenInfo),
                                ),
                                // マウスモード切り替え
                                _toolbarToggleButton(
                                  icon: Icons.mouse,
                                  label: _mouseMode ? l10n.mouse : l10n.view,
                                  isActive: _mouseMode,
                                  onTap: () {
                                    setState(() {
                                      _mouseMode = !_mouseMode;
                                    });
                                    // モード切り替え時に触覚フィードバック
                                    HapticFeedback.lightImpact();
                                  },
                                ),
                                // ズームリセット or Finder
                                if (_focusedWindow != null)
                                  _toolbarButton(
                                    icon: Icons.zoom_out_map,
                                    label: l10n.reset,
                                    onTap: _resetZoom,
                                  )
                                else
                                  _toolbarButton(
                                    icon: Icons.folder,
                                    label: l10n.finder,
                                    onTap: () => _showFinderSheet(),
                                  ),
                                // 閉じる（Cmd+W）
                                _toolbarButton(
                                  icon: Icons.close,
                                  label: l10n.closeWindow,
                                  onTap: () {
                                    ref.read(webSocketProvider.notifier).closeWindow();
                                  },
                                ),
                                // キーボード
                                _toolbarButton(
                                  icon: Icons.keyboard,
                                  label: l10n.keyboard,
                                  onTap: () {
                                    setState(() {
                                      _showKeyboardInput = !_showKeyboardInput;
                                      if (_showKeyboardInput) {
                                        _textFocusNode.requestFocus();
                                      }
                                    });
                                  },
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          // インライン入力フィールド（ツールバーの代わりに表示）
          if (_showKeyboardInput)
            Positioned(
              bottom: MediaQuery.of(context).padding.bottom,
              left: 0,
              right: 0,
              child: _buildInlineKeyboardInput(),
            ),
        ],
      ),
    );
  }

  Widget _buildInlineKeyboardInput() {
    final state = ref.read(webSocketProvider);
    final targetAppName = state.targetApp ??
        state.runningApps.where((app) => app.isActive).firstOrNull?.name;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF16213e).withOpacity(0.95),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 10,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 送信先表示とモード切り替え
          Row(
            children: [
              const Icon(Icons.send, color: Color(0xFFe94560), size: 14),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  targetAppName ?? '不明なアプリ',
                  style: const TextStyle(
                    color: Color(0xFFe94560),
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // リアルタイム同期切り替え
              GestureDetector(
                onTap: () {
                  setState(() {
                    _realtimeSync = !_realtimeSync;
                    if (!_realtimeSync) {
                      _lastSentText = '';
                    }
                  });
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _realtimeSync
                        ? Colors.green.withOpacity(0.3)
                        : Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _realtimeSync ? Icons.sync : Icons.sync_disabled,
                        color: _realtimeSync ? Colors.green : Colors.white54,
                        size: 14,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _realtimeSync ? 'リアルタイム' : '手動送信',
                        style: TextStyle(
                          color: _realtimeSync ? Colors.green : Colors.white54,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // 自動Enter切り替え
              GestureDetector(
                onTap: () {
                  setState(() {
                    _autoEnter = !_autoEnter;
                  });
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _autoEnter
                        ? const Color(0xFFe94560).withOpacity(0.3)
                        : Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.keyboard_return,
                        color: _autoEnter ? const Color(0xFFe94560) : Colors.white54,
                        size: 14,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Enter',
                        style: TextStyle(
                          color: _autoEnter ? const Color(0xFFe94560) : Colors.white54,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () {
                  setState(() {
                    _showKeyboardInput = false;
                    _textController.clear();
                    _lastSentText = '';
                  });
                },
                child: const Icon(Icons.close, color: Colors.white54, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // 入力フィールドと送信ボタン
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _textController,
                  focusNode: _textFocusNode,
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                  decoration: InputDecoration(
                    hintText: _realtimeSync ? '入力するとリアルタイムで反映...' : '入力...',
                    hintStyle: const TextStyle(color: Colors.white38, fontSize: 14),
                    filled: true,
                    fillColor: const Color(0xFF1a1a2e),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                        color: _realtimeSync ? Colors.green : const Color(0xFFe94560),
                        width: 2,
                      ),
                    ),
                  ),
                  onChanged: _realtimeSync ? _onTextChanged : null,
                  onSubmitted: (text) {
                    if (_autoEnter) {
                      ref.read(webSocketProvider.notifier).pressKey('enter');
                    }
                    if (!_realtimeSync) {
                      _sendText();
                    }
                    // フィールドをクリアして次の入力に備える
                    _textController.clear();
                    _lastSentText = '';
                    _textFocusNode.requestFocus();
                  },
                ),
              ),
              const SizedBox(width: 8),
              // 送信ボタン（リアルタイムモードではEnter送信）
              GestureDetector(
                onTap: () {
                  if (_realtimeSync) {
                    // リアルタイムモード: Enterを送信してクリア
                    ref.read(webSocketProvider.notifier).pressKey('enter');
                    _textController.clear();
                    _lastSentText = '';
                  } else {
                    // 手動モード: テキストを送信
                    _sendText();
                  }
                  _textFocusNode.requestFocus();
                },
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _realtimeSync ? Colors.green : const Color(0xFFe94560),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    _realtimeSync ? Icons.keyboard_return : Icons.send,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // ショートカット（横スクロール1行）
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                // 特殊キー
                _compactKeyButton('Tab', 'tab'),
                _compactKeyButton('⇧Tab', 'shift+tab'),
                _compactKeyButton('Esc', 'escape'),
                _compactKeyButton('⌫', 'backspace'),
                // ショートカット
                _compactKeyButton('⌘C', 'cmd+c'),
                _compactKeyButton('⌘V', 'cmd+v'),
                _compactKeyButton('⌘A', 'cmd+a'),
                _compactKeyButton('⌘Z', 'cmd+z'),
                _compactKeyButton('⌘S', 'cmd+s'),
                // コマンド
                _commandShortcut('git pull', 'git pull'),
                _commandShortcut('git push', 'git push'),
                _commandShortcut('git status', 'git status'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // リアルタイムテキスト同期（ASCII文字のみ対応）
  void _onTextChanged(String newText) {
    // リアルタイム同期が無効の場合は何もしない
    // 送信ボタンで一括送信する
    if (!_realtimeSync) {
      return;
    }

    // 非ASCII文字（日本語など）が含まれる場合はリアルタイム同期しない
    final hasNonAscii = newText.runes.any((r) => r > 127);
    if (hasNonAscii) {
      _pendingText = newText;
      return; // 送信しない
    }

    // ASCII入力のみ: 即座に送信
    if (newText.length > _lastSentText.length) {
      final addedText = newText.substring(_lastSentText.length);
      ref.read(webSocketProvider.notifier).typeText(addedText);
    } else if (newText.length < _lastSentText.length) {
      final deleteCount = _lastSentText.length - newText.length;
      for (var i = 0; i < deleteCount; i++) {
        ref.read(webSocketProvider.notifier).pressKey('backspace');
      }
    }
    _lastSentText = newText;
    _pendingText = newText;
  }

  void _sendText() {
    final text = _textController.text;
    if (text.isNotEmpty) {
      if (_autoEnter) {
        ref.read(webSocketProvider.notifier).typeTextAndEnter(text);
      } else {
        ref.read(webSocketProvider.notifier).typeText(text);
      }
      _textController.clear();
      // 状態をリセット
      _lastSentText = '';
      _pendingText = '';
    }
    // フォーカスを維持
    _textFocusNode.requestFocus();
  }

  Widget _operationHint(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Colors.white54, size: 12),
        const SizedBox(width: 4),
        Text(
          text,
          style: const TextStyle(color: Colors.white54, fontSize: 10),
        ),
      ],
    );
  }

  Widget _compactKeyButton(String label, String key) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: () {
          ref.read(webSocketProvider.notifier).pressKey(key);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFF1a1a2e),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.white24),
          ),
          child: Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ),
      ),
    );
  }

  // コマンドショートカット（テキストを送信してEnter）
  Widget _commandShortcut(String label, String command) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: () {
          // コマンドを入力してEnterを送信
          ref.read(webSocketProvider.notifier).typeText(command);
          ref.read(webSocketProvider.notifier).pressKey('enter');
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFF0f3460),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: const Color(0xFFe94560).withOpacity(0.5)),
          ),
          child: Text(
            label,
            style: const TextStyle(color: Color(0xFFe94560), fontSize: 11),
          ),
        ),
      ),
    );
  }

  Widget _toolbarButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 24),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(color: Colors.white70, fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }

  Widget _toolbarToggleButton({
    required IconData icon,
    required String label,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFFe94560).withValues(alpha: 0.3) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isActive ? const Color(0xFFe94560) : Colors.transparent,
            width: 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isActive ? const Color(0xFFe94560) : Colors.white54,
              size: 24,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: isActive ? const Color(0xFFe94560) : Colors.white54,
                fontSize: 10,
                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAppsSheet(List<RunningApp> apps, Size screenSize, ScreenInfo? screenInfo) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF16213e),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '起動中のアプリ',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            if (apps.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Text(
                    'アプリを取得中...',
                    style: TextStyle(color: Colors.white54),
                  ),
                ),
              )
            else
              SizedBox(
                height: 300,
                child: ListView.builder(
                  itemCount: apps.length,
                  itemBuilder: (context, index) {
                    final app = apps[index];
                    final lowerName = app.name.toLowerCase();
                    final isBrowser = lowerName.contains('safari') ||
                                      lowerName.contains('chrome');
                    final isTerminal = lowerName.contains('terminal') ||
                                       lowerName.contains('iterm');
                    final hasSubMenu = isBrowser || isTerminal;
                    return ListTile(
                      leading: Icon(
                        app.isActive ? Icons.check_circle : Icons.circle_outlined,
                        color: app.isActive ? Colors.green : Colors.white54,
                      ),
                      title: Text(
                        app.name,
                        style: TextStyle(
                          color: app.isActive ? Colors.white : Colors.white70,
                          fontWeight: app.isActive ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (hasSubMenu)
                            Icon(
                              isTerminal ? Icons.terminal : Icons.tab,
                              color: Colors.white38,
                              size: 20,
                            ),
                          const SizedBox(width: 8),
                          // 終了ボタン
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.red, size: 20),
                            onPressed: () {
                              Navigator.pop(context);
                              _showQuitAppDialog(app.name);
                            },
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      ),
                      onTap: () {
                        Navigator.pop(context);
                        // Messagesアプリの場合は専用のチャット一覧を表示
                        if (app.name.toLowerCase() == 'messages') {
                          _showMessagesChatsSheet(screenSize, screenInfo);
                        } else {
                          // まずウィンドウ一覧を取得して表示
                          _showAppWindowsSheet(app.name, screenSize, screenInfo, isBrowser, isTerminal);
                        }
                      },
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  // アプリのウィンドウ一覧を表示
  void _showAppWindowsSheet(String appName, Size screenSize, ScreenInfo? screenInfo, bool isBrowser, bool isTerminal) {
    // ウィンドウ一覧を取得
    ref.read(webSocketProvider.notifier).getAppWindows(appName);

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF16213e),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.4,
        minChildSize: 0.2,
        maxChildSize: 0.7,
        expand: false,
        builder: (context, scrollController) => Consumer(
          builder: (context, ref, _) {
            final state = ref.watch(webSocketProvider);
            return Container(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.window, color: Colors.white),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '$appName のウィンドウ',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.refresh, color: Colors.white54),
                        onPressed: () {
                          ref.read(webSocketProvider.notifier).getAppWindows(appName);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'ウィンドウを選択してください',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  const SizedBox(height: 16),
                  if (state.appWindows.isEmpty)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: Text(
                          'ウィンドウを取得中...',
                          style: TextStyle(color: Colors.white54),
                        ),
                      ),
                    )
                  else
                    Expanded(
                      child: ListView.builder(
                        controller: scrollController,
                        itemCount: state.appWindows.length,
                        itemBuilder: (context, index) {
                          final window = state.appWindows[index];
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: window.isMinimized
                                  ? Colors.grey.withOpacity(0.3)
                                  : const Color(0xFF1a1a2e),
                              radius: 16,
                              child: Text(
                                '${window.index}',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            title: Text(
                              window.title.isEmpty ? '(タイトルなし)' : window.title,
                              style: const TextStyle(color: Colors.white),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: window.isMinimized
                                ? const Text(
                                    '最小化中',
                                    style: TextStyle(color: Colors.orange, fontSize: 11),
                                  )
                                : null,
                            trailing: const Icon(
                              Icons.arrow_forward_ios,
                              color: Colors.white38,
                              size: 16,
                            ),
                            onTap: () {
                              Navigator.pop(context);
                              // 選択したウィンドウをフォーカス
                              ref.read(webSocketProvider.notifier).focusAppWindow(appName, window.index);
                              // その後ズーム
                              Future.delayed(const Duration(milliseconds: 300), () {
                                _zoomToApp(appName, screenSize, screenInfo);
                              });
                              // ブラウザの場合のみタブ一覧を表示（ターミナルは不要）
                              if (isBrowser) {
                                Future.delayed(const Duration(milliseconds: 800), () {
                                  _showBrowserTabsSheet(appName);
                                });
                              }
                            },
                          );
                        },
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  // Messagesアプリのチャット一覧を表示
  void _showMessagesChatsSheet(Size screenSize, ScreenInfo? screenInfo) {
    // チャット一覧を取得
    ref.read(webSocketProvider.notifier).getMessagesChats();

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF16213e),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.2,
        maxChildSize: 0.8,
        expand: false,
        builder: (context, scrollController) => Consumer(
          builder: (context, ref, _) {
            final state = ref.watch(webSocketProvider);
            return Container(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.message, color: Colors.green),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'メッセージ',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.refresh, color: Colors.white54),
                        onPressed: () {
                          ref.read(webSocketProvider.notifier).getMessagesChats();
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'チャットを選択してください',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  const SizedBox(height: 16),
                  if (state.messagesChats.isEmpty)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: Text(
                          'チャットを取得中...',
                          style: TextStyle(color: Colors.white54),
                        ),
                      ),
                    )
                  else
                    Expanded(
                      child: ListView.builder(
                        controller: scrollController,
                        itemCount: state.messagesChats.length,
                        itemBuilder: (context, index) {
                          final chat = state.messagesChats[index];
                          final isIMessage = chat.service.toLowerCase().contains('imessage');
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: isIMessage
                                  ? Colors.blue.withOpacity(0.3)
                                  : Colors.green.withOpacity(0.3),
                              radius: 20,
                              child: Icon(
                                isIMessage ? Icons.apple : Icons.sms,
                                color: isIMessage ? Colors.blue : Colors.green,
                                size: 20,
                              ),
                            ),
                            title: Text(
                              chat.name.isEmpty ? '(名前なし)' : chat.name,
                              style: const TextStyle(color: Colors.white),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              isIMessage ? 'iMessage' : 'SMS',
                              style: TextStyle(
                                color: isIMessage ? Colors.blue.shade300 : Colors.green.shade300,
                                fontSize: 11,
                              ),
                            ),
                            trailing: const Icon(
                              Icons.arrow_forward_ios,
                              color: Colors.white38,
                              size: 16,
                            ),
                            onTap: () {
                              Navigator.pop(context);
                              // チャットを開いてフォーカス
                              ref.read(webSocketProvider.notifier).openMessagesChat(chat.id);
                              // アプリにズーム
                              Future.delayed(const Duration(milliseconds: 500), () {
                                _zoomToApp('Messages', screenSize, screenInfo);
                              });
                            },
                          );
                        },
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  // アプリにズーム（ウィンドウ情報を取得してからズーム）
  void _zoomToApp(String appName, Size screenSize, ScreenInfo? screenInfo) async {
    print('[ZoomToApp] Starting zoom for: $appName');
    // アプリをフォーカスしてウィンドウ情報を取得
    ref.read(webSocketProvider.notifier).focusAndGetWindow(appName);

    // ウィンドウ情報が届くのを待つ（最大3秒、150ms間隔でチェック）
    for (var i = 0; i < 20; i++) {
      await Future.delayed(const Duration(milliseconds: 150));
      final state = ref.read(webSocketProvider);
      print('[ZoomToApp] Checking windowInfo (attempt $i): ${state.windowInfo}');
      if (state.windowInfo != null) {
        print('[ZoomToApp] WindowInfo received: ${state.windowInfo!.x}, ${state.windowInfo!.y}, ${state.windowInfo!.width}x${state.windowInfo!.height}');
        _zoomToWindow(state.windowInfo!, screenSize, screenInfo);
        return;
      }
    }
    print('[ZoomToApp] WindowInfo not received within timeout');
    // タイムアウト時はエラーメッセージを表示
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$appName のウィンドウを取得できませんでした'),
          backgroundColor: Colors.red.shade700,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _showBrowserTabsSheet(String appName) {
    ref.read(webSocketProvider.notifier).getBrowserTabs(appName);
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF16213e),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.8,
        expand: false,
        builder: (context, scrollController) => Consumer(
          builder: (context, ref, _) {
            final state = ref.watch(webSocketProvider);
            return Container(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.tab, color: Colors.white),
                      const SizedBox(width: 8),
                      Text(
                        '$appName のタブ',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.refresh, color: Colors.white54),
                        onPressed: () {
                          ref.read(webSocketProvider.notifier).getBrowserTabs(appName);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (state.browserTabs.isEmpty)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: Text(
                          'タブを取得中...',
                          style: TextStyle(color: Colors.white54),
                        ),
                      ),
                    )
                  else
                    Expanded(
                      child: ListView.builder(
                        controller: scrollController,
                        itemCount: state.browserTabs.length,
                        itemBuilder: (context, index) {
                          final tab = state.browserTabs[index];
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: const Color(0xFF1a1a2e),
                              radius: 14,
                              child: Text(
                                '${tab.index}',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            title: Text(
                              tab.title,
                              style: const TextStyle(color: Colors.white),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              tab.url,
                              style: const TextStyle(color: Colors.white38, fontSize: 11),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () {
                              ref.read(webSocketProvider.notifier).activateTab(appName, tab.index);
                              Navigator.pop(context);
                            },
                          );
                        },
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  void _showTerminalTabsSheet(String appName) {
    ref.read(webSocketProvider.notifier).getTerminalTabs(appName);
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF16213e),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.8,
        expand: false,
        builder: (context, scrollController) => Consumer(
          builder: (context, ref, _) {
            final state = ref.watch(webSocketProvider);
            return Container(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.terminal, color: Colors.white),
                      const SizedBox(width: 8),
                      Text(
                        '$appName のタブ',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.refresh, color: Colors.white54),
                        onPressed: () {
                          ref.read(webSocketProvider.notifier).getTerminalTabs(appName);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (state.terminalTabs.isEmpty)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: Text(
                          'タブを取得中...',
                          style: TextStyle(color: Colors.white54),
                        ),
                      ),
                    )
                  else
                    Expanded(
                      child: ListView.builder(
                        controller: scrollController,
                        itemCount: state.terminalTabs.length,
                        itemBuilder: (context, index) {
                          final tab = state.terminalTabs[index];
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: tab.isBusy
                                  ? Colors.orange.withOpacity(0.3)
                                  : const Color(0xFF1a1a2e),
                              radius: 14,
                              child: Text(
                                'W${tab.windowIndex}',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 10,
                                ),
                              ),
                            ),
                            title: Text(
                              tab.title,
                              style: const TextStyle(color: Colors.white),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Row(
                              children: [
                                Text(
                                  'Window ${tab.windowIndex}, Tab ${tab.tabIndex}',
                                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                                ),
                                if (tab.isBusy) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.orange.withOpacity(0.3),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text(
                                      '実行中',
                                      style: TextStyle(color: Colors.orange, fontSize: 10),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            onTap: () {
                              ref.read(webSocketProvider.notifier).activateTerminalTab(
                                appName,
                                tab.windowIndex,
                                tab.tabIndex,
                              );
                              Navigator.pop(context);
                            },
                          );
                        },
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  void _showSpotlightDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF16213e),
        title: const Text('Spotlight検索', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'アプリ名やファイル名...',
            hintStyle: TextStyle(color: Colors.white38),
            prefixIcon: Icon(Icons.search, color: Colors.white54),
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(color: Colors.white24),
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: BorderSide(color: Color(0xFFe94560)),
            ),
          ),
          onSubmitted: (text) {
            if (text.isNotEmpty) {
              ref.read(webSocketProvider.notifier).spotlightSearch(text);
            }
            Navigator.pop(context);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('キャンセル', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () {
              if (controller.text.isNotEmpty) {
                ref.read(webSocketProvider.notifier).spotlightSearch(controller.text);
              }
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFe94560),
            ),
            child: const Text('検索'),
          ),
        ],
      ),
    );
  }

  void _showFinderSheet() {
    ref.read(webSocketProvider.notifier).listDirectory('~');
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF16213e),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => Consumer(
          builder: (context, ref, _) {
            final state = ref.watch(webSocketProvider);
            return Container(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.folder, color: Colors.white),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          state.currentDirectory,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: ListView.builder(
                      controller: scrollController,
                      itemCount: state.directoryContents.length,
                      itemBuilder: (context, index) {
                        final entry = state.directoryContents[index];
                        return ListTile(
                          leading: Icon(
                            entry.isDirectory ? Icons.folder : Icons.insert_drive_file,
                            color: entry.isDirectory ? Colors.amber : Colors.white54,
                          ),
                          title: Text(
                            entry.name,
                            style: const TextStyle(color: Colors.white),
                          ),
                          subtitle: entry.size != null
                              ? Text(
                                  _formatSize(entry.size!),
                                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                                )
                              : null,
                          onTap: () {
                            if (entry.isDirectory) {
                              ref.read(webSocketProvider.notifier).listDirectory(entry.path);
                            } else {
                              ref.read(webSocketProvider.notifier).openFile(entry.path);
                              Navigator.pop(context);
                            }
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  void _showKeyboardDialog() {
    final controller = TextEditingController();
    final state = ref.read(webSocketProvider);
    // ターゲットアプリを取得（選択したアプリ or アクティブなアプリ）
    final targetAppName = state.targetApp ??
        state.runningApps.where((app) => app.isActive).firstOrNull?.name;
    bool autoEnter = false; // 送信後にEnterを押すか

    // 画面下部に表示するダイアログ
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Keyboard Dialog',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (context, animation, secondaryAnimation) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).viewInsets.bottom + 16,
                  left: 16,
                  right: 16,
                ),
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF16213e),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.3),
                          blurRadius: 10,
                          offset: const Offset(0, -2),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // タイトルと送信先表示
                        Row(
                          children: [
                            const Text(
                              'テキスト入力',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const Spacer(),
                            IconButton(
                              icon: const Icon(Icons.close, color: Colors.white54, size: 20),
                              onPressed: () => Navigator.pop(context),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        // 送信先アプリ表示
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1a1a2e),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFe94560).withAlpha(128)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.send, color: Color(0xFFe94560), size: 16),
                              const SizedBox(width: 8),
                              Text(
                                targetAppName ?? '不明なアプリ',
                                style: const TextStyle(
                                  color: Color(0xFFe94560),
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const Text(
                                ' に送信',
                                style: TextStyle(color: Colors.white70, fontSize: 14),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        // テキスト入力フィールド
                        TextField(
                          controller: controller,
                          autofocus: true,
                          style: const TextStyle(color: Colors.white),
                          decoration: const InputDecoration(
                            hintText: '入力するテキスト...',
                            hintStyle: TextStyle(color: Colors.white38),
                            enabledBorder: OutlineInputBorder(
                              borderSide: BorderSide(color: Colors.white24),
                              borderRadius: BorderRadius.all(Radius.circular(8)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderSide: BorderSide(color: Color(0xFFe94560)),
                              borderRadius: BorderRadius.all(Radius.circular(8)),
                            ),
                            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          ),
                          onSubmitted: (text) {
                            if (text.isNotEmpty) {
                              if (autoEnter) {
                                ref.read(webSocketProvider.notifier).typeTextAndEnter(text);
                              } else {
                                ref.read(webSocketProvider.notifier).typeText(text);
                              }
                            }
                            Navigator.pop(context);
                          },
                        ),
                        const SizedBox(height: 12),
                        // 送信後にEnterを押すオプション
                        Row(
                          children: [
                            Switch(
                              value: autoEnter,
                              onChanged: (value) {
                                setDialogState(() {
                                  autoEnter = value;
                                });
                              },
                              activeColor: const Color(0xFFe94560),
                            ),
                            const Text(
                              '送信後にEnterを押す',
                              style: TextStyle(color: Colors.white70, fontSize: 14),
                            ),
                            const Spacer(),
                            // LINEなどのヒント
                            if (targetAppName?.toLowerCase().contains('line') == true)
                              const Text(
                                '(メッセージ送信)',
                                style: TextStyle(color: Colors.white38, fontSize: 12),
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        // 特殊キー（2行に分けて配置）
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _keyButton('Enter', 'enter'),
                            _keyButton('Tab', 'tab'),
                            _keyButton('Shift+Tab', 'shift+tab'),
                            _keyButton('Esc', 'escape'),
                            _keyButton('Del', 'delete'),
                          ],
                        ),
                        const SizedBox(height: 16),
                        // 送信ボタン
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: () {
                              if (controller.text.isNotEmpty) {
                                if (autoEnter) {
                                  ref.read(webSocketProvider.notifier).typeTextAndEnter(controller.text);
                                } else {
                                  ref.read(webSocketProvider.notifier).typeText(controller.text);
                                }
                              }
                              Navigator.pop(context);
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFe94560),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: Text(
                              autoEnter ? '送信 + Enter' : '送信',
                              style: const TextStyle(fontSize: 16),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 1),
            end: Offset.zero,
          ).animate(CurvedAnimation(
            parent: animation,
            curve: Curves.easeOut,
          )),
          child: child,
        );
      },
    );
  }

  Widget _keyButton(String label, String key) {
    return ElevatedButton(
      onPressed: () {
        // AppleScript経由でキー入力（より信頼性が高い）
        ref.read(webSocketProvider.notifier).pressKey(key);
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF1a1a2e),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      child: Text(label, style: const TextStyle(fontSize: 12)),
    );
  }

  void _showQuitAppDialog(String appName) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF16213e),
        title: const Text('アプリを終了', style: TextStyle(color: Colors.white)),
        content: Text(
          '$appName を終了しますか？',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('キャンセル', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () {
              ref.read(webSocketProvider.notifier).quitApp(appName);
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('$appName を終了しました')),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('終了'),
          ),
        ],
      ),
    );
  }
}

// PCマウスカーソルを描画するカスタムペインター
class _CursorPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();

    // マウスカーソルの形状（矢印型）
    path.moveTo(0, 0);  // 先端
    path.lineTo(0, size.height * 0.85);  // 左下
    path.lineTo(size.width * 0.3, size.height * 0.65);  // 中央下
    path.lineTo(size.width * 0.5, size.height);  // 右下（クリック部分）
    path.lineTo(size.width * 0.7, size.height * 0.75);  // 右下上
    path.lineTo(size.width * 0.45, size.height * 0.55);  // 中央
    path.lineTo(size.width * 0.85, size.height * 0.55);  // 右
    path.close();

    // 白い塗りつぶし
    final fillPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, fillPaint);

    // 黒い輪郭
    final strokePaint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawPath(path, strokePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

