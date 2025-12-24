import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/command.dart';
import '../models/connection_info.dart';
import 'webrtc_service.dart';
import 'h264_decoder_service.dart';

enum WsConnectionState { disconnected, connecting, connected, error }

class ScreenInfo {
  final int width;
  final int height;

  ScreenInfo({required this.width, required this.height});

  factory ScreenInfo.fromJson(Map<String, dynamic> json) {
    return ScreenInfo(
      width: json['width'] as int,
      height: json['height'] as int,
    );
  }
}

class RunningApp {
  final String name;
  final String? bundleId;
  final bool isActive;
  final bool isCli; // ターミナルで実行中のCLIツールかどうか

  RunningApp({required this.name, this.bundleId, required this.isActive, this.isCli = false});

  factory RunningApp.fromJson(Map<String, dynamic> json) {
    return RunningApp(
      name: json['name'] as String,
      bundleId: json['bundle_id'] as String?,
      isActive: json['is_active'] as bool? ?? false,
      isCli: json['is_cli'] as bool? ?? false,
    );
  }
}

class FileEntry {
  final String name;
  final String path;
  final bool isDirectory;
  final int? size;

  FileEntry({
    required this.name,
    required this.path,
    required this.isDirectory,
    this.size,
  });

  factory FileEntry.fromJson(Map<String, dynamic> json) {
    return FileEntry(
      name: json['name'] as String,
      path: json['path'] as String,
      isDirectory: json['is_directory'] as bool,
      size: json['size'] as int?,
    );
  }
}

class BrowserTab {
  final int index;
  final String title;
  final String url;

  BrowserTab({
    required this.index,
    required this.title,
    required this.url,
  });

  factory BrowserTab.fromJson(Map<String, dynamic> json) {
    return BrowserTab(
      index: json['index'] as int,
      title: json['title'] as String,
      url: json['url'] as String,
    );
  }
}

class TerminalTab {
  final int windowIndex;
  final int tabIndex;
  final String title;
  final bool isBusy;

  TerminalTab({
    required this.windowIndex,
    required this.tabIndex,
    required this.title,
    required this.isBusy,
  });

  factory TerminalTab.fromJson(Map<String, dynamic> json) {
    return TerminalTab(
      windowIndex: json['window_index'] as int,
      tabIndex: json['tab_index'] as int,
      title: json['title'] as String,
      isBusy: json['is_busy'] as bool,
    );
  }
}

/// アプリのウィンドウ一覧用
class WindowListItem {
  final int index;
  final String title;
  final bool isMinimized;

  WindowListItem({
    required this.index,
    required this.title,
    required this.isMinimized,
  });

  factory WindowListItem.fromJson(Map<String, dynamic> json) {
    return WindowListItem(
      index: json['index'] as int,
      title: json['title'] as String? ?? '',
      isMinimized: json['is_minimized'] as bool? ?? false,
    );
  }
}

class AppWindowInfo {
  final String appName;
  final String windowTitle;
  final int x;
  final int y;
  final int width;
  final int height;

  AppWindowInfo({
    required this.appName,
    required this.windowTitle,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  factory AppWindowInfo.fromJson(Map<String, dynamic> json) {
    return AppWindowInfo(
      appName: json['app_name'] as String,
      windowTitle: json['window_title'] as String,
      x: json['x'] as int,
      y: json['y'] as int,
      width: json['width'] as int,
      height: json['height'] as int,
    );
  }
}

// PCのマウスカーソル位置
class MousePosition {
  final int x;
  final int y;

  MousePosition({required this.x, required this.y});

  factory MousePosition.fromJson(Map<String, dynamic> json) {
    return MousePosition(
      x: json['x'] as int,
      y: json['y'] as int,
    );
  }
}

// Messagesアプリのチャット情報
class MessagesChat {
  final String id;
  final String name;
  final String service;

  MessagesChat({
    required this.id,
    required this.name,
    required this.service,
  });

  factory MessagesChat.fromJson(Map<String, dynamic> json) {
    return MessagesChat(
      id: json['id'] as String,
      name: json['name'] as String,
      service: json['service'] as String,
    );
  }
}

class WebSocketState {
  final WsConnectionState connectionState;
  final List<Command> commands;
  final String? errorMessage;
  final String? lastOutput;
  final bool? lastSuccess;
  final ScreenInfo? screenInfo;
  final Uint8List? currentFrame;
  final bool isScreenSharing;
  final List<RunningApp> runningApps;
  final List<FileEntry> directoryContents;
  final String currentDirectory;
  final List<BrowserTab> browserTabs;
  final List<TerminalTab> terminalTabs;
  final String? targetApp; // 最後に選択したアプリ
  final AppWindowInfo? windowInfo; // 現在のウィンドウ情報
  final MousePosition? pcMousePosition; // PCのマウスカーソル位置
  final bool isWebRTCActive; // WebRTCモードがアクティブか
  final String? webrtcConnectionState; // WebRTC接続状態
  final List<WindowListItem> appWindows; // アプリのウィンドウ一覧
  final List<MessagesChat> messagesChats; // Messagesチャット一覧

  WebSocketState({
    this.connectionState = WsConnectionState.disconnected,
    this.commands = const [],
    this.errorMessage,
    this.lastOutput,
    this.lastSuccess,
    this.screenInfo,
    this.currentFrame,
    this.isScreenSharing = false,
    this.runningApps = const [],
    this.directoryContents = const [],
    this.currentDirectory = '~',
    this.browserTabs = const [],
    this.terminalTabs = const [],
    this.targetApp,
    this.windowInfo,
    this.pcMousePosition,
    this.isWebRTCActive = false,
    this.webrtcConnectionState,
    this.appWindows = const [],
    this.messagesChats = const [],
  });

  // 接続中かどうか
  bool get isConnected => connectionState == WsConnectionState.connected;

  WebSocketState copyWith({
    WsConnectionState? connectionState,
    List<Command>? commands,
    String? errorMessage,
    String? lastOutput,
    bool? lastSuccess,
    ScreenInfo? screenInfo,
    Uint8List? currentFrame,
    bool? isScreenSharing,
    List<RunningApp>? runningApps,
    List<FileEntry>? directoryContents,
    String? currentDirectory,
    List<BrowserTab>? browserTabs,
    List<TerminalTab>? terminalTabs,
    String? targetApp,
    AppWindowInfo? windowInfo,
    MousePosition? pcMousePosition,
    bool clearWindowInfo = false,
    bool? isWebRTCActive,
    String? webrtcConnectionState,
    List<WindowListItem>? appWindows,
    List<MessagesChat>? messagesChats,
  }) {
    return WebSocketState(
      connectionState: connectionState ?? this.connectionState,
      commands: commands ?? this.commands,
      errorMessage: errorMessage,
      lastOutput: lastOutput,
      lastSuccess: lastSuccess,
      screenInfo: screenInfo ?? this.screenInfo,
      currentFrame: currentFrame ?? this.currentFrame,
      isScreenSharing: isScreenSharing ?? this.isScreenSharing,
      runningApps: runningApps ?? this.runningApps,
      directoryContents: directoryContents ?? this.directoryContents,
      currentDirectory: currentDirectory ?? this.currentDirectory,
      browserTabs: browserTabs ?? this.browserTabs,
      terminalTabs: terminalTabs ?? this.terminalTabs,
      targetApp: targetApp ?? this.targetApp,
      windowInfo: clearWindowInfo ? null : (windowInfo ?? this.windowInfo),
      pcMousePosition: pcMousePosition ?? this.pcMousePosition,
      isWebRTCActive: isWebRTCActive ?? this.isWebRTCActive,
      webrtcConnectionState: webrtcConnectionState ?? this.webrtcConnectionState,
      appWindows: appWindows ?? this.appWindows,
      messagesChats: messagesChats ?? this.messagesChats,
    );
  }
}

class WebSocketService extends StateNotifier<WebSocketState> {
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  ConnectionInfo? _connectionInfo;
  WebRTCService? _webrtcService;

  // H.264デコーダー（WebSocket経由のH.264フレーム用）
  H264DecoderService? _h264Decoder;
  bool _h264DecoderInitialized = false;

  // シェルコマンド実行用のCompleter
  Completer<String>? _shellCommandCompleter;

  // PTY（永続ターミナル）セッション用
  final _ptyOutputController = StreamController<String>.broadcast();
  Stream<String> get ptyOutputStream => _ptyOutputController.stream;
  bool _ptySessionActive = false;

  // ターミナルコンテンツ取得用
  final _terminalContentController = StreamController<String>.broadcast();
  Stream<String> get terminalContentStream => _terminalContentController.stream;
  Completer<String>? _terminalContentCompleter;

  WebSocketService() : super(WebSocketState());

  // 安全にstateを更新（ウィジェット破棄後のエラーを防止）
  void _safeSetState(WebSocketState Function(WebSocketState) updater) {
    try {
      state = updater(state);
    } catch (e) {
      // ウィジェット破棄後のエラーを無視
      print('[WebSocket] State update ignored (widget disposed): $e');
    }
  }

  Future<void> connect(ConnectionInfo info) async {
    _connectionInfo = info;
    _safeSetState((s) => s.copyWith(connectionState: WsConnectionState.connecting));
    print('[WebSocket] Connecting to: ${info.wsUrl}');
    print('[WebSocket] Token: ${info.token}');
    print('[WebSocket] isExternal: ${info.isExternal}');

    try {
      _channel = WebSocketChannel.connect(Uri.parse(info.wsUrl));
      print('[WebSocket] Channel created');

      _subscription = _channel!.stream.listen(
        _onMessage,
        onError: _onError,
        onDone: _onDone,
      );
      print('[WebSocket] Stream listener attached');

      // 認証メッセージを送信（外部接続かどうかのフラグを含む）
      final authMsg = {
        'type': 'auth',
        'token': info.token,
        'device_name': 'RemoteTouch',
        'is_external': info.isExternal,
      };
      print('[WebSocket] Sending auth: $authMsg');
      _send(authMsg);
    } catch (e) {
      print('[WebSocket] Connection error: $e');
      _safeSetState((s) => s.copyWith(
        connectionState: WsConnectionState.error,
        errorMessage: e.toString(),
      ));
    }
  }

  void disconnect() {
    _webrtcService?.close();
    _webrtcService = null;
    _subscription?.cancel();
    _channel?.sink.close();
    _channel = null;
    _safeSetState((_) => WebSocketState());
  }

  void executeCommand(String commandId) {
    _send({
      'type': 'execute',
      'command_id': commandId,
    });
  }

  void addCommand(String name, String command) {
    _send({
      'type': 'add_command',
      'name': name,
      'command': command,
    });
  }

  void startScreenShare() {
    _send({'type': 'start_screen_share'});
    _safeSetState((s) => s.copyWith(isScreenSharing: true));
  }

  void stopScreenShare() {
    _send({'type': 'stop_screen_share'});
    _safeSetState((s) => s.copyWith(isScreenSharing: false, currentFrame: null));
  }

  // WebRTC画面共有開始
  Future<void> startWebRTCScreenShare() async {
    print('[WebRTC] Starting WebRTC screen share...');

    // WebRTCサービスを初期化
    _webrtcService = WebRTCService();
    await _webrtcService!.initialize();

    // フレーム受信コールバック（接続中のみ更新）
    _webrtcService!.onFrame = (frame) {
      // 接続が切れている場合は無視（破棄後のstate更新エラー防止）
      if (_channel == null) return;
      _safeSetState((s) => s.copyWith(currentFrame: frame));
    };

    // 接続状態コールバック
    _webrtcService!.onConnectionStateChange = (stateStr) {
      if (_channel == null) return;
      print('[WebRTC] Connection state: $stateStr');
      _safeSetState((s) => s.copyWith(webrtcConnectionState: stateStr));
    };

    // ICE候補コールバック（サーバーに送信）
    _webrtcService!.onIceCandidate = (candidateStr) {
      if (_channel == null) return;
      print('[WebRTC] Sending ICE candidate');
      _send({
        'type': 'webrtc_ice_candidate',
        'candidate': candidateStr,
      });
    };

    // サーバーにWebRTC開始を要求
    _send({'type': 'start_webrtc'});
    _safeSetState((s) => s.copyWith(isWebRTCActive: true, isScreenSharing: true));
  }

  // WebRTC画面共有停止
  void stopWebRTCScreenShare() {
    _send({'type': 'stop_webrtc'});
    _webrtcService?.close();
    _webrtcService = null;
    _safeSetState((s) => s.copyWith(
      isWebRTCActive: false,
      isScreenSharing: false,
      currentFrame: null,
      webrtcConnectionState: null,
    ));
  }

  void sendMouseMove(int x, int y) {
    _send({
      'type': 'input',
      'action': 'mouse_move',
      'x': x,
      'y': y,
    });
  }

  void sendMouseClick(int x, int y, {String button = 'left'}) {
    _send({
      'type': 'input',
      'action': 'mouse_click',
      'x': x,
      'y': y,
      'button': button,
    });
  }

  void sendMouseDown(int x, int y, {String button = 'left'}) {
    _send({
      'type': 'input',
      'action': 'mouse_down',
      'x': x,
      'y': y,
      'button': button,
    });
  }

  void sendMouseUp(int x, int y, {String button = 'left'}) {
    _send({
      'type': 'input',
      'action': 'mouse_up',
      'x': x,
      'y': y,
      'button': button,
    });
  }

  void sendScroll(int deltaX, int deltaY) {
    _send({
      'type': 'input',
      'action': 'mouse_scroll',
      'delta_x': deltaX,
      'delta_y': deltaY,
    });
  }

  /// ビューポート情報を送信（スクロール対応）
  /// qualityMode: "low"（スクロール中）, "high"（停止時）
  void sendViewport({
    required int viewportX,
    required int viewportY,
    required int viewportWidth,
    required int viewportHeight,
    required String qualityMode,
  }) {
    _send({
      'type': 'set_viewport',
      'viewport_x': viewportX,
      'viewport_y': viewportY,
      'viewport_width': viewportWidth,
      'viewport_height': viewportHeight,
      'quality_mode': qualityMode,
    });
  }

  void sendKeyPress(String key) {
    _send({
      'type': 'input',
      'action': 'key_press',
      'key': key,
    });
  }

  void sendKeyType(String text) {
    _send({
      'type': 'input',
      'action': 'key_type',
      'text': text,
    });
  }

  // システム制御
  void getRunningApps() {
    _send({'type': 'get_running_apps'});
  }

  void focusApp(String appName) {
    // ターゲットアプリを保存
    _safeSetState((s) => s.copyWith(targetApp: appName));
    _send({
      'type': 'focus_app',
      'app_name': appName,
    });
  }

  void spotlightSearch(String query) {
    _send({
      'type': 'spotlight_search',
      'query': query,
    });
  }

  void listDirectory(String path) {
    _send({
      'type': 'list_directory',
      'path': path,
    });
  }

  void openFile(String path) {
    _send({
      'type': 'open_file',
      'path': path,
    });
  }

  // ブラウザタブ
  void getBrowserTabs(String appName) {
    _send({
      'type': 'get_browser_tabs',
      'app_name': appName,
    });
  }

  void activateTab(String appName, int tabIndex) {
    _send({
      'type': 'activate_tab',
      'app_name': appName,
      'tab_index': tabIndex,
    });
  }

  // AppleScriptテキスト入力（より信頼性が高い）
  void typeText(String text) {
    _send({
      'type': 'type_text',
      'text': text,
    });
  }

  // テキスト入力後にEnterキーを押す
  void typeTextAndEnter(String text) {
    _send({
      'type': 'type_text_and_enter',
      'text': text,
    });
  }

  void pressKey(String key) {
    _send({
      'type': 'press_key',
      'key': key,
    });
  }

  // Terminal/iTermタブ
  void getTerminalTabs(String appName) {
    _send({
      'type': 'get_terminal_tabs',
      'app_name': appName,
    });
  }

  void activateTerminalTab(String appName, int windowIndex, int tabIndex) {
    // ターゲットアプリを保存
    _safeSetState((s) => s.copyWith(targetApp: '$appName (Window $windowIndex, Tab $tabIndex)'));
    _send({
      'type': 'activate_terminal_tab',
      'app_name': appName,
      'window_index': windowIndex,
      'tab_index': tabIndex,
    });
  }

  // アプリのウィンドウ一覧を取得
  void getAppWindows(String appName) {
    _send({
      'type': 'get_app_windows',
      'app_name': appName,
    });
  }

  // 特定のウィンドウをフォーカス
  void focusAppWindow(String appName, int windowIndex) {
    // ターゲットアプリを保存
    _safeSetState((s) => s.copyWith(targetApp: appName));
    _send({
      'type': 'focus_app_window',
      'app_name': appName,
      'window_index': windowIndex,
    });
  }

  // Messagesアプリのチャット一覧を取得
  void getMessagesChats() {
    _send({'type': 'get_messages_chats'});
  }

  // Messagesチャットを開く
  void openMessagesChat(String chatId) {
    _send({
      'type': 'open_messages_chat',
      'chat_id': chatId,
    });
  }

  // アプリを終了する
  void quitApp(String appName) {
    _send({
      'type': 'quit_app',
      'app_name': appName,
    });
    // アプリリストを更新
    Future.delayed(const Duration(milliseconds: 500), () {
      getRunningApps();
    });
  }

  // 現在のウィンドウ/タブを閉じる（Cmd+W）
  void closeWindow() {
    _send({'type': 'close_window'});
  }

  // 最前面ウィンドウの情報を取得
  void getWindowInfo() {
    _send({'type': 'get_window_info'});
  }

  // アプリをフォーカスしてウィンドウ情報を取得
  void focusAndGetWindow(String appName) {
    // windowInfoをクリアして新しい値を待つ
    _safeSetState((s) => s.copyWith(targetApp: appName, clearWindowInfo: true));
    _send({
      'type': 'focus_and_get_window',
      'app_name': appName,
    });
  }

  // ウィンドウを最大化
  void maximizeWindow() {
    _send({'type': 'maximize_window'});
  }

  // ウィンドウを指定サイズにリサイズ
  void resizeWindow(int width, int height) {
    _send({
      'type': 'resize_window',
      'width': width,
      'height': height,
    });
  }

  // キャプチャ領域を設定（高解像度フォーカス）
  void setCaptureRegion(int x, int y, int width, int height) {
    _send({
      'type': 'set_capture_region',
      'x': x,
      'y': y,
      'width': width,
      'height': height,
    });
  }

  // キャプチャ領域をリセット（全画面に戻す）
  void resetCaptureRegion() {
    _send({'type': 'reset_capture_region'});
  }

  // スクロール（縦横スクロール）
  // direction: "up", "down", "left", "right"
  // amount: スクロール量（デフォルト100）
  void scroll(String direction, {int amount = 100}) {
    print('[WebSocket] Sending scroll: $direction, amount: $amount');
    _send({
      'type': 'scroll',
      'direction': direction,
      'amount': amount,
    });
  }

  void _send(Map<String, dynamic> data) {
    if (_channel != null) {
      _channel!.sink.add(jsonEncode(data));
    }
  }

  /// シェルコマンドを実行して結果を返す
  Future<String> executeShellCommand(String command) async {
    if (_channel == null) {
      throw Exception('Not connected');
    }

    // 既存のCompleterがあればキャンセル
    _shellCommandCompleter?.completeError('Cancelled');
    _shellCommandCompleter = Completer<String>();

    _send({
      'type': 'shell_execute',
      'command': command,
    });

    // タイムアウト30秒
    return _shellCommandCompleter!.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () => 'Error: Command timed out',
    );
  }

  /// PTYセッションを開始
  void startPty() {
    if (_channel == null) return;
    _ptySessionActive = true;
    _send({'type': 'pty_start'});
  }

  /// PTYに入力を送信
  void sendPtyInput(String input) {
    if (_channel == null || !_ptySessionActive) return;
    _send({
      'type': 'pty_input',
      'input': input,
    });
  }

  /// PTY履歴を取得
  void getPtyHistory() {
    if (_channel == null) return;
    _send({'type': 'pty_get_history'});
  }

  /// PTYセッションがアクティブかどうか
  bool get isPtyActive => _ptySessionActive;

  /// 既存ターミナルウィンドウのコンテンツを取得（スクロールバック含む）
  Future<String> getTerminalContent(String appName) async {
    if (_channel == null) {
      throw Exception('Not connected');
    }

    // 既存のCompleterがあり、まだ完了していなければキャンセル
    if (_terminalContentCompleter != null && !_terminalContentCompleter!.isCompleted) {
      _terminalContentCompleter!.completeError('Cancelled');
    }
    _terminalContentCompleter = Completer<String>();

    _send({
      'type': 'get_terminal_content',
      'app_name': appName,
    });

    // タイムアウト10秒
    return _terminalContentCompleter!.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () => '',
    );
  }

  /// 既存ターミナルコンテンツを取得（ストリーム通知も行う）
  void requestTerminalContent(String appName) {
    if (_channel == null) return;
    _send({
      'type': 'get_terminal_content',
      'app_name': appName,
    });
  }

  /// H.264フレームをデコードして表示
  Future<void> _decodeH264Frame(Uint8List h264Data) async {
    // デコーダーが未初期化なら初期化
    if (!_h264DecoderInitialized) {
      _h264Decoder = H264DecoderService();
      try {
        await _h264Decoder!.initialize();
        // デコードされたフレームを受信するコールバック
        _h264Decoder!.onFrame = (jpegData, width, height) {
          _safeSetState((s) => s.copyWith(currentFrame: jpegData));
        };
        _h264DecoderInitialized = true;
        print('[WS-H264] Decoder initialized');
      } catch (e) {
        print('[WS-H264] Failed to initialize decoder: $e');
        return;
      }
    }

    // H.264フレームをデコード
    try {
      await _h264Decoder!.decode(h264Data);
    } catch (e) {
      print('[WS-H264] Decode error: $e');
    }
  }

  void _onMessage(dynamic message) {
    // バイナリデータ（画面フレーム）の処理
    if (message is List<int>) {
      final data = Uint8List.fromList(message);
      // H.264フレームをデコード
      _decodeH264Frame(data);
      return;
    }

    // テキストメッセージ（JSON）の処理
    try {
      print('[WebSocket] Received message: ${message.toString().substring(0, message.toString().length > 200 ? 200 : message.toString().length)}');
      final data = jsonDecode(message as String) as Map<String, dynamic>;
      final type = data['type'] as String;
      print('[WebSocket] Message type: $type');

      switch (type) {
        case 'auth_response':
          final success = data['success'] as bool;
          if (success) {
            ScreenInfo? screenInfo;
            if (data['screen_info'] != null) {
              screenInfo = ScreenInfo.fromJson(data['screen_info'] as Map<String, dynamic>);
            }
            _safeSetState((s) => s.copyWith(
              connectionState: WsConnectionState.connected,
              screenInfo: screenInfo,
            ));
          } else {
            _safeSetState((s) => s.copyWith(
              connectionState: WsConnectionState.error,
              errorMessage: '認証に失敗しました',
            ));
          }
          break;

        case 'command_list':
          final commandsJson = data['commands'] as List<dynamic>;
          final commands = commandsJson
              .map((c) => Command.fromJson(c as Map<String, dynamic>))
              .toList();
          _safeSetState((s) => s.copyWith(commands: commands));
          break;

        case 'execute_result':
          _safeSetState((s) => s.copyWith(
            lastOutput: data['output'] as String,
            lastSuccess: data['success'] as bool,
          ));
          break;

        case 'shell_execute_result':
          // シェルコマンド実行結果
          final output = data['output'] as String? ?? '';
          final success = data['success'] as bool? ?? false;
          if (_shellCommandCompleter != null && !_shellCommandCompleter!.isCompleted) {
            if (success) {
              _shellCommandCompleter!.complete(output);
            } else {
              _shellCommandCompleter!.complete('Error: $output');
            }
          }
          break;

        case 'pty_output':
          // PTY出力（リアルタイムストリーム）
          final output = data['output'] as String? ?? '';
          _ptyOutputController.add(output);
          break;

        case 'pty_history':
          // PTY履歴（接続時に過去のログを受信）
          final history = data['history'] as String? ?? '';
          if (history.isNotEmpty) {
            _ptyOutputController.add(history);
          }
          break;

        case 'terminal_content':
          // 既存ターミナルのコンテンツ（スクロールバック含む）
          final content = data['content'] as String? ?? '';
          final appName = data['app_name'] as String? ?? '';
          print('[WebSocket] Received terminal_content for $appName: ${content.length} chars');
          // ストリームに通知
          _terminalContentController.add(content);
          // Completerがあれば完了
          if (_terminalContentCompleter != null && !_terminalContentCompleter!.isCompleted) {
            _terminalContentCompleter!.complete(content);
          }
          break;

        case 'running_apps':
          final appsJson = data['apps'] as List<dynamic>;
          final apps = appsJson
              .map((a) => RunningApp.fromJson(a as Map<String, dynamic>))
              .toList();
          _safeSetState((s) => s.copyWith(runningApps: apps));
          break;

        case 'directory_contents':
          final entriesJson = data['entries'] as List<dynamic>;
          final entries = entriesJson
              .map((e) => FileEntry.fromJson(e as Map<String, dynamic>))
              .toList();
          _safeSetState((s) => s.copyWith(
            directoryContents: entries,
            currentDirectory: data['path'] as String,
          ));
          break;

        case 'focus_result':
          // フォーカス変更後、アプリ一覧を更新
          if (data['success'] as bool) {
            getRunningApps();
          }
          break;

        case 'browser_tabs':
          final tabsJson = data['tabs'] as List<dynamic>;
          final tabs = tabsJson
              .map((t) => BrowserTab.fromJson(t as Map<String, dynamic>))
              .toList();
          _safeSetState((s) => s.copyWith(browserTabs: tabs));
          break;

        case 'terminal_tabs':
          final tabsJson = data['tabs'] as List<dynamic>;
          final tabs = tabsJson
              .map((t) => TerminalTab.fromJson(t as Map<String, dynamic>))
              .toList();
          _safeSetState((s) => s.copyWith(terminalTabs: tabs));
          break;

        case 'app_windows':
          final windowsJson = data['windows'] as List<dynamic>;
          final windows = windowsJson
              .map((w) => WindowListItem.fromJson(w as Map<String, dynamic>))
              .toList();
          _safeSetState((s) => s.copyWith(appWindows: windows));
          break;

        case 'messages_chats':
          final chatsJson = data['chats'] as List<dynamic>;
          final chats = chatsJson
              .map((c) => MessagesChat.fromJson(c as Map<String, dynamic>))
              .toList();
          _safeSetState((s) => s.copyWith(messagesChats: chats));
          break;

        case 'window_info':
          final infoJson = data['info'];
          if (infoJson != null) {
            final info = AppWindowInfo.fromJson(infoJson as Map<String, dynamic>);
            _safeSetState((s) => s.copyWith(windowInfo: info));
          }
          break;

        case 'mouse_position':
          final x = data['x'] as int;
          final y = data['y'] as int;
          _safeSetState((s) => s.copyWith(pcMousePosition: MousePosition(x: x, y: y)));
          break;

        // WebRTCシグナリング
        case 'webrtc_offer':
          final sdp = data['sdp'] as String;
          print('[WebRTC] Received offer, creating answer...');
          _handleWebRTCOffer(sdp);
          break;

        case 'webrtc_ice_candidate':
          final candidateJson = data['candidate'] as String;
          print('[WebRTC] Received ICE candidate');
          _handleWebRTCIceCandidate(candidateJson);
          break;
      }
    } catch (e) {
      print('Error parsing message: $e');
    }
  }

  // WebRTCオファーを処理してアンサーを返す
  Future<void> _handleWebRTCOffer(String sdp) async {
    if (_webrtcService == null) {
      print('[WebRTC] Service not initialized');
      return;
    }

    final answer = await _webrtcService!.handleOffer(sdp);
    if (answer != null) {
      print('[WebRTC] Sending answer');
      _send({
        'type': 'webrtc_answer',
        'sdp': answer,
      });
    } else {
      print('[WebRTC] Failed to create answer');
    }
  }

  // WebRTC ICE候補を追加
  Future<void> _handleWebRTCIceCandidate(String candidateJson) async {
    if (_webrtcService == null) {
      print('[WebRTC] Service not initialized');
      return;
    }

    try {
      final candidateMap = jsonDecode(candidateJson) as Map<String, dynamic>;
      await _webrtcService!.addIceCandidate(candidateMap);
    } catch (e) {
      print('[WebRTC] Error parsing ICE candidate: $e');
    }
  }

  void _onError(dynamic error) {
    print('[WebSocket] Error: $error');
    _safeSetState((s) => s.copyWith(
      connectionState: WsConnectionState.error,
      errorMessage: error.toString(),
    ));
  }

  void _onDone() {
    print('[WebSocket] Connection closed (onDone)');
    // 接続中に切断された場合は認証失敗の可能性が高い
    if (state.connectionState == WsConnectionState.connecting) {
      print('[WebSocket] Connection closed during auth - likely auth failure');
      _safeSetState((s) => s.copyWith(
        connectionState: WsConnectionState.error,
        errorMessage: '認証に失敗しました。QRコードを再スキャンしてください。',
      ));
    } else {
      _safeSetState((s) => s.copyWith(connectionState: WsConnectionState.disconnected));
    }
    // 接続情報をクリア
    _connectionInfo = null;
    _channel = null;
  }
}

final webSocketProvider =
    StateNotifierProvider<WebSocketService, WebSocketState>((ref) {
  return WebSocketService();
});
