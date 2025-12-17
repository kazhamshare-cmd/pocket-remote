use serde::{Deserialize, Serialize};
use std::process::Command;

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

pub struct SystemController;

impl SystemController {
    /// 起動中のアプリケーション一覧を取得（高速版）
    pub fn get_running_apps() -> Vec<RunningApp> {
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

    /// アプリをフォーカス（アクティブに）
    pub fn focus_app(app_name: &str) -> bool {
        let script = format!(
            r#"tell application "{}" to activate"#,
            app_name.replace("\"", "\\\"")
        );

        Command::new("osascript")
            .arg("-e")
            .arg(&script)
            .status()
            .map(|s| s.success())
            .unwrap_or(false)
    }

    /// アプリを終了する
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

    /// 現在のウィンドウ/タブを閉じる（Cmd+W）
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

    /// Spotlight検索を開いてクエリを入力（クリップボード経由でIME問題を回避）
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

    /// ファイルを開く
    pub fn open_file(path: &str) -> bool {
        Command::new("open")
            .arg(path)
            .status()
            .map(|s| s.success())
            .unwrap_or(false)
    }

    /// Safari/Chromeのタブ一覧を取得
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

        let output = Command::new("osascript")
            .arg("-e")
            .arg(&script)
            .output();

        match output {
            Ok(o) => {
                let stdout = String::from_utf8_lossy(&o.stdout);
                parse_browser_tabs(&stdout)
            }
            Err(e) => {
                eprintln!("Failed to get browser tabs: {}", e);
                Vec::new()
            }
        }
    }

    /// Safariのタブをアクティブにする
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

    /// Chromeのタブをアクティブにする
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

    /// クリップボード経由でテキストを入力（IMEの影響を受けない）
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

    /// テキストを入力してEnterキーを押す（LINEなどでメッセージ送信）
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

    /// AppleScript経由でキーを押す
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

    /// Terminal.appのウィンドウ・タブ一覧を取得
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

    /// iTerm2のウィンドウ・タブ一覧を取得
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

    /// Terminal.appの特定のタブをアクティブにする
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

    /// iTerm2の特定のタブをアクティブにする
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

    /// 最前面のウィンドウ情報を取得
    pub fn get_frontmost_window() -> Option<AppWindowInfo> {
        let script = r#"
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

    /// 指定アプリのウィンドウを最前面に持ってきて最大化し、サイズを取得
    pub fn focus_and_get_window(app_name: &str) -> Option<AppWindowInfo> {
        // まずアプリをフォーカス
        Self::focus_app(app_name);

        // 少し待機
        std::thread::sleep(std::time::Duration::from_millis(100));

        // ウィンドウを最大化して他のアプリを隠す
        Self::maximize_window();

        // 最大化後に少し待ってからウィンドウ情報を取得
        std::thread::sleep(std::time::Duration::from_millis(200));

        Self::get_frontmost_window()
    }

    /// ウィンドウを最大化（フルスクリーンではなく画面いっぱいに）
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
}

/// AppleScriptの出力をパースしてBrowserTabのリストに変換
fn parse_browser_tabs(output: &str) -> Vec<BrowserTab> {
    let mut tabs = Vec::new();
    let trimmed = output.trim();

    // 簡易パース: index, title, url の組み合わせを探す
    let parts: Vec<&str> = trimmed.split(", ").collect();

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
