use std::sync::Arc;
use tokio::sync::{mpsc, RwLock};
use parking_lot::RwLock as ParkingRwLock;
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
    // キャプチャスレッドで実行
    let result = tokio::task::spawn_blocking(move || {
        let rt = tokio::runtime::Handle::current();

        let display = match Display::primary() {
            Ok(d) => d,
            Err(e) => {
                eprintln!("[WebRTC] Failed to get display: {}", e);
                return;
            }
        };

        let mut capturer = match Capturer::new(display) {
            Ok(c) => c,
            Err(e) => {
                eprintln!("[WebRTC] Failed to create capturer: {}", e);
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

        loop {
            // 実行フラグチェック
            let running = rt.block_on(async {
                *capture_running.read().await
            });
            if !running {
                break;
            }

            let start = Instant::now();

            match capturer.frame() {
                Ok(frame) => {
                    // キャプチャ領域を取得
                    let region = capture_region.read().clone();

                    // フレームをエンコード
                    if let Some(encoded) = encode_frame(&frame, width, height, region) {
                        // Data Channelで送信
                        let dc_opt = rt.block_on(async {
                            data_channel.read().await.clone()
                        });

                        if let Some(dc) = dc_opt {
                            // Data Channelが開いているか確認
                            if dc.ready_state() == webrtc::data_channel::data_channel_state::RTCDataChannelState::Open {
                                let data = Bytes::from(encoded);
                                let data_len = data.len();

                                // 送信（ブロッキング、安定性重視）
                                rt.block_on(async {
                                    if let Err(e) = dc.send(&data).await {
                                        if frame_count % 30 == 0 {
                                            eprintln!("[WebRTC] Send error: {} (size: {} KB)", e, data_len / 1024);
                                        }
                                    }
                                });

                                frame_count += 1;
                                // 最初の10フレームと、その後は100フレームごとにログ
                                if frame_count <= 10 || frame_count % 100 == 0 {
                                    let elapsed = last_send_time.elapsed();
                                    let fps = if frame_count > 1 { (frame_count as f64) / elapsed.as_secs_f64() } else { 0.0 };
                                    println!("[WebRTC] Frame {} sent ({} KB), {:.1} fps", frame_count, data_len / 1024, fps);
                                    if frame_count == 100 {
                                        last_send_time = Instant::now();
                                    }
                                }
                            }
                        }
                    }
                }
                Err(ref e) if e.kind() == WouldBlock => {
                    // フレーム準備中
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

/// フレームエンコード（JPEG、低品質・高速）
fn encode_frame(bgra: &[u8], width: usize, height: usize, region: Option<CaptureRegion>) -> Option<Vec<u8>> {
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

    // 選択領域があれば切り抜き、なければ全画面（領域指定は現在無効化）
    let (crop_x, crop_y, crop_w, crop_h, is_region) = (0, 0, width, height, false);
    let _ = region; // 未使用警告を抑制

    // サイズが有効か確認
    if crop_w == 0 || crop_h == 0 {
        eprintln!("[WebRTC] encode_frame: invalid crop size: {}x{}", crop_w, crop_h);
        return None;
    }

    // BGRAからRGBAに変換（切り抜き領域のみ）
    let mut rgba_data = Vec::with_capacity(crop_w * crop_h * 4);
    for y in crop_y..(crop_y + crop_h) {
        let row_start = y * actual_stride;
        for x in crop_x..(crop_x + crop_w) {
            let src = row_start + x * bytes_per_pixel;
            if src + 3 < bgra.len() {
                rgba_data.push(bgra[src + 2]);     // R
                rgba_data.push(bgra[src + 1]);     // G
                rgba_data.push(bgra[src]);         // B
                rgba_data.push(255);               // A
            }
        }
    }

    if rgba_data.len() != crop_w * crop_h * 4 {
        return None;
    }

    let img: ImageBuffer<Rgba<u8>, _> = ImageBuffer::from_raw(
        crop_w as u32,
        crop_h as u32,
        rgba_data,
    )?;

    let dynamic_img = DynamicImage::ImageRgba8(img);

    // 1/2サイズに縮小（画質向上）
    let _ = is_region; // 未使用警告を抑制
    let new_width = (crop_w / 2) as u32;
    let new_height = (crop_h / 2) as u32;
    let quality = 50u8;

    let final_img = dynamic_img.resize_exact(
        new_width.max(1),
        new_height.max(1),
        image::imageops::FilterType::Triangle,
    );

    // JPEGエンコード
    let mut jpeg_data = Vec::new();
    let encoder = image::codecs::jpeg::JpegEncoder::new_with_quality(&mut jpeg_data, quality);

    if final_img.write_with_encoder(encoder).is_ok() {
        Some(jpeg_data)
    } else {
        None
    }
}
