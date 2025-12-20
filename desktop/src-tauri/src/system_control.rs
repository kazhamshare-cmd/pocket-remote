use serde::{Deserialize, Serialize};
use std::process::Command;

#[cfg(target_os = "windows")]
use std::os::windows::process::CommandExt;

#[cfg(target_os = "windows")]
const CREATE_NO_WINDOW: u32 = 0x08000000;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RunningApp {
    pub name: String,
    pub bundle_id: Option<String>,
    pub is_active: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BrowserTab {
    pub index: usize,
    pub title: String,
    pub url: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FileEntry {
    pub name: String,
    pub path: String,
    pub is_directory: bool,
    pub size: Option<u64>,
}

/// Terminalのタブ情報
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TerminalTab {
    pub window_index: usize,
    pub tab_index: usize,
    pub title: String,
    pub is_busy: bool,
}

/// ウィンドウ情報
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AppWindowInfo {
    pub app_name: String,
    pub window_title: String,
    pub x: i32,
    pub y: i32,
    pub width: i32,
    pub height: i32,
}

/// アプリのウィンドウ一覧用
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WindowListItem {
    pub index: usize,
    pub title: String,
    pub is_minimized: bool,
}

/// Messagesアプリのチャット情報
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MessagesChat {
    pub id: String,
    pub name: String,
    pub service: String,  // SMS, iMessage等
}

pub struct SystemController;

impl SystemController {
    /// 起動中のアプリケーション一覧を取得（高速版）
    #[cfg(target_os = "macos")]
    pub fn get_running_apps() -> Vec<RunningApp> {
        // ウィンドウ操作がうまくいかないアプリのブロックリスト
        // ※最小限のシステムUIコンポーネントのみ
        let blocklist = [
            "Control Center",
            "SystemUIServer",
            "NotificationCenter",
            "AirPlayUIAgent",
            "TextInputMenuAgent",
            "TextInputSwitcher",
            "universalAccessAuthWarn",
            "CoreServicesUIAgent",
            "UserNotificationCenter",
        ];

        // 高速化: 一括取得でループを避ける、明示的なデリミタを使用
        let script = r#"
            tell application "System Events"
                set frontApp to ""
                try
                    set frontApp to name of first application process whose frontmost is true
                end try
                set appNames to name of every application process whose background only is false
                set AppleScript's text item delimiters to "|||"
                set appNamesText to appNames as text
                set AppleScript's text item delimiters to ""
                return frontApp & ":::" & appNamesText
            end tell
        "#;

        let output = Command::new("osascript")
            .arg("-e")
            .arg(script)
            .output();

        match output {
            Ok(o) => {
                let stdout = String::from_utf8_lossy(&o.stdout).trim().to_string();
                // フォーマット: "FrontApp:::App1|||App2|||App3|||..."
                let parts: Vec<&str> = stdout.splitn(2, ":::").collect();
                if parts.len() == 2 {
                    let front_app = parts[0];
                    let app_names: Vec<&str> = parts[1].split("|||").collect();
                    return app_names
                        .into_iter()
                        .filter(|name| !name.is_empty())
                        .filter(|name| !blocklist.iter().any(|blocked| name == blocked))
                        .map(|name| RunningApp {
                            name: name.to_string(),
                            bundle_id: None,
                            is_active: name == front_app,
                        })
                        .collect();
                }
            }
            Err(e) => {
                eprintln!("Failed to get running apps: {}", e);
            }
        }
        Vec::new()
    }

    /// 起動中のアプリケーション一覧を取得（Windows版）
    #[cfg(target_os = "windows")]
    pub fn get_running_apps() -> Vec<RunningApp> {
        // PowerShellでウィンドウを持つプロセス一覧を取得
        let script = r#"
            $foreground = (Get-Process | Where-Object {$_.MainWindowHandle -eq (Add-Type -MemberDefinition '[DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();' -Name 'Win32' -Namespace 'Native' -PassThru)::GetForegroundWindow()}).ProcessName
            Get-Process | Where-Object {$_.MainWindowTitle -ne ''} | ForEach-Object {
                $name = $_.ProcessName
                $isActive = if ($name -eq $foreground) {'true'} else {'false'}
                "$name|||$isActive"
            }
        "#;

        let mut cmd = Command::new("powershell");
        cmd.args(["-NoProfile", "-Command", script]);
        cmd.creation_flags(CREATE_NO_WINDOW);

        match cmd.output() {
            Ok(o) => {
                let stdout = String::from_utf8_lossy(&o.stdout);
                stdout
                    .lines()
                    .filter_map(|line| {
                        let parts: Vec<&str> = line.split("|||").collect();
                        if parts.len() >= 2 {
                            Some(RunningApp {
                                name: parts[0].to_string(),
                                bundle_id: None,
                                is_active: parts[1] == "true",
                            })
                        } else {
                            None
                        }
                    })
                    .collect()
            }
            Err(e) => {
                eprintln!("Failed to get running apps: {}", e);
                Vec::new()
            }
        }
    }

    /// アプリをフォーカス（アクティブに）- macOS版
    #[cfg(target_os = "macos")]
    pub fn focus_app(app_name: &str) -> bool {
        // タイムアウト付きでアプリをアクティブ化
        // 一部のアプリ（Messages等）はactivateがハングすることがある
        let script = format!(
            r#"
            with timeout of 2 seconds
                tell application "{}" to activate
            end timeout
            "#,
            app_name.replace("\"", "\\\"")
        );

        Command::new("osascript")
            .arg("-e")
            .arg(&script)
            .status()
            .map(|s| s.success())
            .unwrap_or(false)
    }

    /// アプリをフォーカス（アクティブに）- Windows版
    #[cfg(target_os = "windows")]
    pub fn focus_app(app_name: &str) -> bool {
        let script = format!(
            r#"
            $proc = Get-Process -Name '{}' -ErrorAction SilentlyContinue | Where-Object {{$_.MainWindowHandle -ne 0}} | Select-Object -First 1
            if ($proc) {{
                Add-Type -TypeDefinition @'
                using System;
                using System.Runtime.InteropServices;
                public class Win32 {{
                    [DllImport("user32.dll")]
                    public static extern bool SetForegroundWindow(IntPtr hWnd);
                    [DllImport("user32.dll")]
                    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
                }}
'@
                [Win32]::ShowWindow($proc.MainWindowHandle, 9)
                [Win32]::SetForegroundWindow($proc.MainWindowHandle)
            }}
            "#,
            app_name.replace("'", "''")
        );

        let mut cmd = Command::new("powershell");
        cmd.args(["-NoProfile", "-Command", &script]);
        cmd.creation_flags(CREATE_NO_WINDOW);
        cmd.status().map(|s| s.success()).unwrap_or(false)
    }

    /// アプリのウィンドウ一覧を取得 - macOS版
    #[cfg(target_os = "macos")]
    pub fn get_app_windows(app_name: &str) -> Vec<WindowListItem> {
        let escaped_name = app_name.replace("\"", "\\\"");

        // System Eventsを使用してウィンドウ一覧を取得
        let script = format!(
            r#"
            tell application "System Events"
                tell process "{}"
                    set windowList to {{}}
                    set windowCount to count of windows
                    repeat with i from 1 to windowCount
                        set w to window i
                        set wTitle to ""
                        set wMinimized to false
                        try
                            set wTitle to name of w
                        end try
                        try
                            set wMinimized to value of attribute "AXMinimized" of w
                        end try
                        set end of windowList to (i as text) & ":::" & wTitle & ":::" & (wMinimized as text)
                    end repeat
                    set AppleScript's text item delimiters to "|||"
                    set windowListText to windowList as text
                    set AppleScript's text item delimiters to ""
                    return windowListText
                end tell
            end tell
            "#,
            escaped_name
        );

        let output = Command::new("osascript")
            .arg("-e")
            .arg(&script)
            .output();

        match output {
            Ok(o) => {
                let stdout = String::from_utf8_lossy(&o.stdout).trim().to_string();
                if stdout.is_empty() {
                    return Vec::new();
                }

                stdout
                    .split("|||")
                    .filter_map(|entry| {
                        let parts: Vec<&str> = entry.splitn(3, ":::").collect();
                        if parts.len() >= 2 {
                            let index = parts[0].parse::<usize>().unwrap_or(1);
                            let title = parts[1].to_string();
                            let is_minimized = parts.get(2).map(|s| *s == "true").unwrap_or(false);
                            Some(WindowListItem {
                                index,
                                title,
                                is_minimized,
                            })
                        } else {
                            None
                        }
                    })
                    .collect()
            }
            Err(e) => {
                eprintln!("Failed to get windows for {}: {}", app_name, e);
                Vec::new()
            }
        }
    }

    /// アプリのウィンドウ一覧を取得 - Windows版
    #[cfg(target_os = "windows")]
    pub fn get_app_windows(app_name: &str) -> Vec<WindowListItem> {
        // Windowsではプロセスごとにメインウィンドウタイトルを取得
        let script = format!(
            r#"
            $index = 1
            Get-Process -Name '{}' -ErrorAction SilentlyContinue | Where-Object {{$_.MainWindowTitle -ne ''}} | ForEach-Object {{
                $title = $_.MainWindowTitle
                "$index:::$title:::false"
                $index++
            }}
            "#,
            app_name.replace("'", "''")
        );

        let mut cmd = Command::new("powershell");
        cmd.args(["-NoProfile", "-Command", &script]);
        cmd.creation_flags(CREATE_NO_WINDOW);

        match cmd.output() {
            Ok(o) => {
                let stdout = String::from_utf8_lossy(&o.stdout);
                stdout
                    .lines()
                    .filter_map(|line| {
                        let parts: Vec<&str> = line.splitn(3, ":::").collect();
                        if parts.len() >= 2 {
                            let index = parts[0].parse::<usize>().unwrap_or(1);
                            let title = parts[1].to_string();
                            let is_minimized = parts.get(2).map(|s| *s == "true").unwrap_or(false);
                            Some(WindowListItem {
                                index,
                                title,
                                is_minimized,
                            })
                        } else {
                            None
                        }
                    })
                    .collect()
            }
            Err(e) => {
                eprintln!("Failed to get windows for {}: {}", app_name, e);
                Vec::new()
            }
        }
    }

    /// 特定のウィンドウをフォーカス（インデックス指定）- macOS版
    #[cfg(target_os = "macos")]
    pub fn focus_app_window(app_name: &str, window_index: usize) -> bool {
        let escaped_name = app_name.replace("\"", "\\\"");

        // 特定のウィンドウだけを最前面に（他のウィンドウは移動しない）
        // System Eventsを使って直接ウィンドウを操作
        let script = format!(
            r#"
            tell application "System Events"
                tell process "{}"
                    try
                        -- 指定ウィンドウを取得
                        set targetWindow to window {}
                        -- ウィンドウを最前面に上げる
                        perform action "AXRaise" of targetWindow
                        -- プロセスを最前面に
                        set frontmost to true
                    end try
                end tell
            end tell
            "#,
            escaped_name, window_index
        );

        Command::new("osascript")
            .arg("-e")
            .arg(&script)
            .status()
            .map(|s| s.success())
            .unwrap_or(false)
    }

    /// 特定のウィンドウをフォーカス（インデックス指定）- Windows版
    #[cfg(target_os = "windows")]
    pub fn focus_app_window(app_name: &str, _window_index: usize) -> bool {
        // Windowsでは単にアプリをフォーカス（複数ウィンドウの選択は簡略化）
        Self::focus_app(app_name)
    }

    /// アプリを終了する - macOS版
    #[cfg(target_os = "macos")]
    pub fn quit_app(app_name: &str) -> bool {
        let script = format!(
            r#"tell application "{}" to quit"#,
            app_name.replace("\"", "\\\"")
        );

        Command::new("osascript")
            .arg("-e")
            .arg(&script)
            .status()
            .map(|s| s.success())
            .unwrap_or(false)
    }

    /// アプリを終了する - Windows版
    #[cfg(target_os = "windows")]
    pub fn quit_app(app_name: &str) -> bool {
        let mut cmd = Command::new("taskkill");
        cmd.args(["/IM", &format!("{}.exe", app_name), "/F"]);
        cmd.creation_flags(CREATE_NO_WINDOW);
        cmd.status().map(|s| s.success()).unwrap_or(false)
    }

    /// 現在のウィンドウ/タブを閉じる（Cmd+W / Ctrl+W）- macOS版
    #[cfg(target_os = "macos")]
    pub fn close_current_window() -> bool {
        let script = r#"
            tell application "System Events"
                keystroke "w" using command down
            end tell
        "#;

        Command::new("osascript")
            .arg("-e")
            .arg(script)
            .status()
            .map(|s| s.success())
            .unwrap_or(false)
    }

    /// 現在のウィンドウ/タブを閉じる（Ctrl+W）- Windows版
    #[cfg(target_os = "windows")]
    pub fn close_current_window() -> bool {
        // Ctrl+W を送信
        let script = r#"
            Add-Type -TypeDefinition @'
            using System;
            using System.Runtime.InteropServices;
            public class Keyboard {
                [DllImport("user32.dll")]
                public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);
            }
'@
            $VK_CONTROL = 0x11
            $VK_W = 0x57
            $KEYDOWN = 0x0000
            $KEYUP = 0x0002
            [Keyboard]::keybd_event($VK_CONTROL, 0, $KEYDOWN, [UIntPtr]::Zero)
            [Keyboard]::keybd_event($VK_W, 0, $KEYDOWN, [UIntPtr]::Zero)
            Start-Sleep -Milliseconds 50
            [Keyboard]::keybd_event($VK_W, 0, $KEYUP, [UIntPtr]::Zero)
            [Keyboard]::keybd_event($VK_CONTROL, 0, $KEYUP, [UIntPtr]::Zero)
        "#;

        let mut cmd = Command::new("powershell");
        cmd.args(["-NoProfile", "-Command", script]);
        cmd.creation_flags(CREATE_NO_WINDOW);
        cmd.status().map(|s| s.success()).unwrap_or(false)
    }

    /// Spotlight検索を開いてクエリを入力 - macOS版
    #[cfg(target_os = "macos")]
    pub fn spotlight_search(query: &str) -> bool {
        let escaped = query
            .replace("\\", "\\\\")
            .replace("\"", "\\\"");

        // Cmd+Space でSpotlightを開き、クリップボード経由でペースト
        let script = format!(
            r#"
            -- クリップボードにクエリを設定
            set the clipboard to "{}"

            -- Cmd+Space でSpotlightを開く
            tell application "System Events"
                key code 49 using {{command down}}
            end tell

            -- Spotlightが開くのを待つ
            delay 0.3

            -- Cmd+V でペースト
            tell application "System Events"
                keystroke "v" using command down
            end tell

            delay 0.1
            "#,
            escaped
        );

        Command::new("osascript")
            .arg("-e")
            .arg(&script)
            .status()
            .map(|s| s.success())
            .unwrap_or(false)
    }

    /// Windows検索を開いてクエリを入力 - Windows版
    #[cfg(target_os = "windows")]
    pub fn spotlight_search(query: &str) -> bool {
        // Win+S で検索を開き、クエリを入力
        let script = format!(
            r#"
            Set-Clipboard -Value '{}'
            Add-Type -TypeDefinition @'
            using System;
            using System.Runtime.InteropServices;
            public class Keyboard {{
                [DllImport("user32.dll")]
                public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);
            }}
'@
            $VK_LWIN = 0x5B
            $VK_S = 0x53
            $VK_CONTROL = 0x11
            $VK_V = 0x56
            $KEYDOWN = 0x0000
            $KEYUP = 0x0002
            # Win+S
            [Keyboard]::keybd_event($VK_LWIN, 0, $KEYDOWN, [UIntPtr]::Zero)
            [Keyboard]::keybd_event($VK_S, 0, $KEYDOWN, [UIntPtr]::Zero)
            Start-Sleep -Milliseconds 50
            [Keyboard]::keybd_event($VK_S, 0, $KEYUP, [UIntPtr]::Zero)
            [Keyboard]::keybd_event($VK_LWIN, 0, $KEYUP, [UIntPtr]::Zero)
            Start-Sleep -Milliseconds 300
            # Ctrl+V
            [Keyboard]::keybd_event($VK_CONTROL, 0, $KEYDOWN, [UIntPtr]::Zero)
            [Keyboard]::keybd_event($VK_V, 0, $KEYDOWN, [UIntPtr]::Zero)
            Start-Sleep -Milliseconds 50
            [Keyboard]::keybd_event($VK_V, 0, $KEYUP, [UIntPtr]::Zero)
            [Keyboard]::keybd_event($VK_CONTROL, 0, $KEYUP, [UIntPtr]::Zero)
            "#,
            query.replace("'", "''")
        );

        let mut cmd = Command::new("powershell");
        cmd.args(["-NoProfile", "-Command", &script]);
        cmd.creation_flags(CREATE_NO_WINDOW);
        cmd.status().map(|s| s.success()).unwrap_or(false)
    }

    /// ディレクトリの内容を取得
    pub fn list_directory(path: &str) -> Vec<FileEntry> {
        let path = if path.is_empty() || path == "~" {
            dirs::home_dir()
                .map(|p| p.to_string_lossy().to_string())
                .unwrap_or_else(|| "/".to_string())
        } else if path.starts_with("~") {
            dirs::home_dir()
                .map(|p| path.replacen("~", &p.to_string_lossy(), 1))
                .unwrap_or_else(|| path.to_string())
        } else {
            path.to_string()
        };

        let mut entries = Vec::new();

        // 親ディレクトリへのエントリを追加（ルート以外）
        if path != "/" {
            if let Some(parent) = std::path::Path::new(&path).parent() {
                entries.push(FileEntry {
                    name: "..".to_string(),
                    path: parent.to_string_lossy().to_string(),
                    is_directory: true,
                    size: None,
                });
            }
        }

        match std::fs::read_dir(&path) {
            Ok(dir) => {
                for entry in dir.flatten() {
                    let file_name = entry.file_name().to_string_lossy().to_string();

                    // 隠しファイルをスキップ（オプション）
                    if file_name.starts_with('.') {
                        continue;
                    }

                    let metadata = entry.metadata().ok();
                    let is_dir = metadata.as_ref().map(|m| m.is_dir()).unwrap_or(false);
                    let size = if is_dir {
                        None
                    } else {
                        metadata.as_ref().map(|m| m.len())
                    };

                    entries.push(FileEntry {
                        name: file_name,
                        path: entry.path().to_string_lossy().to_string(),
                        is_directory: is_dir,
                        size,
                    });
                }

                // ディレクトリを先に、その後ファイルをソート
                entries.sort_by(|a, b| {
                    if a.name == ".." {
                        std::cmp::Ordering::Less
                    } else if b.name == ".." {
                        std::cmp::Ordering::Greater
                    } else if a.is_directory && !b.is_directory {
                        std::cmp::Ordering::Less
                    } else if !a.is_directory && b.is_directory {
                        std::cmp::Ordering::Greater
                    } else {
                        a.name.to_lowercase().cmp(&b.name.to_lowercase())
                    }
                });
            }
            Err(e) => {
                eprintln!("Failed to read directory {}: {}", path, e);
            }
        }

        entries
    }

    /// ファイルを開く - macOS版
    #[cfg(target_os = "macos")]
    pub fn open_file(path: &str) -> bool {
        Command::new("open")
            .arg(path)
            .status()
            .map(|s| s.success())
            .unwrap_or(false)
    }

    /// ファイルを開く - Windows版
    #[cfg(target_os = "windows")]
    pub fn open_file(path: &str) -> bool {
        Command::new("cmd")
            .args(["/C", "start", "", path])
            .creation_flags(CREATE_NO_WINDOW)
            .status()
            .map(|s| s.success())
            .unwrap_or(false)
    }

    /// Safari/Chromeのタブ一覧を取得 - macOS版
    #[cfg(target_os = "macos")]
    pub fn get_browser_tabs(app_name: &str) -> Vec<BrowserTab> {
        let script = if app_name.to_lowercase().contains("safari") {
            r#"
            tell application "Safari"
                set tabList to {}
                set tabIndex to 1
                repeat with w in windows
                    repeat with t in tabs of w
                        set tabTitle to name of t
                        set tabUrl to URL of t
                        set end of tabList to {tabIndex, tabTitle, tabUrl}
                        set tabIndex to tabIndex + 1
                    end repeat
                end repeat
                return tabList
            end tell
            "#.to_string()
        } else if app_name.to_lowercase().contains("chrome") {
            r#"
            tell application "Google Chrome"
                set tabList to {}
                set tabIndex to 1
                repeat with w in windows
                    repeat with t in tabs of w
                        set tabTitle to title of t
                        set tabUrl to URL of t
                        set end of tabList to {tabIndex, tabTitle, tabUrl}
                        set tabIndex to tabIndex + 1
                    end repeat
                end repeat
                return tabList
            end tell
            "#.to_string()
        } else {
            return Vec::new();
        };

        println!("[get_browser_tabs] Running AppleScript for {}", app_name);
        let output = Command::new("osascript")
            .arg("-e")
            .arg(&script)
            .output();

        match output {
            Ok(o) => {
                let stdout = String::from_utf8_lossy(&o.stdout);
                let stderr = String::from_utf8_lossy(&o.stderr);
                println!("[get_browser_tabs] stdout: {}", stdout);
                if !stderr.is_empty() {
                    println!("[get_browser_tabs] stderr: {}", stderr);
                }
                parse_browser_tabs(&stdout)
            }
            Err(e) => {
                eprintln!("[get_browser_tabs] Failed: {}", e);
                Vec::new()
            }
        }
    }

    /// ブラウザタブ一覧 - Windows版（未実装）
    #[cfg(target_os = "windows")]
    pub fn get_browser_tabs(_app_name: &str) -> Vec<BrowserTab> {
        Vec::new()
    }

    /// Messagesアプリのチャット一覧を取得 - macOS版
    #[cfg(target_os = "macos")]
    pub fn get_messages_chats() -> Vec<MessagesChat> {
        let script = r#"
            tell application "Messages"
                set chatList to {}
                set chatCount to count of chats
                if chatCount > 50 then set chatCount to 50
                repeat with i from 1 to chatCount
                    set c to chat i
                    try
                        set chatId to id of c
                        set chatService to service type of c as text
                        -- 参加者名を取得
                        set participantNames to ""
                        try
                            set participantList to participants of c
                            if (count of participantList) > 0 then
                                repeat with p in participantList
                                    if participantNames is not "" then
                                        set participantNames to participantNames & ", "
                                    end if
                                    try
                                        set participantNames to participantNames & (name of p)
                                    on error
                                        set participantNames to participantNames & (handle of p)
                                    end try
                                end repeat
                            end if
                        end try
                        if participantNames is "" then
                            -- IDから名前部分を抽出
                            set AppleScript's text item delimiters to ";"
                            set idParts to text items of chatId
                            if (count of idParts) >= 3 then
                                set participantNames to item 3 of idParts
                            else
                                set participantNames to chatId
                            end if
                            set AppleScript's text item delimiters to ""
                        end if
                        set end of chatList to chatId & ":::" & participantNames & ":::" & chatService
                    end try
                end repeat
                set AppleScript's text item delimiters to "|||"
                set chatListText to chatList as text
                set AppleScript's text item delimiters to ""
                return chatListText
            end tell
        "#;

        let output = Command::new("osascript")
            .arg("-e")
            .arg(script)
            .output();

        match output {
            Ok(o) => {
                let stdout = String::from_utf8_lossy(&o.stdout).trim().to_string();
                if stdout.is_empty() {
                    return Vec::new();
                }

                stdout
                    .split("|||")
                    .filter_map(|entry| {
                        let parts: Vec<&str> = entry.splitn(3, ":::").collect();
                        if parts.len() >= 3 {
                            Some(MessagesChat {
                                id: parts[0].to_string(),
                                name: parts[1].to_string(),
                                service: parts[2].to_string(),
                            })
                        } else {
                            None
                        }
                    })
                    .collect()
            }
            Err(e) => {
                eprintln!("Failed to get Messages chats: {}", e);
                Vec::new()
            }
        }
    }

    /// Messagesアプリのチャット一覧 - Windows版（未実装）
    #[cfg(target_os = "windows")]
    pub fn get_messages_chats() -> Vec<MessagesChat> {
        Vec::new()
    }

    /// Messagesチャットを開く - macOS版
    #[cfg(target_os = "macos")]
    pub fn open_messages_chat(chat_id: &str) -> bool {
        let escaped_id = chat_id.replace("\"", "\\\"");
        let script = format!(
            r#"
            tell application "Messages"
                activate
                try
                    set targetChat to chat id "{}"
                    -- チャットウィンドウを開く（直接的な方法がないのでURLスキームを使用）
                end try
            end tell
            "#,
            escaped_id
        );

        // Messagesをアクティベートしてからチャットを開く
        let _ = Command::new("osascript")
            .arg("-e")
            .arg(&script)
            .output();

        // Messagesアプリをフォーカス
        Self::focus_app("Messages");
        true
    }

    /// Messagesチャットを開く - Windows版（未実装）
    #[cfg(target_os = "windows")]
    pub fn open_messages_chat(_chat_id: &str) -> bool {
        false
    }

    /// Safariのタブをアクティブにする - macOS版
    #[cfg(target_os = "macos")]
    pub fn activate_safari_tab(tab_index: usize) -> bool {
        let script = format!(
            r#"
            tell application "Safari"
                activate
                set tabCount to 0
                repeat with w in windows
                    repeat with t in tabs of w
                        set tabCount to tabCount + 1
                        if tabCount = {} then
                            set current tab of w to t
                            set index of w to 1
                            return true
                        end if
                    end repeat
                end repeat
                return false
            end tell
            "#,
            tab_index
        );

        Command::new("osascript")
            .arg("-e")
            .arg(&script)
            .status()
            .map(|s| s.success())
            .unwrap_or(false)
    }

    /// Safariタブアクティベート - Windows版（未実装）
    #[cfg(target_os = "windows")]
    pub fn activate_safari_tab(_tab_index: usize) -> bool {
        false
    }

    /// Chromeのタブをアクティブにする - macOS版
    #[cfg(target_os = "macos")]
    pub fn activate_chrome_tab(tab_index: usize) -> bool {
        let script = format!(
            r#"
            tell application "Google Chrome"
                activate
                set globalTabCount to 0
                set winNum to 1
                repeat with w in windows
                    set localTabIdx to 1
                    repeat with t in tabs of w
                        set globalTabCount to globalTabCount + 1
                        if globalTabCount = {} then
                            set active tab index of window winNum to localTabIdx
                            set index of window winNum to 1
                            return true
                        end if
                        set localTabIdx to localTabIdx + 1
                    end repeat
                    set winNum to winNum + 1
                end repeat
                return false
            end tell
            "#,
            tab_index
        );

        Command::new("osascript")
            .arg("-e")
            .arg(&script)
            .status()
            .map(|s| s.success())
            .unwrap_or(false)
    }

    /// Chromeタブアクティベート - Windows版（未実装）
    #[cfg(target_os = "windows")]
    pub fn activate_chrome_tab(_tab_index: usize) -> bool {
        false
    }

    /// クリップボード経由でテキストを入力 - macOS版
    #[cfg(target_os = "macos")]
    pub fn type_text(text: &str) -> bool {
        let escaped = text
            .replace("\\", "\\\\")
            .replace("\"", "\\\"");

        // クリップボードに保存してCmd+Vでペースト
        let script = format!(
            r#"
            -- 新しいテキストをクリップボードに設定
            set the clipboard to "{}"

            -- 少し待機
            delay 0.1

            -- Cmd+V でペースト
            tell application "System Events"
                keystroke "v" using command down
            end tell

            -- ペースト完了を待つ
            delay 0.2
            "#,
            escaped
        );

        Command::new("osascript")
            .arg("-e")
            .arg(&script)
            .status()
            .map(|s| s.success())
            .unwrap_or(false)
    }

    /// クリップボード経由でテキストを入力 - Windows版
    #[cfg(target_os = "windows")]
    pub fn type_text(text: &str) -> bool {
        let script = format!(
            r#"
            Set-Clipboard -Value '{}'
            Add-Type -TypeDefinition @'
            using System;
            using System.Runtime.InteropServices;
            public class Keyboard {{
                [DllImport("user32.dll")]
                public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);
            }}
'@
            $VK_CONTROL = 0x11
            $VK_V = 0x56
            $KEYDOWN = 0x0000
            $KEYUP = 0x0002
            Start-Sleep -Milliseconds 100
            [Keyboard]::keybd_event($VK_CONTROL, 0, $KEYDOWN, [UIntPtr]::Zero)
            [Keyboard]::keybd_event($VK_V, 0, $KEYDOWN, [UIntPtr]::Zero)
            Start-Sleep -Milliseconds 50
            [Keyboard]::keybd_event($VK_V, 0, $KEYUP, [UIntPtr]::Zero)
            [Keyboard]::keybd_event($VK_CONTROL, 0, $KEYUP, [UIntPtr]::Zero)
            "#,
            text.replace("'", "''")
        );

        let mut cmd = Command::new("powershell");
        cmd.args(["-NoProfile", "-Command", &script]);
        cmd.creation_flags(CREATE_NO_WINDOW);
        cmd.status().map(|s| s.success()).unwrap_or(false)
    }

    /// テキストを入力してEnterキーを押す - macOS版
    #[cfg(target_os = "macos")]
    pub fn type_text_and_enter(text: &str) -> bool {
        let escaped = text
            .replace("\\", "\\\\")
            .replace("\"", "\\\"");

        // クリップボードに保存してCmd+Vでペースト、その後Enter
        let script = format!(
            r#"
            -- 新しいテキストをクリップボードに設定
            set the clipboard to "{}"

            -- 少し待機
            delay 0.1

            -- Cmd+V でペースト
            tell application "System Events"
                keystroke "v" using command down
            end tell

            -- ペースト完了を待ってからEnterを押す
            delay 0.2
            tell application "System Events"
                keystroke return
            end tell

            -- 完了を待つ
            delay 0.1
            "#,
            escaped
        );

        Command::new("osascript")
            .arg("-e")
            .arg(&script)
            .status()
            .map(|s| s.success())
            .unwrap_or(false)
    }

    /// テキストを入力してEnterキーを押す - Windows版
    #[cfg(target_os = "windows")]
    pub fn type_text_and_enter(text: &str) -> bool {
        let script = format!(
            r#"
            Set-Clipboard -Value '{}'
            Add-Type -TypeDefinition @'
            using System;
            using System.Runtime.InteropServices;
            public class Keyboard {{
                [DllImport("user32.dll")]
                public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);
            }}
'@
            $VK_CONTROL = 0x11
            $VK_V = 0x56
            $VK_RETURN = 0x0D
            $KEYDOWN = 0x0000
            $KEYUP = 0x0002
            Start-Sleep -Milliseconds 100
            # Ctrl+V
            [Keyboard]::keybd_event($VK_CONTROL, 0, $KEYDOWN, [UIntPtr]::Zero)
            [Keyboard]::keybd_event($VK_V, 0, $KEYDOWN, [UIntPtr]::Zero)
            Start-Sleep -Milliseconds 50
            [Keyboard]::keybd_event($VK_V, 0, $KEYUP, [UIntPtr]::Zero)
            [Keyboard]::keybd_event($VK_CONTROL, 0, $KEYUP, [UIntPtr]::Zero)
            Start-Sleep -Milliseconds 200
            # Enter
            [Keyboard]::keybd_event($VK_RETURN, 0, $KEYDOWN, [UIntPtr]::Zero)
            Start-Sleep -Milliseconds 50
            [Keyboard]::keybd_event($VK_RETURN, 0, $KEYUP, [UIntPtr]::Zero)
            "#,
            text.replace("'", "''")
        );

        let mut cmd = Command::new("powershell");
        cmd.args(["-NoProfile", "-Command", &script]);
        cmd.creation_flags(CREATE_NO_WINDOW);
        cmd.status().map(|s| s.success()).unwrap_or(false)
    }

    /// キーを押す - macOS版
    #[cfg(target_os = "macos")]
    pub fn press_key(key: &str) -> bool {
        // key codeを直接使う
        let script = match key.to_lowercase().as_str() {
            "enter" | "return" => r#"tell application "System Events" to keystroke return"#,
            "tab" => r#"tell application "System Events" to keystroke tab"#,
            "shift+tab" => r#"tell application "System Events" to keystroke tab using shift down"#,
            "escape" | "esc" => r#"tell application "System Events" to key code 53"#,
            "delete" | "backspace" => r#"tell application "System Events" to key code 51"#,
            "space" => r#"tell application "System Events" to keystroke space"#,
            // 矢印キー
            "up" => r#"tell application "System Events" to key code 126"#,
            "down" => r#"tell application "System Events" to key code 125"#,
            "left" => r#"tell application "System Events" to key code 123"#,
            "right" => r#"tell application "System Events" to key code 124"#,
            // コピー・ペースト
            "cmd+c" => r#"tell application "System Events" to keystroke "c" using command down"#,
            "cmd+v" => r#"tell application "System Events" to keystroke "v" using command down"#,
            "cmd+x" => r#"tell application "System Events" to keystroke "x" using command down"#,
            "cmd+a" => r#"tell application "System Events" to keystroke "a" using command down"#,
            "cmd+z" => r#"tell application "System Events" to keystroke "z" using command down"#,
            _ => return false,
        };

        Command::new("osascript")
            .arg("-e")
            .arg(script)
            .status()
            .map(|s| s.success())
            .unwrap_or(false)
    }

    /// キーを押す - Windows版
    #[cfg(target_os = "windows")]
    pub fn press_key(key: &str) -> bool {
        let vk_code = match key.to_lowercase().as_str() {
            "enter" | "return" => "0x0D",
            "tab" => "0x09",
            "escape" | "esc" => "0x1B",
            "delete" | "backspace" => "0x08",
            "space" => "0x20",
            "up" => "0x26",
            "down" => "0x28",
            "left" => "0x25",
            "right" => "0x27",
            _ => return false,
        };

        let script = format!(
            r#"
            Add-Type -TypeDefinition @'
            using System;
            using System.Runtime.InteropServices;
            public class Keyboard {{
                [DllImport("user32.dll")]
                public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);
            }}
'@
            $KEYDOWN = 0x0000
            $KEYUP = 0x0002
            [Keyboard]::keybd_event({}, 0, $KEYDOWN, [UIntPtr]::Zero)
            Start-Sleep -Milliseconds 50
            [Keyboard]::keybd_event({}, 0, $KEYUP, [UIntPtr]::Zero)
            "#,
            vk_code, vk_code
        );

        let mut cmd = Command::new("powershell");
        cmd.args(["-NoProfile", "-Command", &script]);
        cmd.creation_flags(CREATE_NO_WINDOW);
        cmd.status().map(|s| s.success()).unwrap_or(false)
    }

    /// Terminal.appのウィンドウ・タブ一覧を取得 - macOS版
    #[cfg(target_os = "macos")]
    pub fn get_terminal_tabs() -> Vec<TerminalTab> {
        let script = r#"
            tell application "Terminal"
                set tabList to {}
                set winIndex to 1
                repeat with w in windows
                    set tabIndex to 1
                    repeat with t in tabs of w
                        set tabTitle to custom title of t
                        if tabTitle = "" then
                            set tabTitle to "Tab " & tabIndex
                        end if
                        set isBusy to busy of t
                        set end of tabList to {winIndex, tabIndex, tabTitle, isBusy}
                        set tabIndex to tabIndex + 1
                    end repeat
                    set winIndex to winIndex + 1
                end repeat
                return tabList
            end tell
        "#;

        let output = Command::new("osascript")
            .arg("-e")
            .arg(script)
            .output();

        match output {
            Ok(o) => {
                let stdout = String::from_utf8_lossy(&o.stdout);
                parse_terminal_tabs(&stdout)
            }
            Err(e) => {
                eprintln!("Failed to get terminal tabs: {}", e);
                Vec::new()
            }
        }
    }

    /// Terminal.appタブ一覧 - Windows版（未実装）
    #[cfg(target_os = "windows")]
    pub fn get_terminal_tabs() -> Vec<TerminalTab> {
        Vec::new()
    }

    /// iTerm2のウィンドウ・タブ一覧を取得 - macOS版
    #[cfg(target_os = "macos")]
    pub fn get_iterm_tabs() -> Vec<TerminalTab> {
        let script = r#"
            tell application "iTerm2"
                set tabList to {}
                set winIndex to 1
                repeat with w in windows
                    set tabIndex to 1
                    repeat with t in tabs of w
                        set currentSession to current session of t
                        set tabTitle to name of currentSession
                        set isBusy to is processing of currentSession
                        set end of tabList to {winIndex, tabIndex, tabTitle, isBusy}
                        set tabIndex to tabIndex + 1
                    end repeat
                    set winIndex to winIndex + 1
                end repeat
                return tabList
            end tell
        "#;

        let output = Command::new("osascript")
            .arg("-e")
            .arg(script)
            .output();

        match output {
            Ok(o) => {
                let stdout = String::from_utf8_lossy(&o.stdout);
                parse_terminal_tabs(&stdout)
            }
            Err(e) => {
                eprintln!("Failed to get iTerm tabs: {}", e);
                Vec::new()
            }
        }
    }

    /// iTerm2タブ一覧 - Windows版（未実装）
    #[cfg(target_os = "windows")]
    pub fn get_iterm_tabs() -> Vec<TerminalTab> {
        Vec::new()
    }

    /// Terminal.appの特定のタブをアクティブにする - macOS版
    #[cfg(target_os = "macos")]
    pub fn activate_terminal_tab(window_index: usize, tab_index: usize) -> bool {
        let script = format!(
            r#"
            tell application "Terminal"
                activate
                set targetWindow to window {}
                set index of targetWindow to 1
                set selected tab of targetWindow to tab {} of targetWindow
            end tell
            "#,
            window_index, tab_index
        );

        Command::new("osascript")
            .arg("-e")
            .arg(&script)
            .status()
            .map(|s| s.success())
            .unwrap_or(false)
    }

    /// Terminal.appタブアクティベート - Windows版（未実装）
    #[cfg(target_os = "windows")]
    pub fn activate_terminal_tab(_window_index: usize, _tab_index: usize) -> bool {
        false
    }

    /// iTerm2の特定のタブをアクティブにする - macOS版
    #[cfg(target_os = "macos")]
    pub fn activate_iterm_tab(window_index: usize, tab_index: usize) -> bool {
        let script = format!(
            r#"
            tell application "iTerm2"
                activate
                set targetWindow to window {}
                select targetWindow
                tell targetWindow
                    select tab {}
                end tell
            end tell
            "#,
            window_index, tab_index
        );

        Command::new("osascript")
            .arg("-e")
            .arg(&script)
            .status()
            .map(|s| s.success())
            .unwrap_or(false)
    }

    /// iTerm2タブアクティベート - Windows版（未実装）
    #[cfg(target_os = "windows")]
    pub fn activate_iterm_tab(_window_index: usize, _tab_index: usize) -> bool {
        false
    }

    /// 最前面のウィンドウ情報を取得 - macOS版
    #[cfg(target_os = "macos")]
    pub fn get_frontmost_window() -> Option<AppWindowInfo> {
        // タイムアウト付きでウィンドウ情報を取得
        let script = r#"
            with timeout of 3 seconds
                tell application "System Events"
                    set frontApp to first application process whose frontmost is true
                    set appName to name of frontApp

                    try
                        set frontWindow to first window of frontApp
                        set winName to name of frontWindow
                        set winPos to position of frontWindow
                        set winSize to size of frontWindow

                        return appName & "|" & winName & "|" & (item 1 of winPos) & "|" & (item 2 of winPos) & "|" & (item 1 of winSize) & "|" & (item 2 of winSize)
                    on error
                        return appName & "|" & "No Window" & "|0|0|0|0"
                    end try
                end tell
            end timeout
        "#;

        let output = Command::new("osascript")
            .arg("-e")
            .arg(script)
            .output();

        match output {
            Ok(o) => {
                let stdout = String::from_utf8_lossy(&o.stdout);
                let parts: Vec<&str> = stdout.trim().split('|').collect();

                if parts.len() >= 6 {
                    Some(AppWindowInfo {
                        app_name: parts[0].to_string(),
                        window_title: parts[1].to_string(),
                        x: parts[2].parse().unwrap_or(0),
                        y: parts[3].parse().unwrap_or(0),
                        width: parts[4].parse().unwrap_or(0),
                        height: parts[5].parse().unwrap_or(0),
                    })
                } else {
                    None
                }
            }
            Err(e) => {
                eprintln!("Failed to get frontmost window: {}", e);
                None
            }
        }
    }

    /// 最前面のウィンドウ情報を取得 - Windows版
    #[cfg(target_os = "windows")]
    pub fn get_frontmost_window() -> Option<AppWindowInfo> {
        let script = r#"
            Add-Type -TypeDefinition @'
            using System;
            using System.Runtime.InteropServices;
            using System.Text;
            public class Win32 {
                [DllImport("user32.dll")]
                public static extern IntPtr GetForegroundWindow();
                [DllImport("user32.dll")]
                public static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int count);
                [DllImport("user32.dll")]
                public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);
                [DllImport("user32.dll")]
                public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);
                [StructLayout(LayoutKind.Sequential)]
                public struct RECT {
                    public int Left, Top, Right, Bottom;
                }
            }
'@
            $hwnd = [Win32]::GetForegroundWindow()
            $sb = New-Object System.Text.StringBuilder 256
            [Win32]::GetWindowText($hwnd, $sb, 256) | Out-Null
            $title = $sb.ToString()
            $processId = 0
            [Win32]::GetWindowThreadProcessId($hwnd, [ref]$processId) | Out-Null
            $proc = Get-Process -Id $processId -ErrorAction SilentlyContinue
            $appName = if ($proc) { $proc.ProcessName } else { "Unknown" }
            $rect = New-Object Win32+RECT
            [Win32]::GetWindowRect($hwnd, [ref]$rect) | Out-Null
            $x = $rect.Left
            $y = $rect.Top
            $width = $rect.Right - $rect.Left
            $height = $rect.Bottom - $rect.Top
            "$appName|$title|$x|$y|$width|$height"
        "#;

        let mut cmd = Command::new("powershell");
        cmd.args(["-NoProfile", "-Command", script]);
        cmd.creation_flags(CREATE_NO_WINDOW);

        match cmd.output() {
            Ok(o) => {
                let stdout = String::from_utf8_lossy(&o.stdout);
                let parts: Vec<&str> = stdout.trim().split('|').collect();

                if parts.len() >= 6 {
                    Some(AppWindowInfo {
                        app_name: parts[0].to_string(),
                        window_title: parts[1].to_string(),
                        x: parts[2].parse().unwrap_or(0),
                        y: parts[3].parse().unwrap_or(0),
                        width: parts[4].parse().unwrap_or(0),
                        height: parts[5].parse().unwrap_or(0),
                    })
                } else {
                    None
                }
            }
            Err(e) => {
                eprintln!("Failed to get frontmost window: {}", e);
                None
            }
        }
    }

    /// 指定アプリのウィンドウを最前面に持ってきてサイズを取得（最大化しない）
    pub fn focus_and_get_window(app_name: &str) -> Option<AppWindowInfo> {
        // まずアプリをフォーカス（アクティブ化）
        println!("[SystemControl] focus_and_get_window: Focusing app '{}'", app_name);
        Self::focus_app(app_name);

        // アプリがアクティブになるのを待つ
        std::thread::sleep(std::time::Duration::from_millis(300));

        // ウィンドウを左上に移動（座標計算を簡単にするため）
        Self::move_window_to_top_left(None, None);

        // 移動後に少し待機してからウィンドウ情報を取得
        std::thread::sleep(std::time::Duration::from_millis(100));

        let window_info = Self::get_frontmost_window();

        // ウィンドウの中央をクリックしてカーソルをアクティブ化
        // ただし、指定したアプリのウィンドウである場合のみ
        if let Some(ref info) = window_info {
            // アプリ名が一致するか確認（大文字小文字を無視して部分一致）
            let info_app_lower = info.app_name.to_lowercase();
            let target_app_lower = app_name.to_lowercase();

            if info_app_lower.contains(&target_app_lower) || target_app_lower.contains(&info_app_lower) {
                let center_x = info.x + (info.width / 2);
                let center_y = info.y + (info.height / 2);
                println!("[SystemControl] App matched: '{}' == '{}'. Window at ({}, {}), clicking center ({}, {})",
                    info.app_name, app_name, info.x, info.y, center_x, center_y);
                Self::click_at(center_x as f64, center_y as f64);
            } else {
                println!("[SystemControl] App mismatch: frontmost='{}', target='{}'. Skipping click.",
                    info.app_name, app_name);
            }
        }

        window_info
    }

    /// 指定座標をクリック（CoreGraphics使用）
    #[cfg(target_os = "macos")]
    pub fn click_at(x: f64, y: f64) {
        use core_graphics::event::{CGEvent, CGEventTapLocation, CGEventType, CGMouseButton};
        use core_graphics::event_source::{CGEventSource, CGEventSourceStateID};
        use core_graphics::geometry::CGPoint;

        let point = CGPoint::new(x, y);

        // マウスダウン
        if let Ok(source) = CGEventSource::new(CGEventSourceStateID::HIDSystemState) {
            if let Ok(event) = CGEvent::new_mouse_event(
                source.clone(),
                CGEventType::LeftMouseDown,
                point,
                CGMouseButton::Left,
            ) {
                event.post(CGEventTapLocation::HID);
            }
        }

        // 少し待機
        std::thread::sleep(std::time::Duration::from_millis(50));

        // マウスアップ
        if let Ok(source) = CGEventSource::new(CGEventSourceStateID::HIDSystemState) {
            if let Ok(event) = CGEvent::new_mouse_event(
                source.clone(),
                CGEventType::LeftMouseUp,
                point,
                CGMouseButton::Left,
            ) {
                event.post(CGEventTapLocation::HID);
            }
        }

        println!("[SystemControl] Clicked at ({}, {})", x, y);
    }

    #[cfg(not(target_os = "macos"))]
    pub fn click_at(_x: f64, _y: f64) {
        // Windows/Linux版は未実装
    }

    /// フォーカス中のウィンドウを左上(0,0)に移動し、指定サイズに変更 - macOS版
    #[cfg(target_os = "macos")]
    pub fn move_window_to_top_left(width: Option<i32>, height: Option<i32>) -> bool {
        // ウィンドウを(0, 25)に移動（25はメニューバーの高さ）
        // サイズが指定されていれば変更
        let size_script = if let (Some(w), Some(h)) = (width, height) {
            format!(
                r#"
                    set size of frontWindow to {{{}, {}}}
                "#,
                w, h
            )
        } else {
            String::new()
        };

        let script = format!(
            r#"
            tell application "System Events"
                set frontApp to first application process whose frontmost is true
                try
                    set frontWindow to first window of frontApp
                    set position of frontWindow to {{0, 25}}
                    {}
                    return "success"
                on error errMsg
                    return "error: " & errMsg
                end try
            end tell
            "#,
            size_script
        );

        match Command::new("osascript")
            .args(["-e", &script])
            .output()
        {
            Ok(output) => {
                let stdout = String::from_utf8_lossy(&output.stdout);
                let success = stdout.trim().starts_with("success");
                println!("[SystemControl] move_window_to_top_left: {}", stdout.trim());
                success
            }
            Err(e) => {
                println!("[SystemControl] move_window_to_top_left error: {}", e);
                false
            }
        }
    }

    #[cfg(not(target_os = "macos"))]
    pub fn move_window_to_top_left(_width: Option<i32>, _height: Option<i32>) -> bool {
        // Windows/Linux版は未実装
        false
    }

    /// ウィンドウを最大化（フルスクリーンではなく画面いっぱいに）- macOS版
    #[cfg(target_os = "macos")]
    pub fn maximize_window() -> bool {
        // メニューバーの高さは25px、Dockの高さを考慮して動的に計算
        let script = r#"
            tell application "Finder"
                set screenBounds to bounds of window of desktop
                set screenWidth to item 3 of screenBounds
                set screenHeight to item 4 of screenBounds
            end tell

            tell application "System Events"
                set frontApp to first application process whose frontmost is true
                try
                    set frontWindow to first window of frontApp
                    tell frontWindow
                        -- メニューバーの下から開始、画面いっぱいに
                        set position to {0, 25}
                        set size to {screenWidth, screenHeight - 25}
                    end tell
                    return true
                on error errMsg
                    return false
                end try
            end tell
        "#;

        Command::new("osascript")
            .arg("-e")
            .arg(script)
            .status()
            .map(|s| s.success())
            .unwrap_or(false)
    }

    /// ウィンドウを指定サイズにリサイズ - macOS版
    #[cfg(target_os = "macos")]
    pub fn resize_window(width: i32, height: i32) -> bool {
        let script = format!(r#"
            tell application "System Events"
                set frontApp to first application process whose frontmost is true
                try
                    set frontWindow to first window of frontApp
                    tell frontWindow
                        -- 左上に配置してリサイズ
                        set position to {{0, 25}}
                        set size to {{{}, {}}}
                    end tell
                    return true
                on error errMsg
                    return false
                end try
            end tell
        "#, width, height);

        Command::new("osascript")
            .arg("-e")
            .arg(&script)
            .status()
            .map(|s| s.success())
            .unwrap_or(false)
    }

    /// ウィンドウを最大化 - Windows版
    #[cfg(target_os = "windows")]
    pub fn maximize_window() -> bool {
        let script = r#"
            Add-Type -TypeDefinition @'
            using System;
            using System.Runtime.InteropServices;
            public class Win32 {
                [DllImport("user32.dll")]
                public static extern IntPtr GetForegroundWindow();
                [DllImport("user32.dll")]
                public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
            }
'@
            $hwnd = [Win32]::GetForegroundWindow()
            [Win32]::ShowWindow($hwnd, 3)  # SW_MAXIMIZE = 3
        "#;

        let mut cmd = Command::new("powershell");
        cmd.args(["-NoProfile", "-Command", script]);
        cmd.creation_flags(CREATE_NO_WINDOW);
        cmd.status().map(|s| s.success()).unwrap_or(false)
    }

    /// ウィンドウを指定サイズにリサイズ - Windows版
    #[cfg(target_os = "windows")]
    pub fn resize_window(width: i32, height: i32) -> bool {
        let script = format!(r#"
            Add-Type -TypeDefinition @'
            using System;
            using System.Runtime.InteropServices;
            public class Win32 {{
                [DllImport("user32.dll")]
                public static extern IntPtr GetForegroundWindow();
                [DllImport("user32.dll")]
                public static extern bool MoveWindow(IntPtr hWnd, int X, int Y, int nWidth, int nHeight, bool bRepaint);
            }}
'@
            $hwnd = [Win32]::GetForegroundWindow()
            [Win32]::MoveWindow($hwnd, 0, 0, {}, {}, $true)
        "#, width, height);

        let mut cmd = Command::new("powershell");
        cmd.args(["-NoProfile", "-Command", &script]);
        cmd.creation_flags(CREATE_NO_WINDOW);
        cmd.status().map(|s| s.success()).unwrap_or(false)
    }
}

/// AppleScriptの出力をパースしてBrowserTabのリストに変換
fn parse_browser_tabs(output: &str) -> Vec<BrowserTab> {
    let mut tabs = Vec::new();
    let trimmed = output.trim();
    println!("[parse_browser_tabs] Input: {:?}", trimmed);

    // 簡易パース: index, title, url の組み合わせを探す
    let parts: Vec<&str> = trimmed.split(", ").collect();
    println!("[parse_browser_tabs] Parts count: {}", parts.len());

    let mut i = 0;
    while i + 2 < parts.len() {
        let index_str = parts[i].trim().trim_matches(|c| c == '{' || c == '}');
        let title = parts[i + 1].trim().trim_matches(|c| c == '{' || c == '}');
        let url = parts[i + 2].trim().trim_matches(|c| c == '{' || c == '}');

        if let Ok(index) = index_str.parse::<usize>() {
            tabs.push(BrowserTab {
                index,
                title: title.to_string(),
                url: url.to_string(),
            });
        }
        i += 3;
    }

    println!("[parse_browser_tabs] Parsed {} tabs", tabs.len());
    tabs
}

/// AppleScriptの出力をパースしてRunningAppのリストに変換
fn parse_running_apps(output: &str) -> Vec<RunningApp> {
    let mut apps = Vec::new();

    // AppleScriptの出力形式: {{name, bundleId, isFront}, {name, bundleId, isFront}, ...}
    let trimmed = output.trim();

    // シンプルな分割パース
    // 出力例: "Finder, com.apple.finder, false, Chrome, com.google.Chrome, true, ..."
    let parts: Vec<&str> = trimmed.split(", ").collect();

    let mut i = 0;
    while i + 2 < parts.len() {
        let name = parts[i].trim().trim_matches(|c| c == '{' || c == '}');
        let bundle_id = parts[i + 1].trim();
        let is_active = parts[i + 2].trim().trim_matches('}') == "true";

        if !name.is_empty() {
            apps.push(RunningApp {
                name: name.to_string(),
                bundle_id: if bundle_id == "missing value" {
                    None
                } else {
                    Some(bundle_id.to_string())
                },
                is_active,
            });
        }
        i += 3;
    }

    apps
}

/// AppleScriptの出力をパースしてTerminalTabのリストに変換
fn parse_terminal_tabs(output: &str) -> Vec<TerminalTab> {
    let mut tabs = Vec::new();
    let trimmed = output.trim();

    // 出力例: "1, 1, bash, false, 1, 2, npm run dev, true, ..."
    let parts: Vec<&str> = trimmed.split(", ").collect();

    let mut i = 0;
    while i + 3 < parts.len() {
        let win_str = parts[i].trim().trim_matches(|c| c == '{' || c == '}');
        let tab_str = parts[i + 1].trim();
        let title = parts[i + 2].trim();
        let is_busy = parts[i + 3].trim().trim_matches('}') == "true";

        if let (Ok(window_index), Ok(tab_index)) = (win_str.parse::<usize>(), tab_str.parse::<usize>()) {
            tabs.push(TerminalTab {
                window_index,
                tab_index,
                title: title.to_string(),
                is_busy,
            });
        }
        i += 4;
    }

    tabs
}
