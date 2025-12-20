mod screen_capture;
mod input_control;
mod system_control;
mod accessibility;
mod webrtc_screen;

use base64::{engine::general_purpose::STANDARD, Engine};
use futures_util::{SinkExt, StreamExt};
use image::Luma;
use parking_lot::RwLock;
use qrcode::QrCode;
use serde::{Deserialize, Serialize};
use std::io::Cursor;
use std::net::SocketAddr;
use std::sync::Arc;
use tauri::{AppHandle, Emitter};
use tokio::net::{TcpListener, TcpStream};
use tokio::sync::{broadcast, mpsc, Mutex};
use tokio_tungstenite::{accept_async, tungstenite::Message};

use screen_capture::ScreenCapturer;
use input_control::{InputController, InputEvent, get_mouse_position};
use system_control::{SystemController, RunningApp, FileEntry, BrowserTab, TerminalTab, AppWindowInfo, WindowListItem, MessagesChat};
use webrtc_screen::WebRTCScreenShare;

// 接続情報
#[derive(Clone, Serialize)]
pub struct ConnectionInfo {
    ip: String,
    port: u16,
    qr_code: String,
    auth_token: String,
}

// 接続状態
#[derive(Clone, Serialize)]
pub struct ConnectionStatus {
    connected: bool,
    device: Option<String>,
}

// コマンド定義
#[derive(Clone, Serialize, Deserialize)]
pub struct Command {
    id: String,
    name: String,
    command: String,
    icon: Option<String>,
}

// 画面情報
#[derive(Clone, Serialize, Deserialize)]
pub struct ScreenInfo {
    width: u32,
    height: u32,
}

// WebSocketメッセージ
#[derive(Serialize, Deserialize)]
#[serde(tag = "type")]
enum WsMessage {
    #[serde(rename = "auth")]
    Auth { token: String, device_name: String, #[serde(default)] is_external: bool },
    #[serde(rename = "auth_response")]
    AuthResponse { success: bool, screen_info: Option<ScreenInfo> },
    #[serde(rename = "command_list")]
    CommandList { commands: Vec<Command> },
    #[serde(rename = "execute")]
    Execute { command_id: String },
    #[serde(rename = "execute_result")]
    ExecuteResult { command_id: String, output: String, success: bool },
    #[serde(rename = "add_command")]
    AddCommand { name: String, command: String },
    #[serde(rename = "start_screen_share")]
    StartScreenShare,
    #[serde(rename = "stop_screen_share")]
    StopScreenShare,
    // キャプチャ領域設定（高解像度フォーカス）
    #[serde(rename = "set_capture_region")]
    SetCaptureRegion { x: i32, y: i32, width: i32, height: i32 },
    #[serde(rename = "reset_capture_region")]
    ResetCaptureRegion,
    // ビューポート設定（スクロール対応）
    #[serde(rename = "set_viewport")]
    SetViewport {
        viewport_x: i32,
        viewport_y: i32,
        viewport_width: i32,
        viewport_height: i32,
        quality_mode: String,  // "low" or "high"
    },
    // スクロール（ブラウザ等用）
    #[serde(rename = "scroll")]
    Scroll { direction: String, amount: i32 },
    // マウス位置
    #[serde(rename = "mouse_position")]
    MousePosition { x: i32, y: i32 },
    #[serde(rename = "input")]
    Input(InputEvent),
    // システム制御
    #[serde(rename = "get_running_apps")]
    GetRunningApps,
    #[serde(rename = "running_apps")]
    RunningApps { apps: Vec<RunningApp> },
    #[serde(rename = "focus_app")]
    FocusApp { app_name: String },
    #[serde(rename = "focus_result")]
    FocusResult { success: bool },
    #[serde(rename = "spotlight_search")]
    SpotlightSearch { query: String },
    #[serde(rename = "list_directory")]
    ListDirectory { path: String },
    #[serde(rename = "directory_contents")]
    DirectoryContents { path: String, entries: Vec<FileEntry> },
    #[serde(rename = "open_file")]
    OpenFile { path: String },
    // ブラウザタブ
    #[serde(rename = "get_browser_tabs")]
    GetBrowserTabs { app_name: String },
    #[serde(rename = "browser_tabs")]
    BrowserTabs { tabs: Vec<BrowserTab> },
    #[serde(rename = "activate_tab")]
    ActivateTab { app_name: String, tab_index: usize },
    #[serde(rename = "activate_tab_result")]
    ActivateTabResult { success: bool },
    // AppleScriptテキスト入力（より信頼性が高い）
    #[serde(rename = "type_text")]
    TypeText { text: String },
    #[serde(rename = "type_text_and_enter")]
    TypeTextAndEnter { text: String },
    #[serde(rename = "press_key")]
    PressKey { key: String },
    // Terminal/iTermタブ
    #[serde(rename = "get_terminal_tabs")]
    GetTerminalTabs { app_name: String },
    #[serde(rename = "terminal_tabs")]
    TerminalTabs { tabs: Vec<TerminalTab> },
    #[serde(rename = "activate_terminal_tab")]
    ActivateTerminalTab { app_name: String, window_index: usize, tab_index: usize },
    // アプリのウィンドウ一覧
    #[serde(rename = "get_app_windows")]
    GetAppWindows { app_name: String },
    #[serde(rename = "app_windows")]
    AppWindows { app_name: String, windows: Vec<WindowListItem> },
    // Messagesチャット一覧
    #[serde(rename = "get_messages_chats")]
    GetMessagesChats,
    #[serde(rename = "messages_chats")]
    MessagesChats { chats: Vec<MessagesChat> },
    #[serde(rename = "open_messages_chat")]
    OpenMessagesChat { chat_id: String },
    #[serde(rename = "focus_app_window")]
    FocusAppWindow { app_name: String, window_index: usize },
    // アプリ/ウィンドウを閉じる
    #[serde(rename = "quit_app")]
    QuitApp { app_name: String },
    #[serde(rename = "close_window")]
    CloseWindow,
    // ウィンドウ情報
    #[serde(rename = "get_window_info")]
    GetWindowInfo,
    #[serde(rename = "window_info")]
    WindowInfo { info: Option<AppWindowInfo> },
    #[serde(rename = "focus_and_get_window")]
    FocusAndGetWindow { app_name: String },
    #[serde(rename = "maximize_window")]
    MaximizeWindow,
    #[serde(rename = "resize_window")]
    ResizeWindow { width: i32, height: i32 },
    // WebRTCシグナリング
    #[serde(rename = "webrtc_offer")]
    WebRTCOffer { sdp: String },
    #[serde(rename = "webrtc_answer")]
    WebRTCAnswer { sdp: String },
    #[serde(rename = "webrtc_ice_candidate")]
    WebRTCIceCandidate { candidate: String },
    #[serde(rename = "start_webrtc")]
    StartWebRTC,
    #[serde(rename = "stop_webrtc")]
    StopWebRTC,
}

// トンネル情報
#[derive(Clone, Serialize)]
pub struct TunnelInfo {
    pub url: String,
    pub qr_code: String,
}

// 接続リクエスト（承認待ち）
#[derive(Clone, Debug, Serialize)]
pub struct ConnectionRequest {
    pub request_id: String,
    pub device_name: String,
    pub ip_address: String,
}

// アプリケーション状態
pub struct AppState {
    connection_info: RwLock<Option<ConnectionInfo>>,
    connected_device: RwLock<Option<String>>,
    commands: RwLock<Vec<Command>>,
    auth_token: String,
    screen_width: RwLock<u32>,
    screen_height: RwLock<u32>,
    frame_tx: broadcast::Sender<Vec<u8>>,
    input_controller: InputController,
    // キャプチャ領域（None = 全画面）- Arc<RwLock>でスレッド間共有
    capture_region: Arc<RwLock<Option<CaptureRegion>>>,
    // WSキャプチャ停止フラグ
    ws_capture_running: Arc<std::sync::atomic::AtomicBool>,
    // トンネル状態
    tunnel_info: RwLock<Option<TunnelInfo>>,
    tunnel_process: RwLock<Option<u32>>, // プロセスID
    // 接続承認用チャンネル
    pending_connections: RwLock<std::collections::HashMap<String, tokio::sync::oneshot::Sender<bool>>>,
    // ポーリング用: 保留中の接続リクエスト
    pending_requests: RwLock<Vec<ConnectionRequest>>,
}

#[derive(Clone, Debug)]
pub struct CaptureRegion {
    pub x: i32,
    pub y: i32,
    pub width: i32,
    pub height: i32,
    // ビューポート（ウィンドウ内の表示領域）
    pub viewport_x: i32,
    pub viewport_y: i32,
    pub viewport_width: i32,
    pub viewport_height: i32,
    // 画質モード: "low"（スクロール中）, "high"（停止時）
    pub quality_mode: String,
}

impl AppState {
    pub fn new() -> Self {
        let (frame_tx, _) = broadcast::channel(2);

        Self {
            connection_info: RwLock::new(None),
            connected_device: RwLock::new(None),
            commands: RwLock::new(vec![
                Command {
                    id: uuid::Uuid::new_v4().to_string(),
                    name: "ビルド".to_string(),
                    command: "npm run build".to_string(),
                    icon: Some("build".to_string()),
                },
                Command {
                    id: uuid::Uuid::new_v4().to_string(),
                    name: "テスト".to_string(),
                    command: "npm test".to_string(),
                    icon: Some("test".to_string()),
                },
            ]),
            auth_token: uuid::Uuid::new_v4().to_string(),
            screen_width: RwLock::new(0),
            screen_height: RwLock::new(0),
            frame_tx,
            input_controller: InputController::new(),
            capture_region: Arc::new(RwLock::new(None)),
            ws_capture_running: Arc::new(std::sync::atomic::AtomicBool::new(true)),
            tunnel_info: RwLock::new(None),
            tunnel_process: RwLock::new(None),
            pending_connections: RwLock::new(std::collections::HashMap::new()),
            pending_requests: RwLock::new(Vec::new()),
        }
    }
}

// QRコード生成
fn generate_qr_code(data: &str) -> Result<String, String> {
    let code = QrCode::new(data.as_bytes()).map_err(|e| e.to_string())?;
    let image = code.render::<Luma<u8>>().build();

    let mut buffer = Cursor::new(Vec::new());
    image
        .write_to(&mut buffer, image::ImageFormat::Png)
        .map_err(|e| e.to_string())?;

    Ok(STANDARD.encode(buffer.into_inner()))
}

// WebSocket接続処理
async fn handle_connection(
    stream: TcpStream,
    addr: SocketAddr,
    state: Arc<AppState>,
    app_handle: AppHandle,
) {
    let ws_stream = match accept_async(stream).await {
        Ok(ws) => ws,
        Err(e) => {
            eprintln!("WebSocket handshake failed: {}", e);
            return;
        }
    };

    println!("New connection from: {}", addr);
    let (write, mut read) = ws_stream.split();
    let write = Arc::new(Mutex::new(write));
    let mut authenticated = false;
    let mut screen_sharing = false;
    let mut frame_rx: Option<broadcast::Receiver<Vec<u8>>> = None;
    let mut mouse_interval = tokio::time::interval(std::time::Duration::from_millis(50));
    let mut last_mouse_pos: (i32, i32) = (-1, -1); // 最後に送信したマウス位置

    // WebRTC状態
    let mut webrtc_session: Option<Arc<WebRTCScreenShare>> = None;
    let (ice_tx, mut ice_rx) = mpsc::channel::<String>(100);

    loop {
        tokio::select! {
            // フレーム送信
            frame = async {
                if let Some(ref mut rx) = frame_rx {
                    rx.recv().await.ok()
                } else {
                    std::future::pending::<Option<Vec<u8>>>().await
                }
            }, if screen_sharing => {
                if let Some(frame_data) = frame {
                    // バイナリフレームとして送信
                    if write.lock().await.send(Message::Binary(frame_data.into())).await.is_err() {
                        break;
                    }
                }
            }

            // WebRTC ICE候補送信
            ice_candidate = ice_rx.recv() => {
                if let Some(candidate) = ice_candidate {
                    let response = WsMessage::WebRTCIceCandidate { candidate };
                    let json = serde_json::to_string(&response).unwrap();
                    write.lock().await.send(Message::Text(json.into())).await.ok();
                }
            }

            // マウス位置を定期送信（変化時のみ）
            _ = mouse_interval.tick(), if screen_sharing && authenticated => {
                if let Some((x, y)) = get_mouse_position() {
                    if (x, y) != last_mouse_pos {
                        last_mouse_pos = (x, y);
                        let response = WsMessage::MousePosition { x, y };
                        let json = serde_json::to_string(&response).unwrap();
                        write.lock().await.send(Message::Text(json.into())).await.ok();
                    }
                }
            }

            // メッセージ受信
            msg = read.next() => {
                let msg = match msg {
                    Some(Ok(m)) => m,
                    Some(Err(e)) => {
                        eprintln!("Error reading message: {}", e);
                        break;
                    }
                    None => break,
                };

                match msg {
                    Message::Text(text) => {
                        println!("Received text message: {}", &text[..text.len().min(200)]);
                        let parsed: Result<WsMessage, _> = serde_json::from_str(&text);

                        match parsed {
                            Ok(WsMessage::Auth { token, device_name, is_external }) => {
                                let token_valid = token == state.auth_token;
                                println!("Auth request: device={}, is_external={}, token_valid={}", device_name, is_external, token_valid);

                                if !token_valid {
                                    // トークンが無効な場合は即座に拒否
                                    let response = WsMessage::AuthResponse { success: false, screen_info: None };
                                    let json = serde_json::to_string(&response).unwrap();
                                    write.lock().await.send(Message::Text(json.into())).await.ok();
                                } else if is_external {
                                    // 外部接続（トンネル経由）の場合は承認不要
                                    println!("External connection - auto approving");
                                    authenticated = true;
                                    *state.connected_device.write() = Some(device_name.clone());
                                    app_handle.emit("device_connected", &device_name).ok();

                                    let screen_info = Some(ScreenInfo {
                                        width: *state.screen_width.read(),
                                        height: *state.screen_height.read(),
                                    });

                                    let response = WsMessage::AuthResponse { success: true, screen_info };
                                    let json = serde_json::to_string(&response).unwrap();
                                    write.lock().await.send(Message::Text(json.into())).await.ok();

                                    // コマンドリストを送信
                                    let commands = state.commands.read().clone();
                                    let cmd_list = WsMessage::CommandList { commands };
                                    let json = serde_json::to_string(&cmd_list).unwrap();
                                    write.lock().await.send(Message::Text(json.into())).await.ok();
                                } else {
                                    // ローカル接続の場合、ユーザーに承認を求める
                                    println!("Local connection - requesting user approval");
                                    let request_id = uuid::Uuid::new_v4().to_string();
                                    let (tx, rx) = tokio::sync::oneshot::channel::<bool>();

                                    // 承認待ちリストに追加
                                    state.pending_connections.write().insert(request_id.clone(), tx);

                                    // ポーリング用リストにも追加
                                    let connection_request = ConnectionRequest {
                                        request_id: request_id.clone(),
                                        device_name: device_name.clone(),
                                        ip_address: addr.ip().to_string(),
                                    };
                                    state.pending_requests.write().push(connection_request.clone());
                                    println!("Added to pending_requests: {:?}", connection_request);

                                    // フロントエンドにもイベントを送信（バックアップ）
                                    app_handle.emit("connection_request", &connection_request).ok();

                                    // ユーザーの承認を待つ（30秒タイムアウト）
                                    let approved = tokio::time::timeout(
                                        std::time::Duration::from_secs(30),
                                        rx
                                    ).await.unwrap_or(Ok(false)).unwrap_or(false);
                                    println!("Connection approval result: {}", approved);

                                    // 承認待ちリストから削除
                                    state.pending_connections.write().remove(&request_id);
                                    // ポーリング用リストからも削除
                                    state.pending_requests.write().retain(|r| r.request_id != request_id);

                                    if approved {
                                        authenticated = true;
                                        *state.connected_device.write() = Some(device_name.clone());
                                        app_handle.emit("device_connected", &device_name).ok();

                                        let screen_info = Some(ScreenInfo {
                                            width: *state.screen_width.read(),
                                            height: *state.screen_height.read(),
                                        });

                                        let response = WsMessage::AuthResponse { success: true, screen_info };
                                        let json = serde_json::to_string(&response).unwrap();
                                        write.lock().await.send(Message::Text(json.into())).await.ok();

                                        // コマンドリストを送信
                                        let commands = state.commands.read().clone();
                                        let cmd_list = WsMessage::CommandList { commands };
                                        let json = serde_json::to_string(&cmd_list).unwrap();
                                        write.lock().await.send(Message::Text(json.into())).await.ok();
                                    } else {
                                        // 拒否またはタイムアウト
                                        let response = WsMessage::AuthResponse { success: false, screen_info: None };
                                        let json = serde_json::to_string(&response).unwrap();
                                        write.lock().await.send(Message::Text(json.into())).await.ok();
                                    }
                                }
                            }
                            Ok(WsMessage::Execute { command_id }) if authenticated => {
                                let cmd_info = {
                                    let commands = state.commands.read();
                                    commands.iter().find(|c| c.id == command_id).map(|c| (c.id.clone(), c.command.clone()))
                                };

                                if let Some((id, command)) = cmd_info {
                                    let output = std::process::Command::new("sh")
                                        .arg("-c")
                                        .arg(&command)
                                        .output();

                                    let (output_str, success) = match output {
                                        Ok(o) => {
                                            let stdout = String::from_utf8_lossy(&o.stdout);
                                            let stderr = String::from_utf8_lossy(&o.stderr);
                                            let combined = format!("{}{}", stdout, stderr);
                                            (combined, o.status.success())
                                        }
                                        Err(e) => (e.to_string(), false),
                                    };

                                    let result = WsMessage::ExecuteResult {
                                        command_id: id,
                                        output: output_str,
                                        success,
                                    };
                                    let json = serde_json::to_string(&result).unwrap();
                                    write.lock().await.send(Message::Text(json.into())).await.ok();
                                }
                            }
                            Ok(WsMessage::AddCommand { name, command }) if authenticated => {
                                let new_cmd = Command {
                                    id: uuid::Uuid::new_v4().to_string(),
                                    name,
                                    command,
                                    icon: None,
                                };
                                state.commands.write().push(new_cmd);

                                let commands = state.commands.read().clone();
                                let cmd_list = WsMessage::CommandList { commands };
                                let json = serde_json::to_string(&cmd_list).unwrap();
                                write.lock().await.send(Message::Text(json.into())).await.ok();
                            }
                            Ok(WsMessage::StartScreenShare) if authenticated => {
                                println!("Starting screen share...");
                                frame_rx = Some(state.frame_tx.subscribe());
                                screen_sharing = true;
                                println!("Screen sharing started");
                            }
                            Ok(WsMessage::StopScreenShare) if authenticated => {
                                println!("Stopping screen share...");
                                screen_sharing = false;
                                frame_rx = None;
                            }
                            Ok(WsMessage::SetCaptureRegion { x, y, width, height }) if authenticated => {
                                println!("SetCaptureRegion: {}x{} at ({}, {})", width, height, x, y);
                                // 新しいCaptureRegion（ビューポートはウィンドウ全体、高画質モード）
                                *state.capture_region.write() = Some(CaptureRegion {
                                    x, y, width, height,
                                    viewport_x: 0,
                                    viewport_y: 0,
                                    viewport_width: width,
                                    viewport_height: height,
                                    quality_mode: "high".to_string(),
                                });
                            }
                            Ok(WsMessage::SetViewport { viewport_x, viewport_y, viewport_width, viewport_height, quality_mode }) if authenticated => {
                                // 既存のCaptureRegionのビューポートを更新
                                let mut region = state.capture_region.write();
                                if let Some(ref mut r) = *region {
                                    r.viewport_x = viewport_x;
                                    r.viewport_y = viewport_y;
                                    r.viewport_width = viewport_width;
                                    r.viewport_height = viewport_height;
                                    r.quality_mode = quality_mode.clone();
                                    if quality_mode == "high" {
                                        println!("SetViewport: {}x{} at ({}, {}) [HIGH QUALITY]", viewport_width, viewport_height, viewport_x, viewport_y);
                                    }
                                }
                            }
                            Ok(WsMessage::ResetCaptureRegion) if authenticated => {
                                println!("ResetCaptureRegion");
                                *state.capture_region.write() = None;
                            }
                            Ok(WsMessage::Scroll { direction, amount }) if authenticated => {
                                println!("Scroll: {} by {}", direction, amount);
                                state.input_controller.scroll(&direction, amount);
                            }
                            Ok(WsMessage::Input(event)) if authenticated => {
                                // スクロールはユーザーがタッチした位置で実行
                                // （マウスは既にその位置に移動済み）
                                state.input_controller.send_event(event);
                            }
                            Ok(WsMessage::GetRunningApps) if authenticated => {
                                println!("GetRunningApps requested");
                                // 非同期でブロッキング処理を実行（メッセージループをブロックしない）
                                let write_clone = write.clone();
                                tokio::spawn(async move {
                                    let apps = tokio::task::spawn_blocking(|| {
                                        SystemController::get_running_apps()
                                    }).await.unwrap_or_default();
                                    println!("GetRunningApps result: {} apps", apps.len());
                                    let response = WsMessage::RunningApps { apps };
                                    let json = serde_json::to_string(&response).unwrap();
                                    write_clone.lock().await.send(Message::Text(json.into())).await.ok();
                                });
                            }
                            Ok(WsMessage::FocusApp { app_name }) if authenticated => {
                                let name = app_name.clone();
                                let write_clone = write.clone();
                                tokio::spawn(async move {
                                    tokio::task::spawn_blocking(move || {
                                        SystemController::focus_app(&name)
                                    }).await.ok();
                                    let response = WsMessage::FocusResult { success: true };
                                    let json = serde_json::to_string(&response).unwrap();
                                    write_clone.lock().await.send(Message::Text(json.into())).await.ok();
                                });
                            }
                            Ok(WsMessage::SpotlightSearch { query }) if authenticated => {
                                tokio::task::spawn_blocking(move || {
                                    SystemController::spotlight_search(&query)
                                });
                            }
                            Ok(WsMessage::ListDirectory { path }) if authenticated => {
                                let p = path.clone();
                                let write_clone = write.clone();
                                tokio::spawn(async move {
                                    let entries = tokio::task::spawn_blocking(move || {
                                        SystemController::list_directory(&p)
                                    }).await.unwrap_or_default();
                                    let response = WsMessage::DirectoryContents {
                                        path: path.clone(),
                                        entries,
                                    };
                                    let json = serde_json::to_string(&response).unwrap();
                                    write_clone.lock().await.send(Message::Text(json.into())).await.ok();
                                });
                            }
                            Ok(WsMessage::OpenFile { path }) if authenticated => {
                                tokio::task::spawn_blocking(move || {
                                    SystemController::open_file(&path)
                                });
                            }
                            Ok(WsMessage::GetBrowserTabs { app_name }) if authenticated => {
                                println!("GetBrowserTabs: {}", app_name);
                                let name = app_name.clone();
                                let write_clone = write.clone();
                                tokio::spawn(async move {
                                    let tabs = tokio::task::spawn_blocking(move || {
                                        SystemController::get_browser_tabs(&name)
                                    }).await.unwrap_or_default();
                                    println!("GetBrowserTabs result: {} tabs", tabs.len());
                                    let response = WsMessage::BrowserTabs { tabs };
                                    let json = serde_json::to_string(&response).unwrap();
                                    write_clone.lock().await.send(Message::Text(json.into())).await.ok();
                                });
                            }
                            Ok(WsMessage::ActivateTab { app_name, tab_index }) if authenticated => {
                                let name = app_name.clone();
                                let write_clone = write.clone();
                                tokio::spawn(async move {
                                    tokio::task::spawn_blocking(move || {
                                        if name.to_lowercase().contains("safari") {
                                            SystemController::activate_safari_tab(tab_index)
                                        } else if name.to_lowercase().contains("chrome") {
                                            SystemController::activate_chrome_tab(tab_index)
                                        } else {
                                            false
                                        }
                                    }).await.ok();
                                    let response = WsMessage::ActivateTabResult { success: true };
                                    let json = serde_json::to_string(&response).unwrap();
                                    write_clone.lock().await.send(Message::Text(json.into())).await.ok();
                                });
                            }
                            // Messagesチャット
                            Ok(WsMessage::GetMessagesChats) if authenticated => {
                                println!("GetMessagesChats received");
                                let write_clone = write.clone();
                                tokio::spawn(async move {
                                    let chats = tokio::task::spawn_blocking(|| {
                                        SystemController::get_messages_chats()
                                    }).await.unwrap_or_default();
                                    let response = WsMessage::MessagesChats { chats };
                                    let json = serde_json::to_string(&response).unwrap();
                                    write_clone.lock().await.send(Message::Text(json.into())).await.ok();
                                });
                            }
                            Ok(WsMessage::OpenMessagesChat { chat_id }) if authenticated => {
                                println!("OpenMessagesChat: {}", chat_id);
                                let id = chat_id.clone();
                                tokio::task::spawn_blocking(move || {
                                    SystemController::open_messages_chat(&id);
                                });
                            }
                            Ok(WsMessage::TypeText { text }) if authenticated => {
                                println!("TypeText received: {}", text);
                                // ブロッキング処理を別スレッドで実行（画面共有を止めない）
                                tokio::task::spawn_blocking(move || {
                                    let success = SystemController::type_text(&text);
                                    println!("TypeText result: {}", success);
                                });
                            }
                            Ok(WsMessage::TypeTextAndEnter { text }) if authenticated => {
                                println!("TypeTextAndEnter received: {}", text);
                                // ブロッキング処理を別スレッドで実行（画面共有を止めない）
                                tokio::task::spawn_blocking(move || {
                                    let success = SystemController::type_text_and_enter(&text);
                                    println!("TypeTextAndEnter result: {}", success);
                                });
                            }
                            Ok(WsMessage::PressKey { key }) if authenticated => {
                                println!("PressKey received: {}", key);
                                // ブロッキング処理を別スレッドで実行
                                tokio::task::spawn_blocking(move || {
                                    let success = SystemController::press_key(&key);
                                    println!("PressKey result: {}", success);
                                });
                            }
                            Ok(WsMessage::GetTerminalTabs { app_name }) if authenticated => {
                                println!("GetTerminalTabs for: {}", app_name);
                                let name = app_name.clone();
                                let write_clone = write.clone();
                                tokio::spawn(async move {
                                    let tabs = tokio::task::spawn_blocking(move || {
                                        if name.to_lowercase().contains("iterm") {
                                            SystemController::get_iterm_tabs()
                                        } else {
                                            SystemController::get_terminal_tabs()
                                        }
                                    }).await.unwrap_or_default();
                                    let response = WsMessage::TerminalTabs { tabs };
                                    let json = serde_json::to_string(&response).unwrap();
                                    write_clone.lock().await.send(Message::Text(json.into())).await.ok();
                                });
                            }
                            Ok(WsMessage::ActivateTerminalTab { app_name, window_index, tab_index }) if authenticated => {
                                println!("ActivateTerminalTab: {} - win {} tab {}", app_name, window_index, tab_index);
                                let name = app_name.clone();
                                tokio::task::spawn_blocking(move || {
                                    let success = if name.to_lowercase().contains("iterm") {
                                        SystemController::activate_iterm_tab(window_index, tab_index)
                                    } else {
                                        SystemController::activate_terminal_tab(window_index, tab_index)
                                    };
                                    println!("ActivateTerminalTab result: {}", success);
                                });
                            }
                            Ok(WsMessage::GetAppWindows { app_name }) if authenticated => {
                                println!("GetAppWindows: {}", app_name);
                                let name = app_name.clone();
                                let write_clone = write.clone();
                                tokio::spawn(async move {
                                    let name_clone = name.clone();
                                    let windows = tokio::task::spawn_blocking(move || {
                                        SystemController::get_app_windows(&name_clone)
                                    }).await.unwrap_or_default();
                                    println!("GetAppWindows result: {} windows", windows.len());
                                    let response = WsMessage::AppWindows { app_name: name, windows };
                                    let json = serde_json::to_string(&response).unwrap();
                                    write_clone.lock().await.send(Message::Text(json.into())).await.ok();
                                });
                            }
                            Ok(WsMessage::FocusAppWindow { app_name, window_index }) if authenticated => {
                                println!("FocusAppWindow: {} - window {}", app_name, window_index);
                                tokio::task::spawn_blocking(move || {
                                    let success = SystemController::focus_app_window(&app_name, window_index);
                                    println!("FocusAppWindow result: {}", success);
                                });
                            }
                            Ok(WsMessage::QuitApp { app_name }) if authenticated => {
                                println!("QuitApp: {}", app_name);
                                tokio::task::spawn_blocking(move || {
                                    let success = SystemController::quit_app(&app_name);
                                    println!("QuitApp result: {}", success);
                                });
                            }
                            Ok(WsMessage::CloseWindow) if authenticated => {
                                println!("CloseWindow requested");
                                tokio::task::spawn_blocking(|| {
                                    let success = SystemController::close_current_window();
                                    println!("CloseWindow result: {}", success);
                                });
                            }
                            Ok(WsMessage::GetWindowInfo) if authenticated => {
                                println!("GetWindowInfo requested");
                                let write_clone = write.clone();
                                tokio::spawn(async move {
                                    let info = tokio::task::spawn_blocking(|| {
                                        SystemController::get_frontmost_window()
                                    }).await.unwrap_or(None);
                                    println!("WindowInfo: {:?}", info);
                                    let response = WsMessage::WindowInfo { info };
                                    let json = serde_json::to_string(&response).unwrap();
                                    write_clone.lock().await.send(Message::Text(json.into())).await.ok();
                                });
                            }
                            Ok(WsMessage::FocusAndGetWindow { app_name }) if authenticated => {
                                println!("FocusAndGetWindow: {}", app_name);
                                let write_clone = write.clone();
                                tokio::spawn(async move {
                                    let info = tokio::task::spawn_blocking(move || {
                                        SystemController::focus_and_get_window(&app_name)
                                    }).await.unwrap_or(None);
                                    println!("WindowInfo: {:?}", info);
                                    let response = WsMessage::WindowInfo { info };
                                    let json = serde_json::to_string(&response).unwrap();
                                    write_clone.lock().await.send(Message::Text(json.into())).await.ok();
                                });
                            }
                            Ok(WsMessage::MaximizeWindow) if authenticated => {
                                println!("MaximizeWindow requested");
                                tokio::task::spawn_blocking(|| {
                                    let success = SystemController::maximize_window();
                                    println!("MaximizeWindow result: {}", success);
                                });
                            }
                            Ok(WsMessage::ResizeWindow { width, height }) if authenticated => {
                                println!("ResizeWindow requested: {}x{}", width, height);
                                tokio::task::spawn_blocking(move || {
                                    let success = SystemController::resize_window(width, height);
                                    println!("ResizeWindow result: {}", success);
                                });
                            }
                            // WebRTC開始
                            Ok(WsMessage::StartWebRTC) if authenticated => {
                                println!("[WebRTC] Starting WebRTC session...");
                                // WSキャプチャを停止
                                state.ws_capture_running.store(false, std::sync::atomic::Ordering::SeqCst);
                                // キャプチャが完全に停止するまで待機
                                tokio::time::sleep(tokio::time::Duration::from_millis(200)).await;

                                // 新規接続時はキャプチャ領域をリセット（全画面キャプチャから開始）
                                *state.capture_region.write() = None;
                                println!("[WebRTC] Capture region reset to full screen");

                                let ice_tx_clone = ice_tx.clone();
                                let write_clone = write.clone();

                                match WebRTCScreenShare::new(ice_tx_clone, state.capture_region.clone()).await {
                                    Ok(session) => {
                                        let session = Arc::new(session);
                                        webrtc_session = Some(Arc::clone(&session));

                                        // オファー作成
                                        match session.create_offer().await {
                                            Ok(sdp) => {
                                                println!("[WebRTC] Offer created");
                                                let response = WsMessage::WebRTCOffer { sdp };
                                                let json = serde_json::to_string(&response).unwrap();
                                                write_clone.lock().await.send(Message::Text(json.into())).await.ok();
                                            }
                                            Err(e) => {
                                                eprintln!("[WebRTC] Failed to create offer: {}", e);
                                            }
                                        }
                                    }
                                    Err(e) => {
                                        eprintln!("[WebRTC] Failed to create session: {}", e);
                                    }
                                }
                            }
                            // WebRTCアンサー受信
                            Ok(WsMessage::WebRTCAnswer { sdp }) if authenticated => {
                                println!("[WebRTC] Received answer (length: {})", sdp.len());
                                if let Some(ref session) = webrtc_session {
                                    println!("[WebRTC] Setting answer...");
                                    if let Err(e) = session.set_answer(&sdp).await {
                                        eprintln!("[WebRTC] Failed to set answer: {}", e);
                                    } else {
                                        println!("[WebRTC] Answer set successfully, starting capture...");
                                        // 接続確立後、画面キャプチャ開始
                                        session.start_capture().await;
                                        println!("[WebRTC] Capture started");
                                    }
                                } else {
                                    eprintln!("[WebRTC] No session available to set answer!");
                                }
                            }
                            // WebRTC ICE候補受信
                            Ok(WsMessage::WebRTCIceCandidate { candidate }) if authenticated => {
                                if let Some(ref session) = webrtc_session {
                                    if let Err(e) = session.add_ice_candidate(&candidate).await {
                                        eprintln!("[WebRTC] Failed to add ICE candidate: {}", e);
                                    }
                                }
                            }
                            // WebRTC停止
                            Ok(WsMessage::StopWebRTC) if authenticated => {
                                println!("[WebRTC] Stopping WebRTC session...");
                                if let Some(session) = webrtc_session.take() {
                                    if let Err(e) = session.close().await {
                                        eprintln!("[WebRTC] Failed to close session: {}", e);
                                    }
                                }
                                // WSキャプチャを再開
                                state.ws_capture_running.store(true, std::sync::atomic::Ordering::SeqCst);
                            }
                            _ => {}
                        }
                    }
                    Message::Close(_) => break,
                    _ => {}
                }
            }
        }
    }

    println!("Connection closed: {}", addr);
    *state.connected_device.write() = None;
    app_handle.emit("device_disconnected", ()).ok();
}

// 画面キャプチャ開始
fn start_screen_capture(state: &Arc<AppState>) -> Result<(), String> {
    let capturer = ScreenCapturer::new()?;
    let (width, height) = capturer.get_dimensions();

    *state.screen_width.write() = width as u32;
    *state.screen_height.write() = height as u32;

    println!("Screen capture initialized: {}x{}", width, height);

    // キャプチャスレッドを開始（領域指定対応）
    ScreenCapturer::start_capture(width, height, state.frame_tx.clone(), state.capture_region.clone(), state.ws_capture_running.clone());

    Ok(())
}

// WebSocketサーバー起動
async fn start_server(state: Arc<AppState>, app_handle: AppHandle) -> Result<(), String> {
    // 画面キャプチャを開始
    start_screen_capture(&state)?;

    let port = 9876;
    let ip = local_ip_address::local_ip().map_err(|e| e.to_string())?;

    let listener = TcpListener::bind(format!("0.0.0.0:{}", port))
        .await
        .map_err(|e| e.to_string())?;

    // 接続情報を生成
    let connection_data = format!("{}:{}:{}", ip, port, state.auth_token);
    let qr_base64 = generate_qr_code(&connection_data)?;

    let info = ConnectionInfo {
        ip: ip.to_string(),
        port,
        qr_code: qr_base64,
        auth_token: state.auth_token.clone(),
    };
    *state.connection_info.write() = Some(info);

    println!("WebSocket server listening on {}:{}", ip, port);
    println!("Auth token: {}", state.auth_token);
    println!("Connection string: {}", connection_data);

    loop {
        let (stream, addr) = listener.accept().await.map_err(|e| e.to_string())?;
        let state_clone = state.clone();
        let app_handle_clone = app_handle.clone();

        tokio::spawn(async move {
            handle_connection(stream, addr, state_clone, app_handle_clone).await;
        });
    }
}

// Tauriコマンド: 接続情報取得
#[tauri::command]
fn get_connection_info(state: tauri::State<Arc<AppState>>) -> Option<ConnectionInfo> {
    state.connection_info.read().clone()
}

// Tauriコマンド: 接続状態取得
#[tauri::command]
fn get_connection_status(state: tauri::State<Arc<AppState>>) -> ConnectionStatus {
    let device = state.connected_device.read().clone();
    ConnectionStatus {
        connected: device.is_some(),
        device,
    }
}

// Tauriコマンド: アクセシビリティ権限チェック
#[tauri::command]
fn check_accessibility() -> bool {
    accessibility::check_accessibility_permission()
}

// Tauriコマンド: アクセシビリティ設定を開く
#[tauri::command]
fn open_accessibility_settings() -> bool {
    accessibility::open_accessibility_settings()
}

// Tauriコマンド: アクセシビリティ権限を要求（システムダイアログ表示）
#[tauri::command]
fn request_accessibility() -> bool {
    accessibility::request_accessibility_permission()
}

// Tauriコマンド: 保留中の接続リクエストを取得（ポーリング用）
#[tauri::command]
fn get_pending_request(state: tauri::State<Arc<AppState>>) -> Option<ConnectionRequest> {
    let pending = state.pending_requests.read();
    pending.first().cloned()
}

// Tauriコマンド: 接続リクエストを承認/拒否
#[tauri::command]
fn respond_to_connection(state: tauri::State<Arc<AppState>>, request_id: String, approved: bool) -> Result<(), String> {
    // ポーリング用リストからも削除
    state.pending_requests.write().retain(|r| r.request_id != request_id);

    let mut pending = state.pending_connections.write();
    if let Some(sender) = pending.remove(&request_id) {
        sender.send(approved).map_err(|_| "Failed to send response")?;
        Ok(())
    } else {
        Err("Connection request not found".to_string())
    }
}

// cloudflaredのローカルパスを取得
fn get_cloudflared_local_path() -> std::path::PathBuf {
    let data_dir = dirs::data_local_dir()
        .unwrap_or_else(|| std::path::PathBuf::from("."))
        .join("PocketRemote");
    data_dir.join("cloudflared")
}

// cloudflaredのパスを取得（システムまたはローカル）
fn get_cloudflared_path() -> Option<std::path::PathBuf> {
    // まずシステムにインストールされているか確認
    if std::process::Command::new("which")
        .arg("cloudflared")
        .output()
        .map(|o| o.status.success())
        .unwrap_or(false)
    {
        return Some(std::path::PathBuf::from("cloudflared"));
    }

    // ローカルにインストールされているか確認
    let local_path = get_cloudflared_local_path();
    if local_path.exists() {
        return Some(local_path);
    }

    None
}

// Tauriコマンド: cloudflaredがインストールされているかチェック
#[tauri::command]
fn check_cloudflared() -> bool {
    get_cloudflared_path().is_some()
}

// cloudflaredのインストール状態を詳細に返す
#[derive(Clone, Serialize)]
pub struct CloudflaredStatus {
    installed: bool,
    is_system: bool,
    is_local: bool,
    path: Option<String>,
}

#[tauri::command]
fn get_cloudflared_status() -> CloudflaredStatus {
    let system_installed = std::process::Command::new("which")
        .arg("cloudflared")
        .output()
        .map(|o| o.status.success())
        .unwrap_or(false);

    let local_path = get_cloudflared_local_path();
    let local_installed = local_path.exists();

    CloudflaredStatus {
        installed: system_installed || local_installed,
        is_system: system_installed,
        is_local: local_installed,
        path: if system_installed {
            Some("cloudflared".to_string())
        } else if local_installed {
            Some(local_path.to_string_lossy().to_string())
        } else {
            None
        },
    }
}

// Tauriコマンド: cloudflaredをダウンロード・インストール
#[tauri::command]
async fn install_cloudflared(app_handle: tauri::AppHandle) -> Result<(), String> {

    // アーキテクチャを判定
    let arch = if cfg!(target_arch = "aarch64") {
        "arm64"
    } else {
        "amd64"
    };

    let download_url = format!(
        "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-darwin-{}.tgz",
        arch
    );

    println!("Downloading cloudflared from: {}", download_url);
    app_handle.emit("cloudflared_install_progress", "ダウンロード中...").ok();

    // ダウンロード
    let response = reqwest::blocking::get(&download_url)
        .map_err(|e| format!("Download failed: {}", e))?;

    if !response.status().is_success() {
        return Err(format!("Download failed: HTTP {}", response.status()));
    }

    let bytes = response.bytes()
        .map_err(|e| format!("Failed to read response: {}", e))?;

    app_handle.emit("cloudflared_install_progress", "展開中...").ok();

    // 保存先ディレクトリを作成
    let data_dir = dirs::data_local_dir()
        .unwrap_or_else(|| std::path::PathBuf::from("."))
        .join("PocketRemote");
    std::fs::create_dir_all(&data_dir)
        .map_err(|e| format!("Failed to create directory: {}", e))?;

    // tgzを展開
    let tar_gz = flate2::read::GzDecoder::new(&bytes[..]);
    let mut archive = tar::Archive::new(tar_gz);

    let cloudflared_path = data_dir.join("cloudflared");

    for entry in archive.entries().map_err(|e| format!("Failed to read archive: {}", e))? {
        let mut entry = entry.map_err(|e| format!("Failed to read entry: {}", e))?;
        let path = entry.path().map_err(|e| format!("Failed to get path: {}", e))?;

        if path.file_name().map(|n| n == "cloudflared").unwrap_or(false) {
            let mut file = std::fs::File::create(&cloudflared_path)
                .map_err(|e| format!("Failed to create file: {}", e))?;

            std::io::copy(&mut entry, &mut file)
                .map_err(|e| format!("Failed to write file: {}", e))?;

            // 実行権限を付与
            #[cfg(unix)]
            {
                use std::os::unix::fs::PermissionsExt;
                let mut perms = std::fs::metadata(&cloudflared_path)
                    .map_err(|e| format!("Failed to get metadata: {}", e))?
                    .permissions();
                perms.set_mode(0o755);
                std::fs::set_permissions(&cloudflared_path, perms)
                    .map_err(|e| format!("Failed to set permissions: {}", e))?;
            }

            break;
        }
    }

    if !cloudflared_path.exists() {
        return Err("cloudflared binary not found in archive".to_string());
    }

    app_handle.emit("cloudflared_install_progress", "インストール完了").ok();
    println!("cloudflared installed to: {:?}", cloudflared_path);

    Ok(())
}

// Tauriコマンド: トンネルを開始
#[tauri::command]
async fn start_tunnel(state: tauri::State<'_, Arc<AppState>>, app_handle: tauri::AppHandle) -> Result<(), String> {
    // 既にトンネルが起動中なら何もしない
    if state.tunnel_process.read().is_some() {
        return Err("Tunnel is already running".to_string());
    }

    // cloudflaredのパスを取得
    let cloudflared_path = get_cloudflared_path()
        .ok_or("cloudflared is not installed")?;

    let port = 9876;
    let auth_token = state.auth_token.clone();

    // cloudflaredをバックグラウンドで起動
    let mut child = std::process::Command::new(&cloudflared_path)
        .args(["tunnel", "--url", &format!("http://localhost:{}", port)])
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::piped())
        .spawn()
        .map_err(|e| format!("Failed to start cloudflared: {}", e))?;

    let pid = child.id();
    *state.tunnel_process.write() = Some(pid);

    // stderrからURLをパース（cloudflaredはstderrに出力する）
    let stderr = child.stderr.take().ok_or("Failed to get stderr")?;
    let state_clone = state.inner().clone();
    let app_handle_clone = app_handle.clone();

    std::thread::spawn(move || {
        use std::io::{BufRead, BufReader};
        let reader = BufReader::new(stderr);

        for line in reader.lines() {
            if let Ok(line) = line {
                println!("cloudflared: {}", line);
                // URLを探す（例: https://xxxx-xxxx.trycloudflare.com）
                if line.contains(".trycloudflare.com") || line.contains("https://") {
                    if let Some(url) = extract_tunnel_url(&line) {
                        println!("Tunnel URL found: {}", url);

                        // WebSocket URLを生成（https -> wss）
                        let ws_url = url.replace("https://", "wss://");
                        let connection_string = format!("{}:{}", ws_url, auth_token);

                        // QRコードを生成
                        match generate_qr_code(&connection_string) {
                            Ok(qr_code) => {
                                println!("QR code generated successfully");
                                let tunnel_info = TunnelInfo {
                                    url: url.clone(),
                                    qr_code,
                                };
                                *state_clone.tunnel_info.write() = Some(tunnel_info.clone());

                                // フロントエンドにイベントを送信
                                match app_handle_clone.emit("tunnel_started", &tunnel_info) {
                                    Ok(_) => println!("tunnel_started event emitted successfully"),
                                    Err(e) => println!("Failed to emit tunnel_started: {}", e),
                                }
                            }
                            Err(e) => println!("Failed to generate QR code: {}", e),
                        }
                    }
                }
            }
        }
    });

    Ok(())
}

// URLを抽出するヘルパー関数
fn extract_tunnel_url(line: &str) -> Option<String> {
    // "https://xxxx.trycloudflare.com" のようなURLを探す
    let patterns = [".trycloudflare.com", ".cloudflare.dev"];

    for pattern in patterns {
        if let Some(end_pos) = line.find(pattern) {
            // https://の開始位置を探す
            if let Some(start_pos) = line[..end_pos].rfind("https://") {
                let url_end = end_pos + pattern.len();
                return Some(line[start_pos..url_end].to_string());
            }
        }
    }
    None
}

// Tauriコマンド: トンネルを停止
#[tauri::command]
fn stop_tunnel(state: tauri::State<Arc<AppState>>) -> Result<(), String> {
    if let Some(pid) = state.tunnel_process.write().take() {
        // プロセスを終了
        #[cfg(unix)]
        {
            let _ = std::process::Command::new("kill")
                .args(["-9", &pid.to_string()])
                .spawn();
        }
        #[cfg(not(unix))]
        {
            std::process::Command::new("taskkill")
                .args(["/F", "/PID", &pid.to_string()])
                .spawn()
                .ok();
        }

        *state.tunnel_info.write() = None;
        println!("Tunnel stopped");
    }
    Ok(())
}

// Tauriコマンド: トンネル情報を取得
#[tauri::command]
fn get_tunnel_info(state: tauri::State<Arc<AppState>>) -> Option<TunnelInfo> {
    state.tunnel_info.read().clone()
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    let state = Arc::new(AppState::new());
    let state_clone = state.clone();

    tauri::Builder::default()
        .plugin(tauri_plugin_shell::init())
        .manage(state)
        .invoke_handler(tauri::generate_handler![
            get_connection_info,
            get_connection_status,
            check_accessibility,
            open_accessibility_settings,
            request_accessibility,
            get_pending_request,
            respond_to_connection,
            check_cloudflared,
            get_cloudflared_status,
            install_cloudflared,
            start_tunnel,
            stop_tunnel,
            get_tunnel_info,
        ])
        .setup(move |app| {
            let app_handle = app.handle().clone();
            let state = state_clone.clone();

            // WebSocketサーバーをバックグラウンドで起動
            tauri::async_runtime::spawn(async move {
                if let Err(e) = start_server(state, app_handle).await {
                    eprintln!("Server error: {}", e);
                }
            });

            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
