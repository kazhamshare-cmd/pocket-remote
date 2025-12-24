use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};
use tokio::sync::{mpsc, RwLock};
use parking_lot::RwLock as ParkingRwLock;
use parking_lot::Mutex as ParkingMutex;
use rayon::prelude::*;
use webrtc::api::media_engine::MediaEngine;
use webrtc::api::APIBuilder;
use webrtc::api::interceptor_registry::register_default_interceptors;
use webrtc::data_channel::data_channel_message::DataChannelMessage;
use webrtc::data_channel::RTCDataChannel;
use webrtc::ice_transport::ice_server::RTCIceServer;
use webrtc::interceptor::registry::Registry;
use webrtc::peer_connection::configuration::RTCConfiguration;
use webrtc::peer_connection::peer_connection_state::RTCPeerConnectionState;
use webrtc::peer_connection::sdp::session_description::RTCSessionDescription;
use webrtc::peer_connection::RTCPeerConnection;
use scrap::{Capturer, Display};
use std::time::{Duration, Instant};
use std::io::ErrorKind::WouldBlock;
use image::{ImageBuffer, Rgba, DynamicImage};
use bytes::Bytes;
use crate::CaptureRegion;
use crate::h264_encoder::H264Encoder;
use once_cell::sync::Lazy;

/// エンコーディングモード
#[derive(Clone, Copy, PartialEq)]
pub enum EncodingMode {
    Jpeg,
    H264,
}

/// グローバルH.264エンコーダー（スレッドセーフ）
static H264_ENCODER: Lazy<ParkingMutex<Option<H264Encoder>>> = Lazy::new(|| {
    ParkingMutex::new(None)
});

/// 現在のエンコーディングモード
static ENCODING_MODE: Lazy<ParkingRwLock<EncodingMode>> = Lazy::new(|| {
    ParkingRwLock::new(EncodingMode::Jpeg) // JPEGにフォールバック（H.264フラグメント問題回避）
});

/// Data Channel開通時にキーフレームを強制するフラグ
static FORCE_KEYFRAME: AtomicBool = AtomicBool::new(false);

/// キーフレームを強制するフラグをセット
pub fn request_keyframe() {
    FORCE_KEYFRAME.store(true, Ordering::SeqCst);
    println!("[H264] Keyframe requested");
}

/// WebRTC Data Channelを使った低遅延画面共有
pub struct WebRTCScreenShare {
    peer_connection: Arc<RTCPeerConnection>,
    data_channel: Arc<RwLock<Option<Arc<RTCDataChannel>>>>,
    capture_running: Arc<RwLock<bool>>,
    capture_region: Arc<ParkingRwLock<Option<CaptureRegion>>>,
}

impl WebRTCScreenShare {
    pub async fn new(
        ice_candidates_tx: mpsc::Sender<String>,
        capture_region: Arc<ParkingRwLock<Option<CaptureRegion>>>,
    ) -> Result<Self, Box<dyn std::error::Error + Send + Sync>> {
        // メディアエンジン設定
        let mut media_engine = MediaEngine::default();
        media_engine.register_default_codecs()?;

        // インターセプター設定
        let mut registry = Registry::new();
        registry = register_default_interceptors(registry, &mut media_engine)?;

        // API作成
        let api = APIBuilder::new()
            .with_media_engine(media_engine)
            .with_interceptor_registry(registry)
            .build();

        // ICEサーバー設定
        let config = RTCConfiguration {
            ice_servers: vec![
                RTCIceServer {
                    urls: vec!["stun:stun.l.google.com:19302".to_owned()],
                    ..Default::default()
                },
                RTCIceServer {
                    urls: vec!["stun:stun1.l.google.com:19302".to_owned()],
                    ..Default::default()
                },
            ],
            ..Default::default()
        };

        // ピア接続作成
        let peer_connection = Arc::new(api.new_peer_connection(config).await?);
        let data_channel_holder: Arc<RwLock<Option<Arc<RTCDataChannel>>>> = Arc::new(RwLock::new(None));

        // Data Channel作成（順序なし、信頼性なし = UDP的動作）
        let dc_config = webrtc::data_channel::data_channel_init::RTCDataChannelInit {
            ordered: Some(false),        // 順序保証なし
            max_retransmits: Some(0),    // 再送なし
            ..Default::default()
        };

        let data_channel = peer_connection
            .create_data_channel("screen", Some(dc_config))
            .await?;

        // Data Channelを保存
        {
            let mut dc_holder = data_channel_holder.write().await;
            *dc_holder = Some(Arc::clone(&data_channel));
        }

        // Data Channel開通イベント
        let dc_holder_clone = Arc::clone(&data_channel_holder);
        data_channel.on_open(Box::new(move || {
            println!("[WebRTC] Data channel opened!");
            // キーフレームを強制送信（H.264デコーダー初期化のため）
            request_keyframe();
            Box::pin(async {})
        }));

        // ICE候補イベント
        let ice_tx = ice_candidates_tx.clone();
        peer_connection.on_ice_candidate(Box::new(move |candidate| {
            let ice_tx = ice_tx.clone();
            Box::pin(async move {
                if let Some(c) = candidate {
                    if let Ok(json) = c.to_json() {
                        if let Ok(candidate_str) = serde_json::to_string(&json) {
                            println!("[WebRTC] ICE candidate: {}", &candidate_str[..candidate_str.len().min(100)]);
                            ice_tx.send(candidate_str).await.ok();
                        }
                    }
                }
            })
        }));

        // ICE接続状態変更
        peer_connection.on_ice_connection_state_change(Box::new(move |state| {
            println!("[WebRTC] ICE connection state: {:?}", state);
            Box::pin(async {})
        }));

        // 接続状態変更イベント
        peer_connection.on_peer_connection_state_change(Box::new(move |state| {
            println!("[WebRTC] Peer connection state: {:?}", state);
            Box::pin(async {})
        }));

        Ok(Self {
            peer_connection,
            data_channel: data_channel_holder,
            capture_running: Arc::new(RwLock::new(false)),
            capture_region,
        })
    }

    /// オファー作成
    pub async fn create_offer(&self) -> Result<String, Box<dyn std::error::Error + Send + Sync>> {
        let offer = self.peer_connection.create_offer(None).await?;
        self.peer_connection.set_local_description(offer.clone()).await?;
        println!("[WebRTC] Created offer");
        Ok(offer.sdp)
    }

    /// アンサー処理
    pub async fn set_answer(&self, sdp: &str) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
        let answer = RTCSessionDescription::answer(sdp.to_owned())?;
        self.peer_connection.set_remote_description(answer).await?;
        println!("[WebRTC] Set answer");
        Ok(())
    }

    /// ICE候補追加
    pub async fn add_ice_candidate(&self, candidate_json: &str) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
        let candidate: webrtc::ice_transport::ice_candidate::RTCIceCandidateInit =
            serde_json::from_str(candidate_json)?;
        self.peer_connection.add_ice_candidate(candidate).await?;
        println!("[WebRTC] Added ICE candidate");
        Ok(())
    }

    /// 画面キャプチャ開始
    pub async fn start_capture(&self) {
        // 既に実行中なら何もしない
        {
            let mut running = self.capture_running.write().await;
            if *running {
                return;
            }
            *running = true;
        }

        let data_channel = Arc::clone(&self.data_channel);
        let capture_running = Arc::clone(&self.capture_running);
        let capture_region = Arc::clone(&self.capture_region);

        tokio::spawn(async move {
            capture_loop(data_channel, capture_running, capture_region).await;
        });
    }

    /// 接続状態
    pub fn connection_state(&self) -> RTCPeerConnectionState {
        self.peer_connection.connection_state()
    }

    /// 切断
    pub async fn close(&self) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
        {
            let mut running = self.capture_running.write().await;
            *running = false;
        }
        self.peer_connection.close().await?;
        println!("[WebRTC] Connection closed");
        Ok(())
    }
}

/// 画面キャプチャループ
async fn capture_loop(
    data_channel: Arc<RwLock<Option<Arc<RTCDataChannel>>>>,
    capture_running: Arc<RwLock<bool>>,
    capture_region: Arc<ParkingRwLock<Option<CaptureRegion>>>,
) {
    // Data Channelの参照を事前に取得（キャッシュ）
    let cached_dc = {
        let dc_guard = data_channel.read().await;
        dc_guard.clone()
    };

    // キャプチャスレッドで実行
    let result = tokio::task::spawn_blocking(move || {
        let rt = tokio::runtime::Handle::current();

        // 前のCapturerが解放されるまで待機
        // macOSのDisplay Streamコールバックが完全に終了するまで待機
        // scrapライブラリのquartzバックエンドに競合状態があるため長めに待つ
        println!("[WebRTC] Waiting for system to release display resources (3s)...");
        std::thread::sleep(Duration::from_secs(3));

        // Capturerの作成をリトライ（最大10回、1秒間隔）
        let mut capturer = None;
        for attempt in 1..=10 {
            let display = match Display::primary() {
                Ok(d) => {
                    println!("[WebRTC] Got primary display (attempt {})", attempt);
                    d
                }
                Err(e) => {
                    eprintln!("[WebRTC] Failed to get display (attempt {}): {:?}", attempt, e);
                    std::thread::sleep(Duration::from_millis(1000));
                    continue;
                }
            };

            match Capturer::new(display) {
                Ok(c) => {
                    println!("[WebRTC] Capturer created successfully (attempt {})", attempt);
                    capturer = Some(c);
                    break;
                }
                Err(e) => {
                    eprintln!("[WebRTC] Failed to create capturer (attempt {}): {:?}", attempt, e);
                    std::thread::sleep(Duration::from_millis(1000));
                }
            }
        }

        let mut capturer = match capturer {
            Some(c) => c,
            None => {
                eprintln!("[WebRTC] Failed to create capturer after 5 attempts");
                return;
            }
        };

        let width = capturer.width();
        let height = capturer.height();

        println!("[WebRTC] Starting capture: {}x{}", width, height);

        let target_fps = 30;
        let frame_duration = Duration::from_millis(1000 / target_fps);
        let mut frame_count: u64 = 0;
        let mut last_send_time = Instant::now();
        let mut would_block_count: u32 = 0;

        // Data Channelをローカル変数として保持
        let dc = cached_dc;

        loop {
            // 実行フラグチェック（30フレームごと、または最初のフレーム）
            if frame_count % 30 == 0 {
                let running = rt.block_on(async {
                    *capture_running.read().await
                });
                if !running {
                    break;
                }
            }

            let start = Instant::now();

            match capturer.frame() {
                Ok(frame) => {
                    let capture_time = start.elapsed();

                    // キャプチャ領域を取得
                    let region = capture_region.read().clone();

                    // 領域情報をログ出力（最初の5フレームのみ）
                    if frame_count < 5 {
                        if let Some(ref r) = region {
                            println!("[WebRTC] Region: {}x{} at ({}, {})", r.width, r.height, r.x, r.y);
                        } else {
                            println!("[WebRTC] Region: None (full screen)");
                        }
                    }

                    // フレームをエンコード（JPEG or H.264、複数パケット対応）
                    let encode_start = Instant::now();
                    if let Some(packets) = encode_frame_auto(&frame, width, height, region, frame_count) {
                        let encode_time = encode_start.elapsed();
                        if let Some(ref dc) = dc {
                            // Data Channelが開いているか確認
                            let dc_state = dc.ready_state();
                            if dc_state == webrtc::data_channel::data_channel_state::RTCDataChannelState::Open {
                                let total_size: usize = packets.iter().map(|p| p.len()).sum();
                                let packet_count = packets.len();

                                // 各パケットを送信
                                rt.block_on(async {
                                    for packet in packets {
                                        let data = Bytes::from(packet);
                                        if let Err(e) = dc.send(&data).await {
                                            if frame_count % 30 == 0 {
                                                eprintln!("[WebRTC] Send error: {} (size: {} KB)", e, data.len() / 1024);
                                            }
                                            break;
                                        }
                                    }
                                });

                                frame_count += 1;
                                // 最初の10フレームと、その後は100フレームごとにログ
                                if frame_count <= 10 || frame_count % 100 == 0 {
                                    let elapsed = last_send_time.elapsed();
                                    let fps = if frame_count > 1 { (frame_count as f64) / elapsed.as_secs_f64() } else { 0.0 };
                                    let mode_str = if get_encoding_mode() == EncodingMode::H264 { "H264" } else { "JPEG" };
                                    println!("[WebRTC] Frame {} sent ({} KB, {} packets, {}), {:.1} fps, capture={:?}, encode={:?}",
                                        frame_count, total_size / 1024, packet_count, mode_str, fps, capture_time, encode_time);
                                    if frame_count == 100 {
                                        last_send_time = Instant::now();
                                    }
                                }
                            } else if frame_count == 0 {
                                // 最初のフレームでData Channelが開いていない場合のみログ
                                println!("[WebRTC] Data channel not open yet: {:?}", dc_state);
                            }
                        } else if frame_count == 0 {
                            println!("[WebRTC] Data channel not available");
                        }
                    }
                }
                Err(ref e) if e.kind() == WouldBlock => {
                    // フレーム準備中 - 短いスリープで待機
                    would_block_count += 1;
                    if would_block_count == 100 || would_block_count % 1000 == 0 {
                        println!("[WebRTC] WouldBlock count: {}", would_block_count);
                    }
                    // WouldBlockの場合は短いスリープで次のフレームを待つ
                    std::thread::sleep(Duration::from_millis(5));
                    continue;
                }
                Err(e) => {
                    eprintln!("[WebRTC] Capture error: {}", e);
                    break;
                }
            }

            // フレームレート制御
            let elapsed = start.elapsed();
            if elapsed < frame_duration {
                std::thread::sleep(frame_duration - elapsed);
            }
        }

        println!("[WebRTC] Capture loop ended");
    }).await;

    if let Err(e) = result {
        eprintln!("[WebRTC] Capture task error: {:?}", e);
    }
}

/// フレームエンコード（JPEG、ビューポート・画質モード対応）
fn encode_frame(bgra: &[u8], width: usize, height: usize, region: Option<CaptureRegion>, frame_count: u64) -> Option<Vec<u8>> {
    let should_log = frame_count < 5;
    let encode_start = std::time::Instant::now();
    let bytes_per_pixel = 4;

    // macOS IOSurfaceは128バイトアライメントを使用
    let row_bytes = width * bytes_per_pixel;
    let alignment = 128;
    let actual_stride = ((row_bytes + alignment - 1) / alignment) * alignment;

    let expected_len = actual_stride * height;
    if bgra.len() < expected_len {
        eprintln!("[WebRTC] encode_frame: buffer too small: {} < {}", bgra.len(), expected_len);
        return None;
    }

    // ウィンドウ領域をそのままクロップ（シンプル化）
    let (crop_x, crop_y, crop_w, crop_h) = match &region {
        Some(r) => {
            // ウィンドウ座標をクロップ
            let x = (r.x as usize).min(width.saturating_sub(1));
            let y = (r.y as usize).min(height.saturating_sub(1));
            let w = (r.width as usize).min(width.saturating_sub(x));
            let h = (r.height as usize).min(height.saturating_sub(y));

            (x, y, w, h)
        }
        None => (0, 0, width, height),
    };

    // 常に高画質モード（シンプル化）
    let is_low_quality = false;

    // サイズが有効か確認
    if crop_w == 0 || crop_h == 0 {
        eprintln!("[WebRTC] encode_frame: invalid crop size: {}x{}", crop_w, crop_h);
        return None;
    }

    // BGRAからRGBAに変換（切り抜き領域のみ、rayon並列化版）
    let rgba_size = crop_w * crop_h * 4;
    let mut rgba_data = vec![0u8; rgba_size];
    let row_width = crop_w * 4;

    // 行単位で並列処理
    rgba_data
        .par_chunks_mut(row_width)
        .enumerate()
        .for_each(|(row_idx, dst_row)| {
            let y = crop_y + row_idx;
            let row_start = y * actual_stride + crop_x * bytes_per_pixel;
            let row_end = row_start + crop_w * bytes_per_pixel;

            if row_end <= bgra.len() {
                let src_row = &bgra[row_start..row_end];
                for (dst_chunk, src_chunk) in dst_row.chunks_exact_mut(4).zip(src_row.chunks_exact(4)) {
                    dst_chunk[0] = src_chunk[2]; // R (from B)
                    dst_chunk[1] = src_chunk[1]; // G
                    dst_chunk[2] = src_chunk[0]; // B (from R)
                    dst_chunk[3] = 255;          // A
                }
            }
        });

    if rgba_data.len() != crop_w * crop_h * 4 {
        return None;
    }

    let convert_time = encode_start.elapsed();

    let img: ImageBuffer<Rgba<u8>, _> = ImageBuffer::from_raw(
        crop_w as u32,
        crop_h as u32,
        rgba_data,
    )?;

    let dynamic_img = DynamicImage::ImageRgba8(img);

    // ウィンドウサイズに応じてスケールを決定（64KB制限内で高速化）
    let pixel_count = crop_w * crop_h;
    let (scale, start_quality) = if pixel_count <= 150000 {
        // ~400x375以下 → フルサイズ、高品質
        if should_log {
            println!("[WebRTC] XSmall window {}x{} ({}px) → full size, 80% quality", crop_w, crop_h, pixel_count);
        }
        (1, 80u8)
    } else if pixel_count <= 300000 {
        // ~600x500以下 → フルサイズ、中品質
        if should_log {
            println!("[WebRTC] Small window {}x{} ({}px) → full size, 65% quality", crop_w, crop_h, pixel_count);
        }
        (1, 65u8)
    } else if pixel_count <= 600000 {
        // ~800x750以下 → 1/2サイズ
        if should_log {
            println!("[WebRTC] Medium window {}x{} ({}px) → 1/2 size, 70% quality", crop_w, crop_h, pixel_count);
        }
        (2, 70u8)
    } else {
        // 600,000px以上 → 1/2サイズ
        if should_log {
            println!("[WebRTC] Large window {}x{} ({}px) → 1/2 size, 65% quality", crop_w, crop_h, pixel_count);
        }
        (2, 65u8)
    };

    let new_width = (crop_w / scale) as u32;
    let new_height = (crop_h / scale) as u32;
    if should_log {
        println!("[WebRTC] Sending frame: crop={}x{}, scale=1/{}, final={}x{}", crop_w, crop_h, scale, new_width, new_height);
    }
    let resize_start = std::time::Instant::now();
    let final_img = if scale == 1 {
        dynamic_img
    } else {
        dynamic_img.resize_exact(
            new_width.max(1),
            new_height.max(1),
            image::imageops::FilterType::Nearest,  // 高速リサイズ
        )
    };
    let resize_time = resize_start.elapsed();

    let jpeg_start = std::time::Instant::now();
    // 動的品質調整: 63KB以下になるまで品質を下げる（WebRTC上限64KB）
    let max_size = 63 * 1024;
    let mut quality = start_quality;
    let original_quality = quality;

    loop {
        let mut jpeg_data = Vec::new();
        let encoder = image::codecs::jpeg::JpegEncoder::new_with_quality(&mut jpeg_data, quality);

        if final_img.write_with_encoder(encoder).is_ok() {
            if jpeg_data.len() <= max_size {
                let jpeg_time = jpeg_start.elapsed();
                if should_log {
                    println!("[WebRTC] Timing: convert={:?}, resize={:?}, jpeg={:?}, total={:?}",
                        convert_time, resize_time, jpeg_time, encode_start.elapsed());
                    if quality < original_quality {
                        println!("[WebRTC] Quality adjusted: {}% → {}%, size: {} KB", original_quality, quality, jpeg_data.len() / 1024);
                    }
                }
                return Some(jpeg_data);
            }
            // 品質が最低でもサイズオーバーの場合はフレームをスキップ
            if quality <= 10 {
                eprintln!("[WebRTC] Frame too large even at {}% quality ({} KB), skipping", quality, jpeg_data.len() / 1024);
                return None;
            }
            quality = quality.saturating_sub(5); // 5%刻みで細かく調整
        } else {
            return None;
        }
    }
}

/// エンコーディングモードを設定
pub fn set_encoding_mode(mode: EncodingMode) {
    let mut current_mode = ENCODING_MODE.write();
    *current_mode = mode;
    println!("[WebRTC] Encoding mode set to: {:?}",
        match mode {
            EncodingMode::Jpeg => "JPEG",
            EncodingMode::H264 => "H.264",
        });
}

/// 現在のエンコーディングモードを取得
pub fn get_encoding_mode() -> EncodingMode {
    *ENCODING_MODE.read()
}

/// H.264でフレームをエンコード（BGRAデータを直接受け取る）
/// Data Channelの64KB制限に対応するため、フラグメントに分割して返す
fn encode_frame_h264(bgra_data: &[u8], width: u32, height: u32, frame_count: u64) -> Option<Vec<Vec<u8>>> {
    let should_log = frame_count < 10 || frame_count % 100 == 0;

    // H.264エンコーダーを取得または作成
    let mut encoder_guard = H264_ENCODER.lock();
    if encoder_guard.is_none() {
        match H264Encoder::new(width, height) {
            Ok(encoder) => {
                println!("[H264] Encoder initialized: {}x{}", width, height);
                *encoder_guard = Some(encoder);
            }
            Err(e) => {
                eprintln!("[H264] Failed to create encoder: {}", e);
                return None;
            }
        }
    }

    let encoder = encoder_guard.as_mut()?;

    // キーフレーム強制フラグをチェック
    if FORCE_KEYFRAME.swap(false, Ordering::SeqCst) {
        println!("[H264] Forcing keyframe (Data Channel opened)");
        let _ = encoder.force_keyframe();
    }

    // H.264エンコード（BGRAを直接渡す）
    let encode_start = Instant::now();
    let h264_data = match encoder.encode_bgra(bgra_data, width, height) {
        Ok(data) => data,
        Err(e) => {
            if should_log {
                eprintln!("[H264] Encode error: {}", e);
            }
            return None;
        }
    };

    if should_log {
        println!("[H264] Encoded frame {}: {} bytes in {:?}",
            frame_count, h264_data.len(), encode_start.elapsed());
    }

    // 空のフレーム（Pフレームでスキップされた場合など）
    if h264_data.is_empty() {
        return Some(vec![]);
    }

    // WebRTC Data Channelの制限（flutter_webrtcは16KB制限の可能性）
    let max_packet_size = 15 * 1024; // 15KB（WebRTC安全圏）
    if h264_data.len() <= max_packet_size {
        // ヘッダー: [0x01] = H.264 single packet
        let mut packet = Vec::with_capacity(h264_data.len() + 1);
        packet.push(0x01); // H.264 single packet marker
        packet.extend_from_slice(&h264_data);
        return Some(vec![packet]);
    }

    // 大きいフレームはフラグメントに分割
    // ヘッダー: [0x02, fragment_index, total_fragments, frame_id(2bytes)]
    let frame_id = (frame_count & 0xFFFF) as u16;
    let total_fragments = ((h264_data.len() + max_packet_size - 1) / max_packet_size) as u8;
    let mut fragments = Vec::new();

    for (i, chunk) in h264_data.chunks(max_packet_size).enumerate() {
        let mut packet = Vec::with_capacity(chunk.len() + 5);
        packet.push(0x02); // H.264 fragment marker
        packet.push(i as u8); // fragment index
        packet.push(total_fragments); // total fragments
        packet.extend_from_slice(&frame_id.to_be_bytes()); // frame ID
        packet.extend_from_slice(chunk);
        fragments.push(packet);
    }

    if should_log && fragments.len() > 1 {
        println!("[H264] Frame fragmented into {} packets", fragments.len());
    }

    Some(fragments)
}

/// 統合エンコード関数（モードに応じてJPEGまたはH.264を使用）
pub fn encode_frame_auto(
    bgra: &[u8],
    width: usize,
    height: usize,
    region: Option<CaptureRegion>,
    frame_count: u64
) -> Option<Vec<Vec<u8>>> {
    let mode = get_encoding_mode();

    match mode {
        EncodingMode::Jpeg => {
            // JPEG: 1パケットで返す
            encode_frame(bgra, width, height, region, frame_count)
                .map(|data| {
                    // ヘッダー: [0x00] = JPEG packet
                    let mut packet = Vec::with_capacity(data.len() + 1);
                    packet.push(0x00); // JPEG marker
                    packet.extend_from_slice(&data);
                    vec![packet]
                })
        }
        EncodingMode::H264 => {
            // クロップしてBGRAデータを抽出
            let (crop_x, crop_y, crop_w, crop_h) = match &region {
                Some(r) => {
                    let x = (r.x as usize).min(width.saturating_sub(1));
                    let y = (r.y as usize).min(height.saturating_sub(1));
                    let w = (r.width as usize).min(width.saturating_sub(x));
                    let h = (r.height as usize).min(height.saturating_sub(y));
                    (x, y, w, h)
                }
                None => (0, 0, width, height),
            };

            if crop_w == 0 || crop_h == 0 {
                return None;
            }

            // macOS IOSurfaceは128バイトアライメントを使用
            let bytes_per_pixel = 4;
            let row_bytes = width * bytes_per_pixel;
            let alignment = 128;
            let actual_stride = ((row_bytes + alignment - 1) / alignment) * alignment;

            // BGRAデータを抽出（クロップ領域のみ）
            let mut bgra_data = Vec::with_capacity(crop_w * crop_h * 4);
            for y in crop_y..(crop_y + crop_h) {
                let row_start = y * actual_stride + crop_x * bytes_per_pixel;
                let row_end = row_start + crop_w * bytes_per_pixel;
                if row_end <= bgra.len() {
                    bgra_data.extend_from_slice(&bgra[row_start..row_end]);
                }
            }

            encode_frame_h264(&bgra_data, crop_w as u32, crop_h as u32, frame_count)
        }
    }
}
