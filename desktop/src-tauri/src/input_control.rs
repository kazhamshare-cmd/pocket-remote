use enigo::{Enigo, Mouse, Keyboard, Settings, Coordinate, Button, Key};
use serde::{Deserialize, Serialize};
use std::sync::mpsc;
use std::thread;
use std::process::Command;

#[cfg(target_os = "macos")]
use core_graphics::event::{CGEvent, CGEventType, CGMouseButton};
#[cfg(target_os = "macos")]
use core_graphics::event_source::{CGEventSource, CGEventSourceStateID};
#[cfg(target_os = "macos")]
use core_graphics::geometry::CGPoint;

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "action")]
pub enum InputEvent {
    #[serde(rename = "mouse_move")]
    MouseMove { x: i32, y: i32 },
    #[serde(rename = "mouse_click")]
    MouseClick { x: i32, y: i32, button: String },
    #[serde(rename = "mouse_down")]
    MouseDown { x: i32, y: i32, button: String },
    #[serde(rename = "mouse_up")]
    MouseUp { x: i32, y: i32, button: String },
    #[serde(rename = "mouse_scroll")]
    MouseScroll { delta_x: i32, delta_y: i32 },
    #[serde(rename = "key_press")]
    KeyPress { key: String },
    #[serde(rename = "key_type")]
    KeyType { text: String },
}

pub struct InputController {
    tx: mpsc::Sender<InputEvent>,
}

impl InputController {
    pub fn new() -> Self {
        let (tx, rx) = mpsc::channel::<InputEvent>();

        // 別スレッドで入力処理（enigoはSendではないため）
        thread::spawn(move || {
            let mut enigo = match Enigo::new(&Settings::default()) {
                Ok(e) => e,
                Err(e) => {
                    eprintln!("Failed to create Enigo: {}", e);
                    return;
                }
            };

            while let Ok(event) = rx.recv() {
                if let Err(e) = Self::handle_event_inner(&mut enigo, event) {
                    eprintln!("Input error: {}", e);
                }
            }
        });

        Self { tx }
    }

    pub fn send_event(&self, event: InputEvent) {
        let _ = self.tx.send(event);
    }

    fn handle_event_inner(enigo: &mut Enigo, event: InputEvent) -> Result<(), String> {
        match event {
            InputEvent::MouseMove { x, y } => {
                #[cfg(target_os = "macos")]
                {
                    // macOSではCGEventを直接使用してマウス移動
                    // Privateを使用して他のイベントソースの状態に影響されないようにする
                    let point = CGPoint::new(x as f64, y as f64);
                    if let Ok(source) = CGEventSource::new(CGEventSourceStateID::Private) {
                        if let Ok(event) = CGEvent::new_mouse_event(
                            source,
                            CGEventType::MouseMoved,
                            point,
                            CGMouseButton::Left,
                        ) {
                            // ボタン状態をクリア（ドラッグ状態を防ぐ）
                            event.set_integer_value_field(
                                core_graphics::event::EventField::MOUSE_EVENT_BUTTON_NUMBER,
                                0
                            );
                            event.post(core_graphics::event::CGEventTapLocation::HID);
                        }
                    }
                }
                #[cfg(not(target_os = "macos"))]
                {
                    enigo
                        .move_mouse(x, y, Coordinate::Abs)
                        .map_err(|e| e.to_string())?;
                }
            }
            InputEvent::MouseClick { x, y, button } => {
                #[cfg(target_os = "macos")]
                {
                    let point = CGPoint::new(x as f64, y as f64);
                    let cg_button = Self::parse_cg_button(&button);
                    let (down_type, up_type) = Self::get_click_event_types(&button);

                    if let Ok(source) = CGEventSource::new(CGEventSourceStateID::Private) {
                        // Mouse down
                        if let Ok(down_event) = CGEvent::new_mouse_event(
                            source.clone(),
                            down_type,
                            point,
                            cg_button,
                        ) {
                            down_event.post(core_graphics::event::CGEventTapLocation::HID);
                        }
                        // Mouse up
                        if let Ok(up_event) = CGEvent::new_mouse_event(
                            source,
                            up_type,
                            point,
                            cg_button,
                        ) {
                            up_event.post(core_graphics::event::CGEventTapLocation::HID);
                        }
                    }
                }
                #[cfg(not(target_os = "macos"))]
                {
                    enigo.move_mouse(x, y, Coordinate::Abs).map_err(|e| e.to_string())?;
                    let btn = Self::parse_button(&button);
                    enigo.button(btn, enigo::Direction::Click).map_err(|e| e.to_string())?;
                }
            }
            InputEvent::MouseDown { x, y, button } => {
                #[cfg(target_os = "macos")]
                {
                    let point = CGPoint::new(x as f64, y as f64);
                    let cg_button = Self::parse_cg_button(&button);
                    let (down_type, _) = Self::get_click_event_types(&button);

                    if let Ok(source) = CGEventSource::new(CGEventSourceStateID::Private) {
                        if let Ok(event) = CGEvent::new_mouse_event(
                            source,
                            down_type,
                            point,
                            cg_button,
                        ) {
                            event.post(core_graphics::event::CGEventTapLocation::HID);
                        }
                    }
                }
                #[cfg(not(target_os = "macos"))]
                {
                    enigo.move_mouse(x, y, Coordinate::Abs).map_err(|e| e.to_string())?;
                    let btn = Self::parse_button(&button);
                    enigo.button(btn, enigo::Direction::Press).map_err(|e| e.to_string())?;
                }
            }
            InputEvent::MouseUp { x, y, button } => {
                #[cfg(target_os = "macos")]
                {
                    let point = CGPoint::new(x as f64, y as f64);
                    let cg_button = Self::parse_cg_button(&button);
                    let (_, up_type) = Self::get_click_event_types(&button);

                    if let Ok(source) = CGEventSource::new(CGEventSourceStateID::Private) {
                        if let Ok(event) = CGEvent::new_mouse_event(
                            source,
                            up_type,
                            point,
                            cg_button,
                        ) {
                            event.post(core_graphics::event::CGEventTapLocation::HID);
                        }
                    }
                }
                #[cfg(not(target_os = "macos"))]
                {
                    enigo.move_mouse(x, y, Coordinate::Abs).map_err(|e| e.to_string())?;
                    let btn = Self::parse_button(&button);
                    enigo.button(btn, enigo::Direction::Release).map_err(|e| e.to_string())?;
                }
            }
            InputEvent::MouseScroll { delta_x, delta_y } => {
                if delta_y != 0 {
                    enigo.scroll(delta_y, enigo::Axis::Vertical)
                        .map_err(|e| e.to_string())?;
                }
                if delta_x != 0 {
                    enigo.scroll(delta_x, enigo::Axis::Horizontal)
                        .map_err(|e| e.to_string())?;
                }
            }
            InputEvent::KeyPress { key } => {
                if let Some(k) = Self::parse_key(&key) {
                    enigo.key(k, enigo::Direction::Click)
                        .map_err(|e| e.to_string())?;
                }
            }
            InputEvent::KeyType { text } => {
                // 日本語などのUnicode文字を含む場合はクリップボード経由でペースト
                #[cfg(target_os = "macos")]
                {
                    if text.chars().any(|c| !c.is_ascii()) {
                        // クリップボードにコピー（pbcopy使用）
                        let mut child = Command::new("pbcopy")
                            .stdin(std::process::Stdio::piped())
                            .spawn()
                            .map_err(|e| format!("Failed to spawn pbcopy: {}", e))?;

                        if let Some(stdin) = child.stdin.as_mut() {
                            use std::io::Write;
                            stdin.write_all(text.as_bytes())
                                .map_err(|e| format!("Failed to write to pbcopy: {}", e))?;
                        }
                        child.wait().map_err(|e| format!("pbcopy failed: {}", e))?;

                        // 少し待ってからCmd+Vでペースト
                        std::thread::sleep(std::time::Duration::from_millis(50));
                        enigo.key(Key::Meta, enigo::Direction::Press)
                            .map_err(|e| e.to_string())?;
                        enigo.key(Key::Unicode('v'), enigo::Direction::Click)
                            .map_err(|e| e.to_string())?;
                        enigo.key(Key::Meta, enigo::Direction::Release)
                            .map_err(|e| e.to_string())?;
                    } else {
                        enigo.text(&text)
                            .map_err(|e| e.to_string())?;
                    }
                }
                #[cfg(target_os = "windows")]
                {
                    if text.chars().any(|c| !c.is_ascii()) {
                        // Windowsではclip.exeを使用してクリップボードにコピー
                        // PowerShellでUTF-16LEエンコーディングで書き込む
                        let mut child = Command::new("powershell")
                            .args(["-Command", &format!("Set-Clipboard -Value '{}'", text.replace("'", "''"))])
                            .spawn()
                            .map_err(|e| format!("Failed to spawn powershell: {}", e))?;

                        child.wait().map_err(|e| format!("powershell failed: {}", e))?;

                        // 少し待ってからCtrl+Vでペースト
                        std::thread::sleep(std::time::Duration::from_millis(50));
                        enigo.key(Key::Control, enigo::Direction::Press)
                            .map_err(|e| e.to_string())?;
                        enigo.key(Key::Unicode('v'), enigo::Direction::Click)
                            .map_err(|e| e.to_string())?;
                        enigo.key(Key::Control, enigo::Direction::Release)
                            .map_err(|e| e.to_string())?;
                    } else {
                        enigo.text(&text)
                            .map_err(|e| e.to_string())?;
                    }
                }
                #[cfg(not(any(target_os = "macos", target_os = "windows")))]
                {
                    enigo.text(&text)
                        .map_err(|e| e.to_string())?;
                }
            }
        }
        Ok(())
    }

    fn parse_button(button: &str) -> Button {
        match button.to_lowercase().as_str() {
            "right" => Button::Right,
            "middle" => Button::Middle,
            _ => Button::Left,
        }
    }

    #[cfg(target_os = "macos")]
    fn parse_cg_button(button: &str) -> CGMouseButton {
        match button.to_lowercase().as_str() {
            "right" => CGMouseButton::Right,
            "middle" => CGMouseButton::Center,
            _ => CGMouseButton::Left,
        }
    }

    #[cfg(target_os = "macos")]
    fn get_click_event_types(button: &str) -> (CGEventType, CGEventType) {
        match button.to_lowercase().as_str() {
            "right" => (CGEventType::RightMouseDown, CGEventType::RightMouseUp),
            "middle" => (CGEventType::OtherMouseDown, CGEventType::OtherMouseUp),
            _ => (CGEventType::LeftMouseDown, CGEventType::LeftMouseUp),
        }
    }

    fn parse_key(key: &str) -> Option<Key> {
        match key.to_lowercase().as_str() {
            "enter" | "return" => Some(Key::Return),
            "tab" => Some(Key::Tab),
            "space" => Some(Key::Space),
            "backspace" => Some(Key::Backspace),
            "delete" => Some(Key::Delete),
            "escape" | "esc" => Some(Key::Escape),
            "up" => Some(Key::UpArrow),
            "down" => Some(Key::DownArrow),
            "left" => Some(Key::LeftArrow),
            "right" => Some(Key::RightArrow),
            "home" => Some(Key::Home),
            "end" => Some(Key::End),
            "pageup" => Some(Key::PageUp),
            "pagedown" => Some(Key::PageDown),
            "shift" => Some(Key::Shift),
            "control" | "ctrl" => Some(Key::Control),
            "alt" | "option" => Some(Key::Alt),
            "meta" | "command" | "cmd" => Some(Key::Meta),
            "f1" => Some(Key::F1),
            "f2" => Some(Key::F2),
            "f3" => Some(Key::F3),
            "f4" => Some(Key::F4),
            "f5" => Some(Key::F5),
            "f6" => Some(Key::F6),
            "f7" => Some(Key::F7),
            "f8" => Some(Key::F8),
            "f9" => Some(Key::F9),
            "f10" => Some(Key::F10),
            "f11" => Some(Key::F11),
            "f12" => Some(Key::F12),
            _ => None,
        }
    }
}

/// 現在のマウスカーソル位置を取得（macOS）
#[cfg(target_os = "macos")]
pub fn get_mouse_position() -> Option<(i32, i32)> {
    let source = CGEventSource::new(CGEventSourceStateID::HIDSystemState).ok()?;
    let event = CGEvent::new(source).ok()?;
    let point = event.location();
    Some((point.x as i32, point.y as i32))
}

#[cfg(not(target_os = "macos"))]
pub fn get_mouse_position() -> Option<(i32, i32)> {
    None
}
