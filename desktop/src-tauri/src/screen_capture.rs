use scrap::{Capturer, Display};
use std::io::ErrorKind::WouldBlock;
use tokio::sync::broadcast;
use image::{ImageBuffer, Rgba, DynamicImage};
use std::time::Duration;
use serde::{Serialize, Deserialize};
use parking_lot::RwLock;
use std::sync::Arc;
use crate::CaptureRegion;

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
    ) {
        std::thread::spawn(move || {
            let display = match Display::primary() {
                Ok(d) => d,
                Err(e) => {
                    eprintln!("Failed to get display: {}", e);
                    return;
                }
            };

            let mut capturer = match Capturer::new(display) {
                Ok(c) => c,
                Err(e) => {
                    eprintln!("Failed to create capturer: {}", e);
                    return;
                }
            };

            let width = capturer.width();
            let height = capturer.height();
            let bytes_per_pixel = 4;

            println!("Capturer dimensions: {}x{}", width, height);

            let mut frame_count: u64 = 0;
            let mut logged_info = false;

            loop {
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

                        // RGBA画像データを作成
                        // macOS scrapはBGRA形式: B=frame[i], G=frame[i+1], R=frame[i+2], A=frame[i+3]
                        let mut rgba_data = Vec::with_capacity(width * height * 4);

                        for y in 0..height {
                            let row_start = y * actual_stride;
                            for x in 0..width {
                                let i = row_start + x * bytes_per_pixel;
                                if i + 3 < frame.len() {
                                    // BGRA → RGBA 変換
                                    rgba_data.push(frame[i + 2]); // R
                                    rgba_data.push(frame[i + 1]); // G
                                    rgba_data.push(frame[i]);     // B
                                    rgba_data.push(frame[i + 3]); // A
                                }
                            }
                        }

                        if rgba_data.len() == width * height * 4 {
                            if let Some(img) = ImageBuffer::<Rgba<u8>, _>::from_raw(
                                width as u32,
                                height as u32,
                                rgba_data,
                            ) {
                                let dynamic_img = DynamicImage::ImageRgba8(img);

                                // キャプチャ領域をチェック
                                let region = capture_region.read().clone();

                                let (final_img, quality) = if let Some(r) = region {
                                    // 領域指定あり: その領域だけをクロップして高品質で送信
                                    let crop_x = (r.x as u32).min(width as u32);
                                    let crop_y = (r.y as u32).min(height as u32);
                                    let crop_w = (r.width as u32).min(width as u32 - crop_x);
                                    let crop_h = (r.height as u32).min(height as u32 - crop_y);

                                    if crop_w > 0 && crop_h > 0 {
                                        let cropped = dynamic_img.crop_imm(crop_x, crop_y, crop_w, crop_h);
                                        // 高解像度モード: 縮小しない、高品質
                                        (cropped, 75u8)
                                    } else {
                                        // 無効な領域の場合は全画面
                                        let new_width = (width / 2) as u32;
                                        let new_height = (height / 2) as u32;
                                        let resized = dynamic_img.resize_exact(
                                            new_width,
                                            new_height,
                                            image::imageops::FilterType::Nearest,
                                        );
                                        (resized, 60u8)
                                    }
                                } else {
                                    // 領域指定なし: 全画面を1/2に縮小
                                    let new_width = (width / 2) as u32;
                                    let new_height = (height / 2) as u32;
                                    let resized = dynamic_img.resize_exact(
                                        new_width,
                                        new_height,
                                        image::imageops::FilterType::Nearest,
                                    );
                                    (resized, 60u8)
                                };

                                // JPEG品質を設定
                                let mut jpeg_data = Vec::new();
                                let encoder = image::codecs::jpeg::JpegEncoder::new_with_quality(
                                    &mut jpeg_data,
                                    quality,
                                );

                                if final_img.write_with_encoder(encoder).is_ok() {
                                    let receivers = tx.receiver_count();
                                    if receivers > 0 {
                                        let jpeg_size = jpeg_data.len();
                                        match tx.send(jpeg_data) {
                                            Ok(_) => {
                                                frame_count += 1;
                                                // フレーム送信成功（最初と100フレームごとに表示）
                                                if frame_count == 1 || frame_count % 100 == 0 {
                                                    println!("Frame {} sent, {} receivers, {} KB",
                                                             frame_count, receivers, jpeg_size / 1024);
                                                }
                                            }
                                            Err(e) => {
                                                eprintln!("Failed to send frame: {}", e);
                                            }
                                        }
                                    }
                                } else {
                                    eprintln!("Failed to encode JPEG");
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

                // 約20fps
                std::thread::sleep(Duration::from_millis(50));
            }
        });
    }
}
