use enigo::{Enigo, Mouse, Keyboard, Settings, Coordinate, Button, Key};
use serde::{Deserialize, Serialize};
use std::sync::mpsc;
use std::thread;

#[cfg(target_os = "macos")]
use core_graphics::event::CGEvent;
#[cfg(target_os = "macos")]
use core_graphics::event_source::{CGEventSource, CGEventSourceStateID};

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
                enigo
                    .move_mouse(x, y, Coordinate::Abs)
                    .map_err(|e| e.to_string())?;
            }
            InputEvent::MouseClick { x, y, button } => {
                enigo
                    .move_mouse(x, y, Coordinate::Abs)
                    .map_err(|e| e.to_string())?;
                let btn = Self::parse_button(&button);
                enigo.button(btn, enigo::Direction::Click)
                    .map_err(|e| e.to_string())?;
            }
            InputEvent::MouseDown { x, y, button } => {
                enigo
                    .move_mouse(x, y, Coordinate::Abs)
                    .map_err(|e| e.to_string())?;
                let btn = Self::parse_button(&button);
                enigo.button(btn, enigo::Direction::Press)
                    .map_err(|e| e.to_string())?;
            }
            InputEvent::MouseUp { x, y, button } => {
                enigo
                    .move_mouse(x, y, Coordinate::Abs)
                    .map_err(|e| e.to_string())?;
                let btn = Self::parse_button(&button);
                enigo.button(btn, enigo::Direction::Release)
                    .map_err(|e| e.to_string())?;
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
                enigo.text(&text)
                    .map_err(|e| e.to_string())?;
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
