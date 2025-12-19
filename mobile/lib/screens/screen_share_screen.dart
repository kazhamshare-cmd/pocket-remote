import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vector_math/vector_math_64.dart' as vector_math;
import '../services/websocket_service.dart';
import '../services/localization_service.dart';

class ScreenShareScreen extends ConsumerStatefulWidget {
  const ScreenShareScreen({super.key});

  @override
  ConsumerState<ScreenShareScreen> createState() => _ScreenShareScreenState();
}

class _ScreenShareScreenState extends ConsumerState<ScreenShareScreen> {
  final TransformationController _transformController = TransformationController();
  final TextEditingController _textController = TextEditingController();
  final FocusNode _textFocusNode = FocusNode();
  double _scale = 1.0;
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
  String _lastSentText = ''; // 最後に送信したテキスト
  bool _useWebRTC = true; // WebRTCモード（常にWebRTC使用）
  List<Map<String, String>> _customCommands = []; // カスタムコマンド [{name, command}]

  // 2本指スクロール用
  int _pointerCount = 0;
  Offset? _lastScrollPosition;
  bool _isScrolling = false;

  // 固定ズーム倍率
  static const double _fixedZoom = 3.0;

  @override
  void initState() {
    super.initState();
    // カスタムコマンドを読み込み
    _loadCustomCommands();
    // 画面共有開始 & アプリ一覧取得
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startScreenShare();
      ref.read(webSocketProvider.notifier).getRunningApps();
      // 3倍ズームを初期設定（画像は左上から表示）
      _transformController.value = Matrix4.identity()..scale(_fixedZoom);
    });
    // 縦向き固定（パン・ズームで操作）
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
    // フルスクリーン
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  // カスタムコマンドを読み込み
  Future<void> _loadCustomCommands() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString('custom_commands');
    if (jsonStr != null) {
      final list = jsonDecode(jsonStr) as List;
      setState(() {
        _customCommands = list.map((e) => Map<String, String>.from(e)).toList();
      });
    }
  }

  // カスタムコマンドを保存
  Future<void> _saveCustomCommands() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('custom_commands', jsonEncode(_customCommands));
  }

  // カスタムコマンドを追加
  void _addCustomCommand(String name, String command) {
    setState(() {
      _customCommands.add({'name': name, 'command': command});
    });
    _saveCustomCommands();
  }

  // カスタムコマンドを削除
  void _removeCustomCommand(int index) {
    setState(() {
      _customCommands.removeAt(index);
    });
    _saveCustomCommands();
  }

  // カスタムコマンドを実行
  void _executeCustomCommand(String command) {
    // コマンドをタイプして実行
    ref.read(webSocketProvider.notifier).typeText(command);
    // Enterキーを送信
    Future.delayed(const Duration(milliseconds: 100), () {
      ref.read(webSocketProvider.notifier).pressKey('enter');
    });
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
    _transformController.dispose();
    _textController.dispose();
    _textFocusNode.dispose();
    super.dispose();
  }

  Offset? _lastTapPosition; // ダブルタップ位置検出用

  void _onTapDown(TapDownDetails details, Size screenSize, ScreenInfo? screenInfo) {
    if (screenInfo == null || !_mouseMode) return;

    // 2本指操作中はタップを無視
    if (_pointerCount >= 2 || _isScrolling) return;

    final now = DateTime.now();
    final timeSinceLastTap = _lastTapTime != null
        ? now.difference(_lastTapTime!).inMilliseconds
        : 1000;

    // ダブルタップ判定: 400ms以内 & 50px以内の位置
    final positionClose = _lastTapPosition != null &&
        (details.localPosition - _lastTapPosition!).distance < 50;
    final isDoubleTap = timeSinceLastTap < 400 && positionClose;

    // InteractiveViewerの変換を考慮してリモート座標を計算
    final remotePos = _screenToRemoteCoordinates(details.localPosition, screenSize, screenInfo);

    // カーソル位置を更新
    setState(() {
      _cursorPosition = details.localPosition;
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
      _lastTapPosition = null;
    } else {
      // シングルタップ = マウス移動のみ
      ref.read(webSocketProvider.notifier).sendMouseMove(
        remotePos.dx.toInt(),
        remotePos.dy.toInt(),
      );
      _lastTapTime = now;
      _lastTapPosition = details.localPosition;
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

    // カーソル位置を更新
    setState(() {
      _cursorPosition = details.localPosition;
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

  void _onPanStart(DragStartDetails details, Size screenSize, ScreenInfo? screenInfo) {
    if (screenInfo == null || !_mouseMode) return;

    _lastFocalPoint = details.localPosition;

    // カーソル位置を更新
    setState(() {
      _cursorPosition = details.localPosition;
      _showCursor = true;
    });

    final remotePos = _screenToRemoteCoordinates(details.localPosition, screenSize, screenInfo);

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

  void _onPanUpdate(DragUpdateDetails details, Size screenSize, ScreenInfo? screenInfo) {
    if (screenInfo == null || !_mouseMode) return;

    // カーソル位置を更新
    setState(() {
      _cursorPosition = details.localPosition;
    });

    final remotePos = _screenToRemoteCoordinates(details.localPosition, screenSize, screenInfo);

    // 常にマウス移動を送信
    ref.read(webSocketProvider.notifier).sendMouseMove(
      remotePos.dx.toInt(),
      remotePos.dy.toInt(),
    );

    _lastFocalPoint = details.localPosition;
  }

  void _onPanEnd(DragEndDetails details, Size screenSize, ScreenInfo? screenInfo) {
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

  /// 画面座標（ビューポート）をコンテンツ座標（画像ピクセル）に変換
  Offset _getTransformedPosition(Offset viewportPosition) {
    final matrix = _transformController.value;

    // 逆行列を計算
    final inverseMatrix = Matrix4.inverted(matrix);

    // Vector3を使って正確に変換
    final inputVector = vector_math.Vector3(
      viewportPosition.dx,
      viewportPosition.dy,
      0,
    );
    final outputVector = inverseMatrix.transform3(inputVector);

    return Offset(outputVector.x, outputVector.y);
  }

  // 画面タッチ位置からリモートPC座標に変換
  // ヘッダーは別のContainerにあるため、screenPosはStack内の座標（0,0から始まる）
  Offset _screenToRemoteCoordinates(Offset screenPos, Size screenSize, ScreenInfo screenInfo) {
    if (_focusedWindow != null) {
      // アプリ選択時: InteractiveViewerの逆変換を適用
      final contentPos = _getTransformedPosition(screenPos);
      final window = _focusedWindow!;

      // サーバーから送られる画像は等倍（ウィンドウサイズと同じ）
      final imageWidth = window.width.toDouble();
      final imageHeight = window.height.toDouble();

      // 画像ピクセル座標から相対位置を計算
      final relativeX = (contentPos.dx / imageWidth).clamp(0.0, 1.0);
      final relativeY = (contentPos.dy / imageHeight).clamp(0.0, 1.0);

      // PC座標に変換（ウィンドウ内の相対位置 + ウィンドウのオフセット）
      final remoteX = relativeX * window.width + window.x;
      final remoteY = relativeY * window.height + window.y;

      print('[Coords-Focused] screenPos=$screenPos, contentPos=$contentPos');
      print('[Coords-Focused] window: ${window.x},${window.y} ${window.width}x${window.height}');
      print('[Coords-Focused] rel=($relativeX,$relativeY), PC=($remoteX,$remoteY)');
      print('[Coords-Focused] transform: ${_transformController.value}');

      return Offset(
        remoteX.clamp(0, screenInfo.width.toDouble()),
        remoteY.clamp(0, screenInfo.height.toDouble()),
      );
    } else {
      // アプリ未選択時: BoxFit.contain表示の座標計算
      final imageWidth = screenInfo.width / 2.0;
      final imageHeight = screenInfo.height / 2.0;

      // BoxFit.containで表示される実際のサイズとオフセットを計算
      final imageAspect = imageWidth / imageHeight;
      final screenAspect = screenSize.width / screenSize.height;

      double displayWidth, displayHeight, offsetX, offsetY;
      if (imageAspect > screenAspect) {
        displayWidth = screenSize.width;
        displayHeight = screenSize.width / imageAspect;
        offsetX = 0;
        offsetY = (screenSize.height - displayHeight) / 2;
      } else {
        displayHeight = screenSize.height;
        displayWidth = screenSize.height * imageAspect;
        offsetX = (screenSize.width - displayWidth) / 2;
        offsetY = 0;
      }

      // タップ位置から画像内の相対位置を計算
      final tapX = (screenPos.dx - offsetX).clamp(0.0, displayWidth);
      final tapY = (screenPos.dy - offsetY).clamp(0.0, displayHeight);

      final relativeX = tapX / displayWidth;
      final relativeY = tapY / displayHeight;

      // PC座標に変換
      final remoteX = relativeX * screenInfo.width;
      final remoteY = relativeY * screenInfo.height;

      print('[Coords-Full] screenPos=$screenPos, display=${displayWidth}x$displayHeight, offset=($offsetX,$offsetY), rel=($relativeX,$relativeY), PC=($remoteX,$remoteY)');

      return Offset(remoteX, remoteY);
    }
  }

  // PCのマウス座標を画像内のピクセル座標に変換（InteractiveViewer内で使用）
  Offset? _convertPcMouseToImageCoordinates(MousePosition? pcMouse, ScreenInfo? screenInfo) {
    if (pcMouse == null || screenInfo == null) return null;

    // フォーカスモードかどうかで処理を分岐
    if (_focusedWindow != null) {
      // フォーカスモード: 画像はウィンドウ領域のみ（クロップ、縮小なし）
      final window = _focusedWindow!;

      // PCマウスがウィンドウ領域外にある場合はnull
      if (pcMouse.x < window.x || pcMouse.x > window.x + window.width ||
          pcMouse.y < window.y || pcMouse.y > window.y + window.height) {
        return null;
      }

      // ウィンドウ内のピクセル座標
      final imageX = (pcMouse.x - window.x).toDouble();
      final imageY = (pcMouse.y - window.y).toDouble();

      return Offset(imageX, imageY);
    } else {
      // 通常モード: 画面は1/2サイズで縮小されている
      // PCの座標を1/2にして画像内の座標に変換
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

    setState(() {
      _focusedWindow = windowInfo;
    });

    // サーバーに高解像度キャプチャ領域を設定
    // ウィンドウ領域だけをキャプチャするよう指示
    ref.read(webSocketProvider.notifier).setCaptureRegion(
      windowInfo.x,
      windowInfo.y,
      windowInfo.width,
      windowInfo.height,
    );

    // ウィジェット再構築後に3倍ズームを適用
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _transformController.value = Matrix4.identity()..scale(_fixedZoom);
    });
  }

  // ズームをリセット（全画面キャプチャに戻す）
  void _resetZoom() {
    setState(() {
      _focusedWindow = null;
    });

    // サーバーに全画面キャプチャに戻すよう指示
    ref.read(webSocketProvider.notifier).resetCaptureRegion();

    _transformController.value = Matrix4.identity();
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

    final l10n = ref.watch(l10nProvider);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Column(
        children: [
          // 上部ヘッダー（重ならない）
          Container(
            color: Colors.black,
            child: SafeArea(
              bottom: false,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
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
                        // 更新ボタン
                        IconButton(
                          icon: const Icon(Icons.refresh, color: Colors.white),
                          onPressed: () {
                            ref.read(webSocketProvider.notifier).getRunningApps();
                          },
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ],
                    ),
                    // 下段: 操作ガイド（マウスモード時のみ表示）
                    if (_mouseMode)
                      Container(
                        margin: const EdgeInsets.only(top: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
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
            ),
          ),
          // 画面表示エリア
          Expanded(
            child: Stack(
              children: [
                // 画面表示
                if (state.currentFrame != null)
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final screenSize = Size(constraints.maxWidth, constraints.maxHeight);
                      return Listener(
                        onPointerDown: (event) {
                          setState(() {
                            _pointerCount++;
                            if (_pointerCount == 2) {
                              _lastScrollPosition = event.position;
                              _isScrolling = true;
                            }
                          });
                        },
                        onPointerUp: (event) {
                          setState(() {
                            _pointerCount = (_pointerCount - 1).clamp(0, 10);
                            if (_pointerCount < 2) {
                              _isScrolling = false;
                              _lastScrollPosition = null;
                            }
                          });
                        },
                        onPointerCancel: (event) {
                          setState(() {
                            _pointerCount = (_pointerCount - 1).clamp(0, 10);
                            if (_pointerCount < 2) {
                              _isScrolling = false;
                              _lastScrollPosition = null;
                            }
                          });
                        },
                        onPointerMove: (event) {
                          if (_isScrolling && _pointerCount >= 2 && _lastScrollPosition != null) {
                            final delta = event.position - _lastScrollPosition!;
                            final scrollDeltaY = (-delta.dy * 2).toInt();
                            final scrollDeltaX = (-delta.dx * 2).toInt();
                            if (scrollDeltaY.abs() > 2 || scrollDeltaX.abs() > 2) {
                              ref.read(webSocketProvider.notifier).sendScroll(scrollDeltaX, scrollDeltaY);
                              _lastScrollPosition = event.position;
                            }
                          }
                        },
                        child: GestureDetector(
                          onTapDown: (details) => _onTapDown(details, screenSize, state.screenInfo),
                          onLongPressStart: (details) => _onLongPress(details, screenSize, state.screenInfo),
                          child: _focusedWindow != null
                            // アプリ選択時: 3倍ズームでパン可能
                            ? ClipRect(
                                child: InteractiveViewer(
                                  transformationController: _transformController,
                                  constrained: false,
                                  boundaryMargin: const EdgeInsets.all(double.infinity),
                                  minScale: 0.5,
                                  maxScale: 10.0,
                                  panEnabled: true,
                                  scaleEnabled: false,
                                  child: Image.memory(
                                    state.currentFrame!,
                                    fit: BoxFit.none,
                                    gaplessPlayback: true,
                                  ),
                                ),
                              )
                            // アプリ未選択時: 全体表示（フィット）
                            : Image.memory(
                                state.currentFrame!,
                                fit: BoxFit.contain,
                                width: screenSize.width,
                                height: screenSize.height,
                                gaplessPlayback: true,
                              ),
                        ),
                      );
                    },
                  )
                else
                  Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const CircularProgressIndicator(color: Color(0xFFe94560)),
                        const SizedBox(height: 16),
                        Text(
                          l10n.loadingScreen,
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ],
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

                // 下部ツールバー（キーボード非表示時のみ）
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
                                  final screenSize = Size(constraints.maxWidth, MediaQuery.of(context).size.height);
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
                                        // ドラッグモード切り替え（マウスモード時のみ有効）
                                        if (_mouseMode)
                                          _toolbarToggleButton(
                                            icon: Icons.pan_tool,
                                            label: _dragMode ? l10n.drag : l10n.move,
                                            isActive: _dragMode,
                                            onTap: () {
                                              setState(() {
                                                _dragMode = !_dragMode;
                                              });
                                              HapticFeedback.lightImpact();
                                              // モード変更をユーザーに通知
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                SnackBar(
                                                  content: Text(_dragMode
                                                      ? l10n.dragModeOn
                                                      : l10n.moveModeOn),
                                                  duration: const Duration(seconds: 2),
                                                  backgroundColor: const Color(0xFF16213e),
                                                ),
                                              );
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

                // インライン入力フィールド（ツールバーを非表示にして全画面活用）
                if (_showKeyboardInput)
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: SafeArea(
                      top: false,
                      child: _buildInlineKeyboardInput(),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInlineKeyboardInput() {
    final state = ref.read(webSocketProvider);
    final l10n = ref.read(l10nProvider);
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
                  targetAppName ?? l10n.unknownApp,
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
                        _realtimeSync ? l10n.realtimeMode : l10n.manualMode,
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
                    hintText: _realtimeSync ? l10n.realtimeInputHint : l10n.inputHint,
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
          // ショートカット・カスタムコマンド（スクロール可能）
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                // 基本キー
                _compactKeyButton('Tab', 'tab'),
                _compactKeyButton('Esc', 'escape'),
                _compactKeyButton('⌫', 'backspace'),
                const SizedBox(width: 8),
                // ショートカット
                _compactKeyButton('⌘C', 'cmd+c'),
                _compactKeyButton('⌘V', 'cmd+v'),
                _compactKeyButton('⌘Z', 'cmd+z'),
                _compactKeyButton('⌘S', 'cmd+s'),
                _compactKeyButton('⌘Tab', 'cmd+tab'),
                const SizedBox(width: 8),
                // カスタムコマンド
                ..._customCommands.asMap().entries.map((entry) {
                  final index = entry.key;
                  final cmd = entry.value;
                  return GestureDetector(
                    onTap: () => _executeCustomCommand(cmd['command']!),
                    onLongPress: () => _showDeleteCommandDialog(index, cmd['name']!),
                    child: Container(
                      margin: const EdgeInsets.only(right: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.purple.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.purple.withValues(alpha: 0.5)),
                      ),
                      child: Text(
                        cmd['name']!,
                        style: const TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ),
                  );
                }),
                // 追加ボタン
                GestureDetector(
                  onTap: _showAddCommandDialog,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add, color: Colors.white70, size: 14),
                        SizedBox(width: 2),
                        Text('+', style: TextStyle(color: Colors.white70, fontSize: 12)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // コマンド追加ダイアログ
  void _showAddCommandDialog() {
    final nameController = TextEditingController();
    final commandController = TextEditingController();
    final l10n = ref.read(l10nProvider);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF16213e),
        title: Text(l10n.addCommand, style: const TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: l10n.commandName,
                labelStyle: const TextStyle(color: Colors.white54),
                hintText: 'git status',
                hintStyle: const TextStyle(color: Colors.white24),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: commandController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: l10n.command,
                labelStyle: const TextStyle(color: Colors.white54),
                hintText: 'git status',
                hintStyle: const TextStyle(color: Colors.white24),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel, style: const TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () {
              if (nameController.text.isNotEmpty && commandController.text.isNotEmpty) {
                _addCustomCommand(nameController.text, commandController.text);
                Navigator.pop(context);
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFe94560)),
            child: Text(l10n.add),
          ),
        ],
      ),
    );
  }

  // コマンド削除確認ダイアログ
  void _showDeleteCommandDialog(int index, String name) {
    final l10n = ref.read(l10nProvider);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF16213e),
        title: Text(l10n.deleteCommand, style: const TextStyle(color: Colors.white)),
        content: Text(
          '"$name" ${l10n.deleteConfirm}',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel, style: const TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () {
              _removeCustomCommand(index);
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text(l10n.deleteBtn),
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
    final l10n = ref.read(l10nProvider);
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
            Text(
              l10n.runningApps,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            if (apps.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    l10n.fetchingApps,
                    style: const TextStyle(color: Colors.white54),
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
                        // まずウィンドウ一覧を取得して表示
                        _showAppWindowsSheet(app.name, screenSize, screenInfo, isBrowser, isTerminal);
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
            final l10n = ref.watch(l10nProvider);
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
                          l10n.windowsOf(appName),
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
                    l10n.selectWindow,
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  const SizedBox(height: 16),
                  if (state.appWindows.isEmpty)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          l10n.fetchingWindows,
                          style: const TextStyle(color: Colors.white54),
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
                              window.title.isEmpty ? l10n.noTitle : window.title,
                              style: const TextStyle(color: Colors.white),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: window.isMinimized
                                ? Text(
                                    l10n.minimized,
                                    style: const TextStyle(color: Colors.orange, fontSize: 11),
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

  // アプリにズーム（ウィンドウ情報を取得してからズーム）
  void _zoomToApp(String appName, Size screenSize, ScreenInfo? screenInfo) async {
    // アプリをフォーカスしてウィンドウ情報を取得
    ref.read(webSocketProvider.notifier).focusAndGetWindow(appName);

    // ウィンドウ情報が届くのを待つ（最大2秒、100ms間隔でチェック）
    for (var i = 0; i < 20; i++) {
      await Future.delayed(const Duration(milliseconds: 100));
      final state = ref.read(webSocketProvider);
      if (state.windowInfo != null) {
        print('[ZoomToApp] WindowInfo received: ${state.windowInfo!.x}, ${state.windowInfo!.y}, ${state.windowInfo!.width}x${state.windowInfo!.height}');
        _zoomToWindow(state.windowInfo!, screenSize, screenInfo);
        return;
      }
    }
    print('[ZoomToApp] WindowInfo not received within timeout');
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
            final l10n = ref.watch(l10nProvider);
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
                        l10n.tabsOf(appName),
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
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          l10n.fetchingTabs,
                          style: const TextStyle(color: Colors.white54),
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
            final l10n = ref.watch(l10nProvider);
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
                        l10n.tabsOf(appName),
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
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          l10n.fetchingTabs,
                          style: const TextStyle(color: Colors.white54),
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
                                    child: Text(
                                      l10n.busy,
                                      style: const TextStyle(color: Colors.orange, fontSize: 10),
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
    final l10n = ref.read(l10nProvider);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF16213e),
        title: Text(l10n.spotlightSearch, style: const TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: l10n.searchHint,
            hintStyle: const TextStyle(color: Colors.white38),
            prefixIcon: const Icon(Icons.search, color: Colors.white54),
            enabledBorder: const OutlineInputBorder(
              borderSide: BorderSide(color: Colors.white24),
            ),
            focusedBorder: const OutlineInputBorder(
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
            child: Text(l10n.cancel, style: const TextStyle(color: Colors.white54)),
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
            child: Text(l10n.search),
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
    final l10n = ref.read(l10nProvider);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF16213e),
        title: Text(l10n.quitApp, style: const TextStyle(color: Colors.white)),
        content: Text(
          l10n.quitAppConfirm(appName),
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel, style: const TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () {
              ref.read(webSocketProvider.notifier).quitApp(appName);
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(l10n.appQuit(appName))),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text(l10n.quit),
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

