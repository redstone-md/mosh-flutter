//! Host-owned pixels prove the binary ABI, without serializing image data in logs.
use crate::{ProbeResult, engine::Engine};
use serde_json::{Value, json};

pub const MAX_RGBA_BYTES: usize = 1920 * 1080 * 4;

#[repr(C)]
#[derive(Clone, Copy, Default)]
pub struct FrameInfo {
    pub sequence: u64,
    pub width: u32,
    pub height: u32,
    pub rgba_bytes: u32,
    pub age_ms: u32,
}

pub struct Frames {
    pixels: Vec<u8>,
    sequence: u64,
    copied: u64,
    changed: u64,
    previous_pixel: Option<[u8; 4]>,
    max_age_ms: u32,
}

impl Default for Frames {
    fn default() -> Self {
        Self {
            pixels: vec![0; MAX_RGBA_BYTES],
            sequence: 0,
            copied: 0,
            changed: 0,
            previous_pixel: None,
            max_age_ms: 0,
        }
    }
}

impl Frames {
    pub fn pump(&mut self, engine: &Engine) -> ProbeResult {
        let Some(info) = engine.copy_frame(self.sequence, &mut self.pixels)? else {
            return Ok(());
        };
        let length = (info.width as usize)
            .checked_mul(info.height as usize)
            .and_then(|pixels| pixels.checked_mul(4))
            .ok_or("invalid frame size")?;
        if length == 0
            || length > MAX_RGBA_BYTES
            || length != info.rgba_bytes as usize
            || info.sequence <= self.sequence
        {
            return Err("invalid decoded frame metadata".into());
        }
        let pixel = self.pixels[..4].try_into().unwrap();
        if self.previous_pixel.is_some_and(|old| old != pixel) {
            self.changed += 1;
        }
        self.previous_pixel = Some(pixel);
        self.sequence = info.sequence;
        self.copied += 1;
        self.max_age_ms = self.max_age_ms.max(info.age_ms);
        Ok(())
    }

    pub fn snapshot(&self) -> Value {
        json!({"copied": self.copied, "changing_frames": self.changed,
            "last_sequence": self.sequence, "max_age_ms": self.max_age_ms,
            "maximum_buffer_bytes": MAX_RGBA_BYTES})
    }
}
