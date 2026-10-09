// Latest decoded RGBA plus one conversion buffer; no native frames or backlog.
use ringrtc::webrtc::media::VideoFrame;
use std::sync::Mutex;
use std::time::Instant;

pub const MAX_RGBA_BYTES: usize = 1920 * 1080 * 4;

#[repr(C)]
#[derive(Clone, Copy, Debug, Default)]
pub struct FrameInfo {
    pub sequence: u64,
    pub width: u32,
    pub height: u32,
    pub rgba_bytes: u32,
    pub age_ms: u32,
}

#[derive(Default)]
pub struct Frames(Mutex<Storage>);

#[derive(Default)]
struct Storage {
    published: Option<Decoded>,
    spare: Vec<u8>,
}

struct Decoded {
    info: FrameInfo,
    pixels: Vec<u8>,
    received: Instant,
}

impl std::fmt::Debug for Frames {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("Frames")
            .field("maximum_frame_bytes", &MAX_RGBA_BYTES)
            .finish_non_exhaustive()
    }
}

impl Frames {
    pub fn store(&self, frame: VideoFrame) -> bool {
        let received = Instant::now();
        if rgba_length(frame.width(), frame.height()).is_none() {
            return false;
        }
        let frame = frame.apply_rotation();
        self.publish(frame.width(), frame.height(), received, |pixels| {
            frame.to_rgba(pixels)
        })
    }

    fn publish(
        &self,
        width: u32,
        height: u32,
        received: Instant,
        convert: impl FnOnce(&mut [u8]) -> bool,
    ) -> bool {
        let Some(length) = rgba_length(width, height) else {
            return false;
        };
        let Ok(mut held) = self.0.lock() else {
            return false;
        };
        let mut pixels = std::mem::take(&mut held.spare);
        pixels.resize(length, 0);
        if !convert(&mut pixels) {
            held.spare = pixels;
            return false;
        }
        let sequence = held
            .published
            .as_ref()
            .map_or(1, |slot| slot.info.sequence.saturating_add(1));
        let info = FrameInfo {
            sequence,
            width,
            height,
            rgba_bytes: length as u32,
            age_ms: 0,
        };
        let previous = held.published.replace(Decoded {
            info,
            pixels,
            received,
        });
        held.spare = previous.map(|slot| slot.pixels).unwrap_or_default();
        true
    }

    pub fn copy(&self, after: u64, pixels: &mut [u8], info: &mut FrameInfo) -> i32 {
        let Ok(held) = self.0.lock() else {
            return -1;
        };
        let Some(slot) = held
            .published
            .as_ref()
            .filter(|slot| slot.info.sequence > after)
        else {
            return 0;
        };
        *info = slot.info;
        info.age_ms = slot
            .received
            .elapsed()
            .as_millis()
            .min(u128::from(u32::MAX)) as u32;
        if pixels.len() < slot.pixels.len() {
            return 2;
        }
        pixels[..slot.pixels.len()].copy_from_slice(&slot.pixels);
        1
    }
}

fn rgba_length(width: u32, height: u32) -> Option<usize> {
    if width == 0 || height == 0 || width > 1920 || height > 1920 {
        return None;
    }
    let length = (width as usize)
        .checked_mul(height as usize)?
        .checked_mul(4)?;
    (length <= MAX_RGBA_BYTES).then_some(length)
}

#[cfg(test)]
mod tests {
    use super::*;
    use ringrtc::webrtc::media::VideoPixelFormat;

    fn frame(value: u8) -> VideoFrame {
        VideoFrame::copy_from_slice(16, 16, VideoPixelFormat::Rgba, &[value; 16 * 16 * 4])
    }

    #[test]
    fn copies_the_latest_frame_once_per_sequence_without_a_backlog() {
        let frames = Frames::default();
        let mut pixels = [0; 16 * 16 * 4];
        let mut info = FrameInfo::default();
        assert_eq!(frames.copy(0, &mut pixels, &mut info), 0);
        assert!(frames.store(frame(25)));
        assert!(frames.store(frame(180)));
        assert_eq!(frames.copy(0, &mut pixels, &mut info), 1);
        assert_eq!(
            (info.sequence, info.width, info.height, info.rgba_bytes),
            (2, 16, 16, 1024)
        );
        assert!(pixels[0] > 150, "the obsolete frame was overwritten");
        assert_eq!(pixels[3], 255);
        assert_eq!(frames.copy(info.sequence, &mut pixels, &mut info), 0);
    }

    #[test]
    fn short_buffer_reports_required_size_and_preserves_the_frame() {
        let frames = Frames::default();
        assert!(frames.store(frame(70)));
        let mut info = FrameInfo::default();
        let mut short = [42; 10];
        assert_eq!(frames.copy(0, &mut short, &mut info), 2);
        assert_eq!(info.rgba_bytes, 1024);
        assert_eq!(short, [42; 10]);
        let mut pixels = [0; 1024];
        assert_eq!(frames.copy(0, &mut pixels, &mut info), 1);
        assert!(pixels[0] > 50);
    }

    #[test]
    fn bounds_landscape_portrait_and_invalid_dimensions_before_native_copy() {
        assert_eq!(rgba_length(1920, 1080), Some(MAX_RGBA_BYTES));
        assert_eq!(rgba_length(1080, 1920), Some(MAX_RGBA_BYTES));
        for (width, height) in [
            (0, 720),
            (1280, 0),
            (1920, 1920),
            (3840, 2160),
            (u32::MAX, 1),
        ] {
            assert_eq!(rgba_length(width, height), None);
        }
    }

    #[test]
    fn failed_conversion_preserves_the_last_complete_frame_and_dimensions() {
        let frames = Frames::default();
        assert!(frames.store(frame(70)));
        let mut expected = [0; 1024];
        let mut info = FrameInfo::default();
        assert_eq!(frames.copy(0, &mut expected, &mut info), 1);
        assert!(!frames.publish(8, 8, Instant::now(), |pixels| {
            pixels.fill(42);
            false
        }));
        let mut actual = [0; 1024];
        assert_eq!(frames.copy(0, &mut actual, &mut info), 1);
        assert_eq!((info.width, info.height), (16, 16));
        assert_eq!(actual, expected);
    }
}
