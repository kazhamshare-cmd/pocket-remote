use scrap::{Capturer, Display};
use std::io::ErrorKind::WouldBlock;
use tokio::sync::broadcast;
use image::{ImageBuffer, Rgba, DynamicImage};
use std::time::Duration;
use serde::{Serialize, Deserialize};
use parking_lot::RwLock;
use std::sync::Arc;
use rayon::prelude::*;
use crate::CaptureRegion;
use crate::h264_encoder::H264Encoder;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WindowInfo {
    pub id: u32,
    pub name: String,
    pub owner_name: String,
}

pub struct ScreenCapturer {
    width: usize,
    height: usize,
}

impl ScreenCapturer {
    pub fn new() -> Result<Self, String> {
        let display = Display::primary().map_err(|e| format!("Failed to get display: {}", e))?;
        let width = display.width();
        let height = display.height();

        Ok(Self { width, height })
    }

    pub fn get_dimensions(&self) -> (usize, usize) {
        (self.width, self.height)
    }

    /// 利用可能なウィンドウ一覧を取得（将来の拡張用）
    pub fn list_windows() -> Vec<WindowInfo> {
        // 現在は全画面のみサポート
        vec![WindowInfo {
            id: 0,
            name: "全画面".to_string(),
            owner_name: "Desktop".to_string(),
        }]
    }

    pub fn start_capture(
        _width: usize,
        _height: usize,
        tx: broadcast::Sender<Vec<u8>>,
        capture_region: Arc<RwLock<Option<CaptureRegion>>>,
        ws_capture_running: Arc<std::sync::atomic::AtomicBool>,
    ) {
        std::thread::spawn(move || {
            loop {
                // WSキャプチャが有効になるまで待機
                while !ws_capture_running.load(std::sync::atomic::Ordering::SeqCst) {
                    std::thread::sleep(Duration::from_millis(100));
                }

                let display = match Display::primary() {
                    Ok(d) => d,
                    Err(e) => {
                        eprintln!("Failed to get display: {}", e);
                        std::thread::sleep(Duration::from_secs(1));
                        continue;
                    }
                };

                let mut capturer = match Capturer::new(display) {
                    Ok(c) => c,
                    Err(e) => {
                        eprintln!("Failed to create capturer: {}", e);
                        std::thread::sleep(Duration::from_secs(1));
                        continue;
                    }
                };

            let width = capturer.width();
            let height = capturer.height();
            let bytes_per_pixel = 4;

            println!("Capturer dimensions: {}x{}", width, height);

            let mut frame_count: u64 = 0;
            let mut logged_info = false;

            // H.264エンコーダーを初期化（フルスケール - 最高画質）
            let scaled_w = ((width) as u32 / 2) * 2; // 2の倍数に調整
            let scaled_h = ((height) as u32 / 2) * 2;
            let mut h264_encoder = match H264Encoder::new(scaled_w, scaled_h) {
                Ok(enc) => {
                    println!("[WS-H264] Encoder created: {}x{}", scaled_w, scaled_h);
                    Some(enc)
                }
                Err(e) => {
                    eprintln!("[WS-H264] Failed to create encoder: {}", e);
                    None
                }
            };

            // 内側のキャプチャループ
            while ws_capture_running.load(std::sync::atomic::Ordering::SeqCst) {
                match capturer.frame() {
                    Ok(frame) => {
                        let row_bytes = width * bytes_per_pixel;
                        // macOS IOSurfaceは128バイトアライメント
                        let alignment = 128;
                        let actual_stride = ((row_bytes + alignment - 1) / alignment) * alignment;

                        if !logged_info {
                            println!("Screen capture ready: {}x{}, stride: {}", width, height, actual_stride);
                            logged_info = true;
                        }

                        // RGBA画像データを作成（rayon並列化版）
                        // macOS scrapはBGRA形式: B=frame[i], G=frame[i+1], R=frame[i+2], A=frame[i+3]
                        // scrap::FrameはSync未実装のため、まずコピー
                        let frame_data: Vec<u8> = frame.to_vec();
                        let mut rgba_data = vec![0u8; width * height * 4];
                        let row_width = width * 4;

                        rgba_data
                            .par_chunks_mut(row_width)
                            .enumerate()
                            .for_each(|(y, dst_row)| {
                                let row_start = y * actual_stride;
                                for (x, dst_chunk) in dst_row.chunks_exact_mut(4).enumerate() {
                                    let i = row_start + x * bytes_per_pixel;
                                    if i + 3 < frame_data.len() {
                                        dst_chunk[0] = frame_data[i + 2]; // R
                                        dst_chunk[1] = frame_data[i + 1]; // G
                                        dst_chunk[2] = frame_data[i];     // B
                                        dst_chunk[3] = frame_data[i + 3]; // A
                                    }
                                }
                            });

                        if rgba_data.len() == width * height * 4 {
                            if let Some(img) = ImageBuffer::<Rgba<u8>, _>::from_raw(
                                width as u32,
                                height as u32,
                                rgba_data,
                            ) {
                                let dynamic_img = DynamicImage::ImageRgba8(img);

                                // キャプチャ領域をチェック
                                let region = capture_region.read().clone();

                                // H.264エンコード用に1/2スケールにリサイズ
                                // TCPなのでサイズ制限なし、高品質で送信可能
                                let final_img = if let Some(r) = region {
                                    // 領域指定あり: その領域をクロップ
                                    let crop_x = (r.x as u32).min(width as u32);
                                    let crop_y = (r.y as u32).min(height as u32);
                                    let crop_w = (r.width as u32).min(width as u32 - crop_x);
                                    let crop_h = (r.height as u32).min(height as u32 - crop_y);

                                    if crop_w > 0 && crop_h > 0 {
                                        dynamic_img.crop_imm(crop_x, crop_y, crop_w, crop_h)
                                    } else {
                                        dynamic_img.clone()
                                    }
                                } else {
                                    dynamic_img.clone()
                                };

                                // フルスケール、2の倍数に調整（最高画質）
                                let new_width = (final_img.width() / 2) * 2;
                                let new_height = (final_img.height() / 2) * 2;
                                let new_width = new_width.max(2);
                                let new_height = new_height.max(2);

                                let resized = final_img.resize_exact(
                                    new_width,
                                    new_height,
                                    image::imageops::FilterType::Triangle,
                                );

                                // RGBAからBGRAに変換（H264エンコーダーはBGRA入力）
                                let rgba_bytes = resized.to_rgba8().into_raw();
                                let mut bgra_bytes = vec![0u8; rgba_bytes.len()];
                                for (i, chunk) in rgba_bytes.chunks(4).enumerate() {
                                    bgra_bytes[i * 4] = chunk[2];     // B
                                    bgra_bytes[i * 4 + 1] = chunk[1]; // G
                                    bgra_bytes[i * 4 + 2] = chunk[0]; // R
                                    bgra_bytes[i * 4 + 3] = chunk[3]; // A
                                }

                                // H.264エンコード
                                if let Some(ref mut encoder) = h264_encoder {
                                    match encoder.encode_bgra(&bgra_bytes, new_width, new_height) {
                                        Ok(h264_data) => {
                                            if !h264_data.is_empty() {
                                                let receivers = tx.receiver_count();
                                                if receivers > 0 {
                                                    let h264_size = h264_data.len();
                                                    match tx.send(h264_data) {
                                                        Ok(_) => {
                                                            frame_count += 1;
                                                            if frame_count == 1 || frame_count % 100 == 0 {
                                                                println!("[WS-H264] Frame {} sent, {} receivers, {} KB, {}x{}",
                                                                         frame_count, receivers, h264_size / 1024, new_width, new_height);
                                                            }
                                                        }
                                                        Err(e) => {
                                                            eprintln!("[WS-H264] Failed to send frame: {}", e);
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                        Err(e) => {
                                            if frame_count == 0 {
                                                eprintln!("[WS-H264] Encode error: {}", e);
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    Err(ref e) if e.kind() == WouldBlock => {
                        // フレームがまだ準備できていない
                    }
                    Err(e) => {
                        eprintln!("Capture error: {}", e);
                        break;
                    }
                }

                // 約30fps（高速化）
                std::thread::sleep(Duration::from_millis(33));
            }

            // 内側ループを抜けた（ws_capture_runningがfalseになった）
            // Capturerを解放して、外側ループに戻る
            drop(capturer);
            println!("[WS] Capturer released, waiting for system cleanup...");
            // macOSのDisplay Streamコールバックが完全に終了するまで待機
            // scrapライブラリのquartzバックエンドに競合状態があるため長めに待つ
            std::thread::sleep(Duration::from_secs(3));
            println!("[WS] Ready for restart");
            } // 外側のloop終了
        });
    }
}
