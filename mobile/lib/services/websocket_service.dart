import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/command.dart';
import '../models/connection_info.dart';

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

  RunningApp({required this.name, this.bundleId, required this.isActive});

  factory RunningApp.fromJson(Map<String, dynamic> json) {
    return RunningApp(
      name: json['name'] as String,
      bundleId: json['bundle_id'] as String?,
      isActive: json['is_active'] as bool? ?? false,
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
  });

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
      windowInfo: windowInfo ?? this.windowInfo,
      pcMousePosition: pcMousePosition ?? this.pcMousePosition,
    );
  }
}

class WebSocketService extends StateNotifier<WebSocketState> {
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  ConnectionInfo? _connectionInfo;

  WebSocketService() : super(WebSocketState());

  Future<void> connect(ConnectionInfo info) async {
    _connectionInfo = info;
    state = state.copyWith(connectionState: WsConnectionState.connecting);
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
        'device_name': 'Flutter App',
        'is_external': info.isExternal,
      };
      print('[WebSocket] Sending auth: $authMsg');
      _send(authMsg);
    } catch (e) {
      print('[WebSocket] Connection error: $e');
      state = state.copyWith(
        connectionState: WsConnectionState.error,
        errorMessage: e.toString(),
      );
    }
  }

  void disconnect() {
    _subscription?.cancel();
    _channel?.sink.close();
    _channel = null;
    state = WebSocketState();
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
    state = state.copyWith(isScreenSharing: true);
  }

  void stopScreenShare() {
    _send({'type': 'stop_screen_share'});
    state = state.copyWith(isScreenSharing: false, currentFrame: null);
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
    state = state.copyWith(targetApp: appName);
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
    state = state.copyWith(targetApp: '$appName (Window $windowIndex, Tab $tabIndex)');
    _send({
      'type': 'activate_terminal_tab',
      'app_name': appName,
      'window_index': windowIndex,
      'tab_index': tabIndex,
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
    state = state.copyWith(targetApp: appName);
    _send({
      'type': 'focus_and_get_window',
      'app_name': appName,
    });
  }

  // ウィンドウを最大化
  void maximizeWindow() {
    _send({'type': 'maximize_window'});
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

  void _send(Map<String, dynamic> data) {
    if (_channel != null) {
      _channel!.sink.add(jsonEncode(data));
    }
  }

  void _onMessage(dynamic message) {
    // バイナリデータ（画面フレーム）の処理
    if (message is List<int>) {
      state = state.copyWith(currentFrame: Uint8List.fromList(message));
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
            state = state.copyWith(
              connectionState: WsConnectionState.connected,
              screenInfo: screenInfo,
            );
          } else {
            state = state.copyWith(
              connectionState: WsConnectionState.error,
              errorMessage: '認証に失敗しました',
            );
          }
          break;

        case 'command_list':
          final commandsJson = data['commands'] as List<dynamic>;
          final commands = commandsJson
              .map((c) => Command.fromJson(c as Map<String, dynamic>))
              .toList();
          state = state.copyWith(commands: commands);
          break;

        case 'execute_result':
          state = state.copyWith(
            lastOutput: data['output'] as String,
            lastSuccess: data['success'] as bool,
          );
          break;

        case 'running_apps':
          final appsJson = data['apps'] as List<dynamic>;
          final apps = appsJson
              .map((a) => RunningApp.fromJson(a as Map<String, dynamic>))
              .toList();
          state = state.copyWith(runningApps: apps);
          break;

        case 'directory_contents':
          final entriesJson = data['entries'] as List<dynamic>;
          final entries = entriesJson
              .map((e) => FileEntry.fromJson(e as Map<String, dynamic>))
              .toList();
          state = state.copyWith(
            directoryContents: entries,
            currentDirectory: data['path'] as String,
          );
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
          state = state.copyWith(browserTabs: tabs);
          break;

        case 'terminal_tabs':
          final tabsJson = data['tabs'] as List<dynamic>;
          final tabs = tabsJson
              .map((t) => TerminalTab.fromJson(t as Map<String, dynamic>))
              .toList();
          state = state.copyWith(terminalTabs: tabs);
          break;

        case 'window_info':
          final infoJson = data['info'];
          if (infoJson != null) {
            final info = AppWindowInfo.fromJson(infoJson as Map<String, dynamic>);
            state = state.copyWith(windowInfo: info);
          }
          break;

        case 'mouse_position':
          final x = data['x'] as int;
          final y = data['y'] as int;
          state = state.copyWith(pcMousePosition: MousePosition(x: x, y: y));
          break;
      }
    } catch (e) {
      print('Error parsing message: $e');
    }
  }

  void _onError(dynamic error) {
    print('[WebSocket] Error: $error');
    state = state.copyWith(
      connectionState: WsConnectionState.error,
      errorMessage: error.toString(),
    );
  }

  void _onDone() {
    print('[WebSocket] Connection closed (onDone)');
    state = state.copyWith(connectionState: WsConnectionState.disconnected);
  }
}

final webSocketProvider =
    StateNotifierProvider<WebSocketService, WebSocketState>((ref) {
  return WebSocketService();
});
