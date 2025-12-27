use xcap::Monitor;
use tokio::sync::broadcast;
use image::{ImageBuffer, Rgba, DynamicImage, RgbaImage};
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
    scale_factor: f32,
}

impl ScreenCapturer {
    pub fn new() -> Result<Self, String> {
        let monitors = Monitor::all().map_err(|e| format!("Failed to get monitors: {}", e))?;
        let monitor = monitors.first().ok_or("No monitor found")?;

        // 論理解像度
        let logical_width = monitor.width().map_err(|e| format!("Failed to get width: {}", e))?;
        let logical_height = monitor.height().map_err(|e| format!("Failed to get height: {}", e))?;
        let scale_factor = monitor.scale_factor().unwrap_or(1.0);

        // ネイティブ解像度（実際のキャプチャサイズ）
        let native_width = (logical_width as f32 * scale_factor) as usize;
        let native_height = (logical_height as f32 * scale_factor) as usize;

        println!("[xcap] Logical: {}x{}, Scale: {}, Native: {}x{}",
                 logical_width, logical_height, scale_factor, native_width, native_height);

        Ok(Self {
            width: native_width,
            height: native_height,
            scale_factor,
        })
    }

    pub fn get_dimensions(&self) -> (usize, usize) {
        (self.width, self.height)
    }

    /// 利用可能なウィンドウ一覧を取得（将来の拡張用）
    pub fn list_windows() -> Vec<WindowInfo> {
        vec![WindowInfo {
            id: 0,
            name: "全画面".to_string(),
            owner_name: "Desktop".to_string(),
        }]
    }

    pub fn start_capture(
        width: usize,
        height: usize,
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

                let monitors = match Monitor::all() {
                    Ok(m) => m,
                    Err(e) => {
                        eprintln!("Failed to get monitors: {}", e);
                        std::thread::sleep(Duration::from_secs(1));
                        continue;
                    }
                };

                let monitor = match monitors.first() {
                    Some(m) => m,
                    None => {
                        eprintln!("No monitor found");
                        std::thread::sleep(Duration::from_secs(1));
                        continue;
                    }
                };

                let scale_factor = monitor.scale_factor().unwrap_or(1.0);
                println!("[xcap] Capture starting, scale factor: {}", scale_factor);

                let mut frame_count: u64 = 0;
                let mut logged_info = false;
                let mut h264_encoder: Option<H264Encoder> = None;
                let mut last_encoder_size: (u32, u32) = (0, 0);

                // 内側のキャプチャループ
                while ws_capture_running.load(std::sync::atomic::Ordering::SeqCst) {
                    match monitor.capture_image() {
                        Ok(img) => {
                            let cap_width = img.width() as usize;
                            let cap_height = img.height() as usize;

                            if !logged_info {
                                println!("[xcap] Captured: {}x{} (native resolution)", cap_width, cap_height);
                                logged_info = true;
                            }

                            // RgbaImageに変換
                            let rgba_img: RgbaImage = img;
                            let dynamic_img = DynamicImage::ImageRgba8(rgba_img);

                            // キャプチャ領域をチェック（座標はスケール係数で変換）
                            let region = capture_region.read().clone();

                            let final_img = if let Some(r) = region {
                                // 領域指定あり: 座標をネイティブ解像度にスケール
                                let crop_x = ((r.x as f32 * scale_factor) as u32).min(cap_width as u32);
                                let crop_y = ((r.y as f32 * scale_factor) as u32).min(cap_height as u32);
                                let crop_w = ((r.width as f32 * scale_factor) as u32).min(cap_width as u32 - crop_x);
                                let crop_h = ((r.height as f32 * scale_factor) as u32).min(cap_height as u32 - crop_y);

                                if crop_w > 0 && crop_h > 0 {
                                    dynamic_img.crop_imm(crop_x, crop_y, crop_w, crop_h)
                                } else {
                                    dynamic_img.clone()
                                }
                            } else {
                                dynamic_img.clone()
                            };

                            // エンコード用サイズ（2の倍数に調整、最大1920x1200程度に制限）
                            let max_width = 1920u32;
                            let max_height = 1200u32;
                            let img_w = final_img.width();
                            let img_h = final_img.height();

                            // アスペクト比を維持してリサイズ
                            let (new_width, new_height) = if img_w > max_width || img_h > max_height {
                                let scale = (max_width as f32 / img_w as f32)
                                    .min(max_height as f32 / img_h as f32);
                                let w = ((img_w as f32 * scale) as u32 / 2) * 2;
                                let h = ((img_h as f32 * scale) as u32 / 2) * 2;
                                (w.max(2), h.max(2))
                            } else {
                                let w = (img_w / 2) * 2;
                                let h = (img_h / 2) * 2;
                                (w.max(2), h.max(2))
                            };

                            // エンコーダーサイズが変わったら再作成
                            if h264_encoder.is_none() || last_encoder_size != (new_width, new_height) {
                                h264_encoder = match H264Encoder::new(new_width, new_height) {
                                    Ok(enc) => {
                                        println!("[xcap-H264] Encoder created: {}x{}", new_width, new_height);
                                        last_encoder_size = (new_width, new_height);
                                        Some(enc)
                                    }
                                    Err(e) => {
                                        eprintln!("[xcap-H264] Failed to create encoder: {}", e);
                                        None
                                    }
                                };
                            }

                            let resized = final_img.resize_exact(
                                new_width,
                                new_height,
                                image::imageops::FilterType::Triangle,
                            );

                            // RGBAからBGRAに変換
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
                                                            println!("[xcap-H264] Frame {} sent, {} receivers, {} KB, {}x{}",
                                                                     frame_count, receivers, h264_size / 1024, new_width, new_height);
                                                        }
                                                    }
                                                    Err(e) => {
                                                        eprintln!("[xcap-H264] Failed to send frame: {}", e);
                                                    }
                                                }
                                            }
                                        }
                                    }
                                    Err(e) => {
                                        if frame_count == 0 {
                                            eprintln!("[xcap-H264] Encode error: {}", e);
                                        }
                                    }
                                }
                            }
                        }
                        Err(e) => {
                            eprintln!("[xcap] Capture error: {}", e);
                            std::thread::sleep(Duration::from_millis(100));
                        }
                    }

                    // 約30fps
                    std::thread::sleep(Duration::from_millis(33));
                }

                println!("[xcap] Capture stopped, waiting for restart...");
                std::thread::sleep(Duration::from_secs(1));
            }
        });
    }
}
