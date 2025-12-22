use portable_pty::{native_pty_system, CommandBuilder, PtySize, MasterPty};
use std::io::{Read, Write};
use std::sync::{Arc, Mutex};
use std::thread;
use tokio::sync::mpsc;

pub struct PtySession {
    master: Arc<Mutex<Box<dyn MasterPty + Send>>>,
    output_buffer: Arc<Mutex<Vec<String>>>,
}

pub struct PtySessionHandle {
    pub session: PtySession,
    pub output_rx: mpsc::Receiver<String>,
}

impl PtySession {
    pub fn new() -> Result<PtySessionHandle, Box<dyn std::error::Error + Send + Sync>> {
        let pty_system = native_pty_system();

        let pair = pty_system.openpty(PtySize {
            rows: 50,
            cols: 120,
            pixel_width: 0,
            pixel_height: 0,
        })?;

        // シェルを起動
        let mut cmd = CommandBuilder::new("zsh");
        cmd.env("TERM", "xterm-256color");
        cmd.env("LANG", "ja_JP.UTF-8");

        let _child = pair.slave.spawn_command(cmd)?;
        drop(pair.slave); // slaveは子プロセスに渡したので解放

        let master = Arc::new(Mutex::new(pair.master));
        let output_buffer = Arc::new(Mutex::new(Vec::new()));

        // 出力を読み取るチャンネル
        let (output_tx, output_rx) = mpsc::channel::<String>(100);

        // 出力読み取りスレッド
        let master_clone = master.clone();
        let buffer_clone = output_buffer.clone();
        thread::spawn(move || {
            let mut reader = {
                let master = master_clone.lock().unwrap();
                match master.try_clone_reader() {
                    Ok(r) => r,
                    Err(e) => {
                        eprintln!("Failed to clone PTY reader: {}", e);
                        return;
                    }
                }
            };

            let mut buf = [0u8; 4096];
            loop {
                match reader.read(&mut buf) {
                    Ok(0) => break, // EOF
                    Ok(n) => {
                        let text = String::from_utf8_lossy(&buf[..n]).to_string();

                        // バッファに保存（履歴用）
                        {
                            let mut buffer = buffer_clone.lock().unwrap();
                            buffer.push(text.clone());
                            // 最大1000行保持
                            if buffer.len() > 1000 {
                                buffer.remove(0);
                            }
                        }

                        // チャンネルに送信（非同期）
                        if output_tx.blocking_send(text).is_err() {
                            break;
                        }
                    }
                    Err(e) => {
                        eprintln!("PTY read error: {}", e);
                        break;
                    }
                }
            }
        });

        let session = PtySession {
            master,
            output_buffer,
        };

        Ok(PtySessionHandle { session, output_rx })
    }

    /// 入力を送信
    pub fn write(&self, input: &str) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
        let master = self.master.lock().unwrap();
        let mut writer = master.take_writer()?;
        writer.write_all(input.as_bytes())?;
        writer.flush()?;
        Ok(())
    }

    /// 履歴を1つの文字列として取得
    pub fn get_history_text(&self) -> String {
        let buffer = self.output_buffer.lock().unwrap();
        buffer.join("")
    }
}
