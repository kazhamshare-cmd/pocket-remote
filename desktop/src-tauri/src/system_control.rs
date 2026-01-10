use serde::{Deserialize, Serialize};
use std::process::Command;
use std::sync::Mutex;
use std::time::{Duration, Instant};
use std::collections::HashMap;

#[cfg(target_os = "windows")]
use std::os::windows::process::CommandExt;

#[cfg(target_os = "windows")]
const CREATE_NO_WINDOW: u32 = 0x08000000;

// ブラウザタブのキャッシュ（2秒間有効）
lazy_static::lazy_static! {
    static ref BROWSER_TABS_CACHE: Mutex<HashMap<String, (Vec<BrowserTab>, Instant)>> = Mutex::new(HashMap::new());
}
const BROWSER_TABS_CACHE_DURATION: Duration = Duration::from_secs(2);

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RunningApp {
    pub name: String,
    pub bundle_id: Option<String>,
    pub is_active: bool,
    pub is_cli: bool, // ターミナルで実行中のCLIツールかどうか
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
                            is_cli: false, // GUIアプリ
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

    /// ターミナルで実行中のCLIツールを取得（macOS版）
    /// running_apps: 既に取得済みの起動中アプリリスト（ターミナルが起動しているかの確認用）
    #[cfg(target_os = "macos")]
    pub fn get_cli_tools_fast(running_apps: &[RunningApp]) -> Vec<RunningApp> {
        let mut cli_tools = Vec::new();

        // 起動中のターミナルアプリを確認
        let has_terminal = running_apps.iter().any(|a| a.name == "Terminal");
        let has_iterm = running_apps.iter().any(|a| a.name.contains("iTerm"));
        let has_warp = running_apps.iter().any(|a| a.name == "Warp");

        // どのターミナルも起動していなければ早期リターン
        if !has_terminal && !has_iterm && !has_warp {
            return cli_tools;
        }

        // 既知のCLIツール名（ターミナルタイトルの先頭単語と完全一致するもののみ）
        // より限定的に: AI CLIツールのみ
        let known_cli_tools = [
            "gemini", "claude", "aider", "ollama", "sgpt",
        ];

        // タブタイトルがCLIツールかどうかを判定（先頭単語で判定）
        let is_cli_tool_tab = |title: &str| -> Option<&str> {
            let first_word = title.split_whitespace().next()?.to_lowercase();
            known_cli_tools.iter().find(|&&tool| first_word == tool).copied()
        };

        // Terminal.appからCLIツールを検出（起動中の場合のみ）
        if has_terminal {
            for tab in Self::get_terminal_tabs() {
                if let Some(tool) = is_cli_tool_tab(&tab.title) {
                    let display_name = format!("{} (Terminal)", tool);
                    if !cli_tools.iter().any(|t: &RunningApp| t.name == display_name) {
                        cli_tools.push(RunningApp {
                            name: display_name,
                            bundle_id: Some("com.apple.Terminal".to_string()),
                            is_active: false,
                            is_cli: true,
                        });
                    }
                }
            }
        }

        // iTerm2からCLIツールを検出（起動中の場合のみ）
        if has_iterm {
            for tab in Self::get_iterm_tabs() {
                if let Some(tool) = is_cli_tool_tab(&tab.title) {
                    let display_name = format!("{} (iTerm)", tool);
                    if !cli_tools.iter().any(|t: &RunningApp| t.name == display_name) {
                        cli_tools.push(RunningApp {
                            name: display_name,
                            bundle_id: Some("com.googlecode.iterm2".to_string()),
                            is_active: false,
                            is_cli: true,
                        });
                    }
                }
            }
        }

        // WarpからCLIツールを検出（起動中の場合のみ）
        if has_warp {
            for tab in Self::get_warp_tabs() {
                if let Some(tool) = is_cli_tool_tab(&tab.title) {
                    let display_name = format!("{} (Warp)", tool);
                    if !cli_tools.iter().any(|t: &RunningApp| t.name == display_name) {
                        cli_tools.push(RunningApp {
                            name: display_name,
                            bundle_id: Some("dev.warp.Warp-Stable".to_string()),
                            is_active: false,
                            is_cli: true,
                        });
                    }
                }
            }
        }

        cli_tools
    }

    /// ターミナルで実行中のCLIツールを取得（Windows版）- 高速版
    /// Windows版は現在空のリストを返す
    #[cfg(target_os = "windows")]
    pub fn get_cli_tools_fast(_running_apps: &[RunningApp]) -> Vec<RunningApp> {
        Vec::new() // Windows版は未実装
    }

    /// ターミナルで実行中のCLIツールを取得（macOS版）- 互換用
    #[cfg(target_os = "macos")]
    pub fn get_cli_tools() -> Vec<RunningApp> {
        // 起動中アプリを取得してから呼び出し
        let apps = Self::get_running_apps();
        Self::get_cli_tools_fast(&apps)
    }

    /// ターミナルで実行中のCLIツールを取得（Windows版）
    #[cfg(target_os = "windows")]
    pub fn get_cli_tools() -> Vec<RunningApp> {
        Vec::new() // Windows版は未実装
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
                                is_cli: false, // GUIアプリ
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
        // 一般的なアプリ名のマッピング（プロセス名とアプリ名が異なる場合）
        let normalized_name = match app_name.to_lowercase().as_str() {
            "chrome" => "Google Chrome",
            "safari" => "Safari",
            "firefox" => "Firefox",
            "edge" => "Microsoft Edge",
            "vscode" | "code" => "Visual Studio Code",
            "terminal" => "Terminal",
            "finder" => "Finder",
            "slack" => "Slack",
            "discord" => "Discord",
            "zoom" => "zoom.us",
            _ => app_name,
        };
        println!("[focus_app] Normalizing '{}' → '{}'", app_name, normalized_name);

        // まずbundle identifierを取得してからアクティベート
        // プロセス名とアプリ名が異なる場合（例: AdobeAcrobat → Adobe Acrobat DC）に対応
        let script = format!(
            r#"
            with timeout of 5 seconds
                tell application "System Events"
                    try
                        set targetProcess to first process whose name is "{}"
                        set bundleId to bundle identifier of targetProcess
                        tell application id bundleId to activate
                        return "success"
                    on error
                        -- フォールバック: 直接アプリ名でアクティベート
                        try
                            tell application "{}" to activate
                            return "success"
                        on error errMsg
                            return "error: " & errMsg
                        end try
                    end try
                end tell
            end timeout
            "#,
            normalized_name.replace("\"", "\\\""),
            normalized_name.replace("\"", "\\\"")
        );

        let output = Command::new("osascript")
            .arg("-e")
            .arg(&script)
            .output();

        match output {
            Ok(o) => {
                let stdout = String::from_utf8_lossy(&o.stdout);
                let stderr = String::from_utf8_lossy(&o.stderr);
                if !stderr.is_empty() {
                    eprintln!("[focus_app] stderr: {}", stderr);
                }
                stdout.trim().starts_with("success")
            }
            Err(e) => {
                eprintln!("[focus_app] Failed: {}", e);
                false
            }
        }
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
    /// ウィンドウがない場合はアプリをアクティベートして新しいウィンドウを開く
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

        let mut windows: Vec<WindowListItem> = match output {
            Ok(o) => {
                let stdout = String::from_utf8_lossy(&o.stdout).trim().to_string();
                if stdout.is_empty() {
                    Vec::new()
                } else {
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
            }
            Err(e) => {
                eprintln!("Failed to get windows for {}: {}", app_name, e);
                Vec::new()
            }
        };

        // ウィンドウがない場合、アプリをアクティベートして新しいウィンドウを開く
        if windows.is_empty() {
            println!("[get_app_windows] No windows found for '{}', attempting to activate app", app_name);

            // アプリをアクティベート
            Self::focus_app(app_name);
            std::thread::sleep(std::time::Duration::from_millis(500));

            // 再度ウィンドウを取得
            let retry_output = Command::new("osascript")
                .arg("-e")
                .arg(&format!(
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
                ))
                .output();

            if let Ok(o) = retry_output {
                let stdout = String::from_utf8_lossy(&o.stdout).trim().to_string();
                if !stdout.is_empty() {
                    windows = stdout
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
                        .collect();
                }
            }

            // それでもウィンドウがない場合、デフォルトエントリを追加
            if windows.is_empty() {
                println!("[get_app_windows] Still no windows after activation, adding default entry");
                windows.push(WindowListItem {
                    index: 1,
                    title: format!("{} (アプリを開く)", app_name),
                    is_minimized: false,
                });
            }
        }

        windows
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

        // まずbundle identifier経由でアプリをアクティベートしてから、
        // 特定のウィンドウを最前面に。最小化されている場合は解除する
        let script = format!(
            r#"
            -- まずアプリをアクティベート（bundle identifier経由）
            tell application "System Events"
                try
                    set targetProcess to first process whose name is "{}"
                    set bundleId to bundle identifier of targetProcess
                    tell application id bundleId to activate
                on error
                    -- フォールバック
                    try
                        tell application "{}" to activate
                    end try
                end try
            end tell
            delay 0.1

            -- 次に特定のウィンドウを最前面に
            tell application "System Events"
                tell process "{}"
                    try
                        -- 指定ウィンドウを取得
                        set targetWindow to window {}

                        -- 最小化されている場合は解除
                        set isMinimized to value of attribute "AXMinimized" of targetWindow
                        if isMinimized then
                            set value of attribute "AXMinimized" of targetWindow to false
                            delay 0.2
                        end if

                        -- ウィンドウを最前面に上げる
                        perform action "AXRaise" of targetWindow
                    end try
                end tell
            end tell
            "#,
            escaped_name, escaped_name, escaped_name, window_index
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
        // キャッシュをチェック
        let cache_key = app_name.to_lowercase();
        {
            let cache = BROWSER_TABS_CACHE.lock().unwrap();
            if let Some((tabs, timestamp)) = cache.get(&cache_key) {
                if timestamp.elapsed() < BROWSER_TABS_CACHE_DURATION {
                    println!("[get_browser_tabs] Using cached tabs for {} ({} tabs)", app_name, tabs.len());
                    return tabs.clone();
                }
            }
        }

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
                let tabs = parse_browser_tabs(&stdout);

                // キャッシュを更新
                {
                    let mut cache = BROWSER_TABS_CACHE.lock().unwrap();
                    cache.insert(cache_key, (tabs.clone(), Instant::now()));
                }

                tabs
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

    /// Chromeのタブをアクティブにする - macOS版（最適化版）
    #[cfg(target_os = "macos")]
    pub fn activate_chrome_tab(tab_index: usize) -> bool {
        // 高速版：ウィンドウごとのタブ数を先に取得してから直接アクセス
        let script = format!(
            r#"
            tell application "Google Chrome"
                activate
                set targetIdx to {}
                set currentCount to 0
                repeat with winIdx from 1 to count of windows
                    set w to window winIdx
                    set tabCount to count of tabs of w
                    if currentCount + tabCount >= targetIdx then
                        set localIdx to targetIdx - currentCount
                        set active tab index of w to localIdx
                        set index of w to 1
                        return true
                    end if
                    set currentCount to currentCount + tabCount
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
            // Control キー組み合わせ（ターミナル用）
            "ctrl+c" => r#"tell application "System Events" to keystroke "c" using control down"#,
            "ctrl+d" => r#"tell application "System Events" to keystroke "d" using control down"#,
            "ctrl+z" => r#"tell application "System Events" to keystroke "z" using control down"#,
            "ctrl+a" => r#"tell application "System Events" to keystroke "a" using control down"#,
            "ctrl+e" => r#"tell application "System Events" to keystroke "e" using control down"#,
            "ctrl+l" => r#"tell application "System Events" to keystroke "l" using control down"#,
            "ctrl+r" => r#"tell application "System Events" to keystroke "r" using control down"#,
            "ctrl+u" => r#"tell application "System Events" to keystroke "u" using control down"#,
            "ctrl+k" => r#"tell application "System Events" to keystroke "k" using control down"#,
            // Command キー組み合わせ（コピー・ペースト）
            "cmd+c" => r#"tell application "System Events" to keystroke "c" using command down"#,
            "cmd+v" => r#"tell application "System Events" to keystroke "v" using command down"#,
            "cmd+x" => r#"tell application "System Events" to keystroke "x" using command down"#,
            "cmd+a" => r#"tell application "System Events" to keystroke "a" using command down"#,
            "cmd+z" => r#"tell application "System Events" to keystroke "z" using command down"#,
            "cmd+s" => r#"tell application "System Events" to keystroke "s" using command down"#,
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

    /// Warp Terminalのタブ一覧を取得 - macOS版
    #[cfg(target_os = "macos")]
    pub fn get_warp_tabs() -> Vec<TerminalTab> {
        // WarpはモダンなターミナルでAppleScriptサポートが限定的
        // ウィンドウタイトルから情報を取得
        let script = r#"
            tell application "System Events"
                try
                    if (exists process "Warp") then
                        tell process "Warp"
                            set tabList to {}
                            set winIndex to 1
                            repeat with w in windows
                                set winTitle to name of w
                                set end of tabList to {winIndex, 1, winTitle, false}
                                set winIndex to winIndex + 1
                            end repeat
                            return tabList
                        end tell
                    else
                        return {}
                    end if
                on error
                    return {}
                end try
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
                eprintln!("Failed to get Warp tabs: {}", e);
                Vec::new()
            }
        }
    }

    /// Warp Terminalタブ一覧 - Windows版（未実装）
    #[cfg(target_os = "windows")]
    pub fn get_warp_tabs() -> Vec<TerminalTab> {
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

    /// Terminal.appの現在のタブのコンテンツを取得（スクロールバック含む） - macOS版
    #[cfg(target_os = "macos")]
    pub fn get_terminal_content() -> String {
        // history属性でスクロールバックを含むすべての内容を取得
        let script = r#"
            tell application "Terminal"
                try
                    set frontWindow to front window
                    set currentTab to selected tab of frontWindow
                    -- historyでスクロールバック含む全内容を取得
                    set termHistory to history of currentTab
                    -- 長すぎる場合は末尾50000文字を返す
                    if (length of termHistory) > 50000 then
                        set termHistory to text ((length of termHistory) - 50000) thru -1 of termHistory
                    end if
                    return termHistory
                on error errMsg
                    return "Error: " & errMsg
                end try
            end tell
        "#;

        let output = Command::new("osascript")
            .arg("-e")
            .arg(script)
            .output();

        match output {
            Ok(o) => {
                let content = String::from_utf8_lossy(&o.stdout).to_string();
                println!("[get_terminal_content] Terminal.app content length: {} chars", content.len());
                content
            }
            Err(e) => {
                eprintln!("[get_terminal_content] Failed to get Terminal content: {}", e);
                String::new()
            }
        }
    }

    /// Terminal.appコンテンツ取得 - Windows版（未実装）
    #[cfg(target_os = "windows")]
    pub fn get_terminal_content() -> String {
        String::new()
    }

    /// iTerm2の現在のセッションのコンテンツを取得（スクロールバック含む） - macOS版
    #[cfg(target_os = "macos")]
    pub fn get_iterm_content() -> String {
        // iTerm2はcontentsでスクロールバック含むテキストを取得できる
        let script = r#"
            tell application "iTerm2"
                try
                    set currentWindow to current window
                    set currentSession to current session of current tab of currentWindow
                    -- contentsはスクロールバックを含む全テキストを返す
                    set sessionContents to contents of currentSession
                    return sessionContents
                on error errMsg
                    return ""
                end try
            end tell
        "#;

        let output = Command::new("osascript")
            .arg("-e")
            .arg(script)
            .output();

        match output {
            Ok(o) => {
                let content = String::from_utf8_lossy(&o.stdout).to_string();
                println!("[get_iterm_content] iTerm2 content length: {} chars", content.len());
                content
            }
            Err(e) => {
                eprintln!("[get_iterm_content] Failed to get iTerm2 content: {}", e);
                String::new()
            }
        }
    }

    /// iTerm2コンテンツ取得 - Windows版（未実装）
    #[cfg(target_os = "windows")]
    pub fn get_iterm_content() -> String {
        String::new()
    }

    /// 汎用ターミナルコンテンツ取得（アプリ名から自動判定）
    pub fn get_terminal_content_for_app(app_name: &str) -> String {
        let app_lower = app_name.to_lowercase();

        // Terminal.app
        if app_lower.contains("terminal") && !app_lower.contains("warp") {
            println!("[get_terminal_content_for_app] Using Terminal.app method");
            return Self::get_terminal_content();
        }

        // iTerm2
        if app_lower.contains("iterm") {
            println!("[get_terminal_content_for_app] Using iTerm2 method");
            return Self::get_iterm_content();
        }

        // Warp Terminal
        if app_lower.contains("warp") {
            println!("[get_terminal_content_for_app] Using Warp method");
            return Self::get_warp_content();
        }

        // Cursor / VSCode / Electron系（統合ターミナル）
        if app_lower.contains("cursor") || app_lower.contains("code") ||
           app_lower.contains("vscode") || app_lower.contains("electron") {
            println!("[get_terminal_content_for_app] Using Cursor/VSCode method");
            return Self::get_vscode_terminal_content(app_name);
        }

        // その他のアプリ（アクセシビリティAPIを試す）
        println!("[get_terminal_content_for_app] Using generic accessibility method for: {}", app_name);
        Self::get_app_text_content(app_name)
    }

    /// Warp Terminalのコンテンツを取得 - macOS版
    #[cfg(target_os = "macos")]
    pub fn get_warp_content() -> String {
        // Warpはモダンなターミナルでアクセシビリティ対応
        let script = r#"
            tell application "System Events"
                tell process "Warp"
                    try
                        set allText to ""
                        -- Warpのテキストコンテンツを取得
                        set textElements to every text area of every scroll area of every window
                        repeat with elem in textElements
                            try
                                set elemValue to value of item 1 of elem
                                if elemValue is not missing value then
                                    set allText to allText & elemValue & return
                                end if
                            end try
                        end repeat
                        -- 別のアプローチ: AXValue を直接取得
                        if allText = "" then
                            set allGroups to every group of window 1
                            repeat with grp in allGroups
                                try
                                    set grpText to value of grp
                                    if grpText is not missing value then
                                        set allText to allText & grpText
                                    end if
                                end try
                            end repeat
                        end if
                        return allText
                    on error errMsg
                        return ""
                    end try
                end tell
            end tell
        "#;

        let output = Command::new("osascript")
            .arg("-e")
            .arg(script)
            .output();

        match output {
            Ok(o) => {
                let content = String::from_utf8_lossy(&o.stdout).to_string();
                println!("[get_warp_content] Warp content length: {} chars", content.len());
                content
            }
            Err(e) => {
                eprintln!("[get_warp_content] Failed to get Warp content: {}", e);
                String::new()
            }
        }
    }

    #[cfg(target_os = "windows")]
    pub fn get_warp_content() -> String {
        String::new()
    }

    /// VSCode/Cursor の統合ターミナルコンテンツを取得 - macOS版
    #[cfg(target_os = "macos")]
    pub fn get_vscode_terminal_content(app_name: &str) -> String {
        let process_name = if app_name.to_lowercase().contains("cursor") {
            "Cursor"
        } else {
            "Code"
        };

        // VSCode/Cursorの統合ターミナルはxterm.jsベース
        // アクセシビリティでテキストコンテンツを取得
        let script = format!(r#"
            tell application "System Events"
                tell process "{}"
                    try
                        set allText to ""
                        -- ウィンドウ内のすべてのテキストエリアを探索
                        set allWindows to every window
                        repeat with win in allWindows
                            -- スクロールエリア内のテキストエリア
                            try
                                set scrollAreas to every scroll area of win
                                repeat with sa in scrollAreas
                                    try
                                        set textAreas to every text area of sa
                                        repeat with ta in textAreas
                                            try
                                                set taValue to value of ta
                                                if taValue is not missing value and taValue is not "" then
                                                    set allText to allText & taValue & return
                                                end if
                                            end try
                                        end repeat
                                    end try
                                end repeat
                            end try
                            -- グループ内のテキストエリア
                            try
                                set allGroups to every group of win
                                repeat with grp in allGroups
                                    try
                                        set innerGroups to every group of grp
                                        repeat with innerGrp in innerGroups
                                            try
                                                set grpScrolls to every scroll area of innerGrp
                                                repeat with gs in grpScrolls
                                                    try
                                                        set gsText to value of first text area of gs
                                                        if gsText is not missing value then
                                                            set allText to allText & gsText & return
                                                        end if
                                                    end try
                                                end repeat
                                            end try
                                        end repeat
                                    end try
                                end repeat
                            end try
                        end repeat
                        return allText
                    on error errMsg
                        return "Error: " & errMsg
                    end try
                end tell
            end tell
        "#, process_name);

        let output = Command::new("osascript")
            .arg("-e")
            .arg(&script)
            .output();

        match output {
            Ok(o) => {
                let content = String::from_utf8_lossy(&o.stdout).to_string();
                println!("[get_vscode_terminal_content] {} content length: {} chars", process_name, content.len());
                content
            }
            Err(e) => {
                eprintln!("[get_vscode_terminal_content] Failed to get {} content: {}", process_name, e);
                String::new()
            }
        }
    }

    #[cfg(target_os = "windows")]
    pub fn get_vscode_terminal_content(_app_name: &str) -> String {
        String::new()
    }

    /// アプリのテキストコンテンツを取得（アクセシビリティAPI使用） - macOS版
    #[cfg(target_os = "macos")]
    pub fn get_app_text_content(app_name: &str) -> String {
        let escaped_name = app_name.replace("\"", "\\\"");

        // System Eventsを使ってUIエレメントからテキストを取得
        // ターミナル系アプリは通常AXTextFieldやAXTextAreaを持つ
        let script = format!(r#"
            tell application "System Events"
                tell process "{}"
                    try
                        set allText to ""
                        -- ウィンドウの全テキストエリアを探す
                        set textElements to every text area of every scroll area of every window
                        repeat with elem in textElements
                            try
                                set elemValue to value of item 1 of item 1 of elem
                                if elemValue is not missing value then
                                    set allText to allText & elemValue
                                end if
                            end try
                        end repeat
                        -- もしテキストエリアがなければ、グループ内を探す
                        if allText = "" then
                            set groupElements to every group of every window
                            repeat with grp in groupElements
                                try
                                    set grpText to value of first text area of first scroll area of item 1 of grp
                                    if grpText is not missing value then
                                        set allText to allText & grpText
                                    end if
                                end try
                            end repeat
                        end if
                        return allText
                    on error errMsg
                        return ""
                    end try
                end tell
            end tell
        "#, escaped_name);

        let output = Command::new("osascript")
            .arg("-e")
            .arg(&script)
            .output();

        match output {
            Ok(o) => {
                let content = String::from_utf8_lossy(&o.stdout).to_string();
                println!("[get_app_text_content] {} content length: {} chars", app_name, content.len());
                content
            }
            Err(e) => {
                eprintln!("[get_app_text_content] Failed to get {} content: {}", app_name, e);
                String::new()
            }
        }
    }

    /// アプリテキストコンテンツ取得 - Windows版（未実装）
    #[cfg(target_os = "windows")]
    pub fn get_app_text_content(_app_name: &str) -> String {
        String::new()
    }

    /// 最前面のウィンドウ情報を取得 - macOS版
    #[cfg(target_os = "macos")]
    pub fn get_frontmost_window() -> Option<AppWindowInfo> {
        // タイムアウト付きでウィンドウ情報を取得
        // Electron系アプリは特に時間がかかるので長めに設定
        let script = r#"
            with timeout of 8 seconds
                tell application "System Events"
                    set frontApp to first application process whose frontmost is true
                    set appName to name of frontApp

                    try
                        -- ウィンドウが複数ある場合、最初の非最小化ウィンドウを優先
                        set frontWindow to missing value
                        repeat with w in windows of frontApp
                            try
                                set isMin to value of attribute "AXMinimized" of w
                                if isMin is false then
                                    set frontWindow to w
                                    exit repeat
                                end if
                            on error
                                -- AXMinimized取得失敗時はそのウィンドウを使用
                                set frontWindow to w
                                exit repeat
                            end try
                        end repeat

                        if frontWindow is missing value then
                            set frontWindow to first window of frontApp
                        end if

                        set winName to name of frontWindow
                        set winPos to position of frontWindow
                        set winSize to size of frontWindow

                        return appName & "|||" & winName & "|||" & (item 1 of winPos) & "|||" & (item 2 of winPos) & "|||" & (item 1 of winSize) & "|||" & (item 2 of winSize)
                    on error errMsg
                        return appName & "|||No Window|||0|||0|||0|||0"
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
                let stderr = String::from_utf8_lossy(&o.stderr);

                if !stderr.is_empty() {
                    eprintln!("[get_frontmost_window] stderr: {}", stderr);
                }

                let parts: Vec<&str> = stdout.trim().split("|||").collect();

                if parts.len() >= 6 {
                    let width = parts[4].parse().unwrap_or(0);
                    let height = parts[5].parse().unwrap_or(0);

                    // 幅または高さが0の場合のみ無効（小さいウィンドウは許可）
                    if width == 0 || height == 0 {
                        eprintln!("[get_frontmost_window] Invalid window size: {}x{}", width, height);
                        return None;
                    }

                    // x, yが負の場合は0にクランプ（一部アプリで負の座標が返る問題を回避）
                    let x: i32 = parts[2].parse().unwrap_or(0).max(0);
                    let y: i32 = parts[3].parse().unwrap_or(0).max(0);

                    Some(AppWindowInfo {
                        app_name: parts[0].to_string(),
                        window_title: parts[1].to_string(),
                        x,
                        y,
                        width,
                        height,
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
    /// 注：focusAppWindowが先に呼ばれている場合は、そのウィンドウを維持する
    pub fn focus_and_get_window(app_name: &str) -> Option<AppWindowInfo> {
        println!("[SystemControl] focus_and_get_window: Getting window info for '{}'", app_name);

        // アプリを最前面に
        println!("[SystemControl] Calling focus_app for '{}'", app_name);
        Self::focus_app(app_name);

        // アプリが最前面になるまでリトライ（最大5回、各200ms待機）
        let target_app_lower = app_name.to_lowercase();
        let mut window_info: Option<AppWindowInfo> = None;

        for attempt in 1..=5 {
            std::thread::sleep(std::time::Duration::from_millis(200));

            // ウィンドウを左上に移動（アプリ名を指定してより確実に）
            Self::move_window_to_top_left_for_app(Some(app_name), None, None);
            std::thread::sleep(std::time::Duration::from_millis(100));

            let info = Self::get_frontmost_window();

            if let Some(ref wi) = info {
                let info_app_lower = wi.app_name.to_lowercase();
                if info_app_lower.contains(&target_app_lower) || target_app_lower.contains(&info_app_lower) {
                    // ウィンドウが左上付近にあるか確認（許容誤差: x <= 10, y <= 50）
                    let is_positioned = wi.x <= 10 && wi.y <= 50;
                    if is_positioned {
                        println!("[SystemControl] App matched and positioned on attempt {}: '{}' at ({}, {})",
                            attempt, wi.app_name, wi.x, wi.y);
                        window_info = info;
                        break;
                    } else if attempt < 5 {
                        // まだ左上に移動していない場合、再試行
                        println!("[SystemControl] App matched but not positioned: '{}' at ({}, {}). Retrying move...",
                            wi.app_name, wi.x, wi.y);
                        Self::move_window_to_top_left_for_app(Some(app_name), None, None);
                    } else {
                        // 最終試行でも移動しなかった場合、現在位置で続行
                        println!("[SystemControl] App matched on final attempt {}: '{}' at ({}, {}) - position may not be top-left",
                            attempt, wi.app_name, wi.x, wi.y);
                        window_info = info;
                        break;
                    }
                } else {
                    println!("[SystemControl] Attempt {}: frontmost='{}', target='{}'. Retrying...",
                        attempt, wi.app_name, app_name);
                    // 再度フォーカスを試みる
                    Self::focus_app(app_name);
                }
            }
        }

        // ターゲットアプリがフォーカスできなかった場合
        if window_info.is_none() {
            println!("[SystemControl] Failed to focus target app '{}' after retries", app_name);
            // 最後に一度だけ現在の最前面を確認
            if let Some(info) = Self::get_frontmost_window() {
                let info_app_lower = info.app_name.to_lowercase();
                if info_app_lower.contains(&target_app_lower) || target_app_lower.contains(&info_app_lower) {
                    println!("[SystemControl] Target app found on final check: '{}'", info.app_name);
                    window_info = Some(info);
                } else {
                    // 間違ったアプリが最前面の場合はNoneを返す
                    println!("[SystemControl] Wrong app frontmost: '{}', expected '{}'. Returning None.",
                        info.app_name, app_name);
                    return None;
                }
            } else {
                return None;
            }
        }

        // ウィンドウの中央をクリックしてカーソルをアクティブ化
        if let Some(ref info) = window_info {
            let center_x = info.x + (info.width / 2);
            let center_y = info.y + (info.height / 2);
            println!("[SystemControl] Window at ({}, {}), clicking center ({}, {})",
                info.x, info.y, center_x, center_y);
            Self::click_at(center_x as f64, center_y as f64);
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

    /// フォーカス中のウィンドウを左上(0,25)に移動し、指定サイズに変更 - macOS版
    /// app_name: 対象アプリ名（指定するとより確実に移動できる）
    /// 最小化されている場合は自動的に最小化解除してから移動する
    #[cfg(target_os = "macos")]
    pub fn move_window_to_top_left_for_app(app_name: Option<&str>, width: Option<i32>, height: Option<i32>) -> bool {
        // ウィンドウを(0, 25)に移動（25はメニューバーの高さ）
        let size_script = if let (Some(w), Some(h)) = (width, height) {
            format!(
                r#"
                    set size of targetWindow to {{{}, {}}}
                "#,
                w, h
            )
        } else {
            String::new()
        };

        // アプリ名が指定されている場合は、そのアプリのウィンドウを直接操作
        let script = if let Some(name) = app_name {
            let escaped_name = name.replace("\"", "\\\"");
            format!(
                r#"
                tell application "System Events"
                    tell process "{}"
                        try
                            -- 最初のウィンドウを取得
                            if (count of windows) = 0 then
                                return "error: no windows"
                            end if
                            set targetWindow to first window

                            -- 最小化されている場合は解除
                            try
                                set isMin to value of attribute "AXMinimized" of targetWindow
                                if isMin is true then
                                    set value of attribute "AXMinimized" of targetWindow to false
                                    delay 0.3
                                end if
                            end try

                            -- ウィンドウを最前面に上げる
                            try
                                perform action "AXRaise" of targetWindow
                            end try

                            -- 位置を設定
                            set position of targetWindow to {{0, 25}}
                            {}
                            return "success"
                        on error errMsg
                            return "error: " & errMsg
                        end try
                    end tell
                end tell
                "#,
                escaped_name, size_script
            )
        } else {
            // アプリ名が指定されていない場合は従来通り
            format!(
                r#"
                tell application "System Events"
                    set frontApp to first application process whose frontmost is true
                    try
                        set targetWindow to first window of frontApp

                        -- 最小化されている場合は解除
                        try
                            set isMin to value of attribute "AXMinimized" of targetWindow
                            if isMin is true then
                                set value of attribute "AXMinimized" of targetWindow to false
                                delay 0.3
                            end if
                        end try

                        -- ウィンドウを最前面に上げる
                        try
                            perform action "AXRaise" of targetWindow
                        end try

                        set position of targetWindow to {{0, 25}}
                        {}
                        return "success"
                    on error errMsg
                        return "error: " & errMsg
                    end try
                end tell
                "#,
                size_script
            )
        };

        match Command::new("osascript")
            .args(["-e", &script])
            .output()
        {
            Ok(output) => {
                let stdout = String::from_utf8_lossy(&output.stdout);
                let success = stdout.trim().starts_with("success");
                println!("[SystemControl] move_window_to_top_left_for_app({:?}): {}", app_name, stdout.trim());
                success
            }
            Err(e) => {
                println!("[SystemControl] move_window_to_top_left_for_app error: {}", e);
                false
            }
        }
    }

    /// フォーカス中のウィンドウを左上(0,25)に移動し、指定サイズに変更 - macOS版（互換用）
    #[cfg(target_os = "macos")]
    pub fn move_window_to_top_left(width: Option<i32>, height: Option<i32>) -> bool {
        Self::move_window_to_top_left_for_app(None, width, height)
    }

    #[cfg(not(target_os = "macos"))]
    pub fn move_window_to_top_left(_width: Option<i32>, _height: Option<i32>) -> bool {
        // Windows/Linux版は未実装
        false
    }

    #[cfg(not(target_os = "macos"))]
    pub fn move_window_to_top_left_for_app(_app_name: Option<&str>, _width: Option<i32>, _height: Option<i32>) -> bool {
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
                is_cli: false, // GUIアプリ
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
