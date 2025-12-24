use openh264::encoder::{Encoder, EncoderConfig};
use openh264::formats::{YUVBuffer, BgraSliceU8};
use std::sync::Mutex;

/// H.264エンコーダー（OpenH264使用）
pub struct H264Encoder {
    encoder: Mutex<Option<Encoder>>,
    width: usize,
    height: usize,
    frame_count: u64,
    keyframe_interval: u64, // キーフレーム間隔（フレーム数）
}

impl H264Encoder {
    /// 新しいH.264エンコーダーを作成
    pub fn new(width: u32, height: u32) -> Result<Self, String> {
        // 幅と高さは2の倍数に調整（YUV420の要件）
        let aligned_width = ((width as usize + 1) & !1).max(2);
        let aligned_height = ((height as usize + 1) & !1).max(2);

        let config = EncoderConfig::new()
            .max_frame_rate(30.0)
            .set_bitrate_bps(5_000_000) // 5 Mbps（最高画質）
            .enable_skip_frame(false); // フレームスキップを無効化

        let encoder = Encoder::with_api_config(openh264::OpenH264API::from_source(), config)
            .map_err(|e| format!("Failed to create H.264 encoder: {:?}", e))?;

        println!("[H264] Encoder created: {}x{} (aligned: {}x{})",
            width, height, aligned_width, aligned_height);

        Ok(Self {
            encoder: Mutex::new(Some(encoder)),
            width: aligned_width,
            height: aligned_height,
            frame_count: 0,
            keyframe_interval: 15, // 0.5秒ごとにキーフレーム（デバッグ用）
        })
    }

    /// BGRAフレームをH.264にエンコード
    /// 返り値: NAL units (H.264 bitstream)
    pub fn encode_bgra(&mut self, bgra_data: &[u8], width: u32, height: u32) -> Result<Vec<u8>, String> {
        // サイズが変わったらエンコーダーを再作成
        let aligned_width = ((width as usize + 1) & !1).max(2);
        let aligned_height = ((height as usize + 1) & !1).max(2);

        if aligned_width != self.width || aligned_height != self.height {
            println!("[H264] Resolution changed: {}x{} -> {}x{}",
                self.width, self.height, aligned_width, aligned_height);

            let config = EncoderConfig::new()
                .max_frame_rate(30.0)
                .set_bitrate_bps(5_000_000) // 5 Mbps（最高画質）
                .enable_skip_frame(false); // フレームスキップを無効化

            let new_encoder = Encoder::with_api_config(openh264::OpenH264API::from_source(), config)
                .map_err(|e| format!("Failed to recreate encoder: {:?}", e))?;

            let mut encoder_lock = self.encoder.lock().unwrap();
            *encoder_lock = Some(new_encoder);
            drop(encoder_lock); // ロックを解放
            self.width = aligned_width;
            self.height = aligned_height;
            self.frame_count = 0; // リセットして最初のフレームでキーフレームを強制
        }

        // BGRAデータをBgraSliceU8でラップしてYUVに変換
        // 実際の幅と高さが2の倍数でない場合はパディングが必要
        let actual_width = width as usize;
        let actual_height = height as usize;

        // 入力データが期待サイズと一致するか確認
        let expected_size = actual_width * actual_height * 4;
        if bgra_data.len() != expected_size {
            return Err(format!(
                "BGRA data size mismatch: expected {} bytes ({}x{}x4), got {} bytes",
                expected_size, actual_width, actual_height, bgra_data.len()
            ));
        }

        // 2の倍数にアラインされたBGRAバッファを作成
        let yuv_buffer = if actual_width == aligned_width && actual_height == aligned_height {
            // サイズが既にアラインされている場合は直接使用
            let bgra_slice = BgraSliceU8::new(bgra_data, (aligned_width, aligned_height));
            YUVBuffer::from_rgb_source(bgra_slice)
        } else {
            // パディングが必要な場合
            let mut padded_bgra = vec![0u8; aligned_width * aligned_height * 4];
            for y in 0..actual_height {
                let src_offset = y * actual_width * 4;
                let dst_offset = y * aligned_width * 4;
                let row_bytes = actual_width * 4;
                padded_bgra[dst_offset..dst_offset + row_bytes]
                    .copy_from_slice(&bgra_data[src_offset..src_offset + row_bytes]);
            }
            let bgra_slice = BgraSliceU8::new(&padded_bgra, (aligned_width, aligned_height));
            YUVBuffer::from_rgb_source(bgra_slice)
        };

        // エンコード
        let mut encoder_lock = self.encoder.lock().unwrap();
        let encoder = encoder_lock.as_mut().ok_or("Encoder not initialized")?;

        // 最初のフレームまたはキーフレーム間隔でIDRフレームを強制
        let is_keyframe = self.frame_count == 0 ||
                          self.frame_count % self.keyframe_interval == 0;
        if is_keyframe {
            encoder.force_intra_frame();
            println!("[H264] Forcing keyframe at frame {}", self.frame_count);
        }

        let bitstream = encoder.encode(&yuv_buffer)
            .map_err(|e| format!("Encode error: {:?}", e))?;

        // NALユニットをVecに変換
        let output = bitstream.to_vec();

        self.frame_count += 1;
        if self.frame_count % 30 == 0 || is_keyframe {
            // NALタイプを確認（デバッグ用）
            let nal_types = parse_nal_types(&output);
            println!("[H264] Encoded frame {}: {} bytes (keyframe: {}, NALs: {:?})",
                self.frame_count, output.len(), is_keyframe, nal_types);
        }

        Ok(output)
    }

    /// キーフレーム（IDRフレーム）を強制的に生成
    pub fn force_keyframe(&mut self) -> Result<(), String> {
        let mut encoder_lock = self.encoder.lock().unwrap();
        if let Some(encoder) = encoder_lock.as_mut() {
            encoder.force_intra_frame();
        }
        Ok(())
    }
}

/// NALユニットのタイプを解析（デバッグ用）
fn parse_nal_types(data: &[u8]) -> Vec<u8> {
    let mut types = Vec::new();
    let mut i = 0;

    while i < data.len().saturating_sub(4) {
        // スタートコードを探す (0x00 0x00 0x00 0x01 or 0x00 0x00 0x01)
        if data[i] == 0x00 && data[i + 1] == 0x00 {
            let nal_start = if data[i + 2] == 0x00 && data[i + 3] == 0x01 {
                i + 4
            } else if data[i + 2] == 0x01 {
                i + 3
            } else {
                i += 1;
                continue;
            };

            if nal_start < data.len() {
                let nal_type = data[nal_start] & 0x1F;
                types.push(nal_type);
            }
            i = nal_start;
        } else {
            i += 1;
        }
    }

    types
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_encoder_creation() {
        let encoder = H264Encoder::new(1920, 1080);
        assert!(encoder.is_ok());
    }

    #[test]
    fn test_encode_frame() {
        let mut encoder = H264Encoder::new(640, 480).unwrap();
        let bgra_data = vec![128u8; 640 * 480 * 4]; // グレー画面
        let result = encoder.encode_bgra(&bgra_data, 640, 480);
        assert!(result.is_ok());
        assert!(!result.unwrap().is_empty());
    }
}
