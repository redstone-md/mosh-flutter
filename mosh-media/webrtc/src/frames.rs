//! The peer's latest decoded frame as RGBA, which mosh-core copies for the
//! call view. Only the newest frame is kept: no backlog, one spare buffer.
//! Frames leave at most at the size the view shows them.
use std::sync::{Arc, Mutex};
use std::time::Instant;

use futures::StreamExt;
use libwebrtc::video_frame::{BoxVideoFrame, VideoBuffer, VideoFormatType};
use libwebrtc::video_stream::native::NativeVideoStream;
use libwebrtc::video_track::RtcVideoTrack;

pub const MAX_RGBA_BYTES: usize = 1920 * 1080 * 4;

/// Frame metadata in the layout mosh-core reads.
#[repr(C)]
#[derive(Clone, Copy, Debug, Default)]
pub struct FrameInfo {
    pub sequence: u64,
    pub width: u32,
    pub height: u32,
    pub rgba_bytes: u32,
    pub age_ms: u32,
}

/// The device pixels a video surface shows; zero means none reported yet.
#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, serde::Deserialize)]
pub struct Surface {
    pub width: u32,
    pub height: u32,
}

impl Surface {
    /// The largest size with the frame's aspect that this surface shows.
    /// Frames are never enlarged, and an unreported surface keeps them whole.
    pub fn fit(self, width: u32, height: u32) -> (u32, u32) {
        if self.width == 0 || self.height == 0 || (width <= self.width && height <= self.height) {
            return (width, height);
        }
        let scale = (f64::from(self.width) / f64::from(width))
            .min(f64::from(self.height) / f64::from(height));
        let side =
            |length: u32, bound: u32| ((f64::from(length) * scale).round() as u32).clamp(1, bound);
        (side(width, self.width), side(height, self.height))
    }
}

#[derive(Clone, Default)]
pub struct Frames(Arc<Mutex<Storage>>);

#[derive(Default)]
struct Storage {
    published: Option<Decoded>,
    spare: Vec<u8>,
    surface: Surface,
}

struct Decoded {
    info: FrameInfo,
    pixels: Vec<u8>,
    received: Instant,
}

impl Frames {
    /// Publishes every frame the peer's track decodes until the track ends.
    pub fn watch(&self, runtime: &tokio::runtime::Handle, track: RtcVideoTrack) {
        let frames = self.clone();
        runtime.spawn(async move {
            let mut stream = NativeVideoStream::new(track);
            while let Some(frame) = stream.next().await {
                frames.store(&frame);
            }
        });
    }

    /// Later frames leave at most at this size.
    pub fn show_at(&self, surface: Surface) {
        if let Ok(mut held) = self.0.lock() {
            held.surface = surface;
        }
    }

    /// Our peers send upright pixels (Android rotates before sending), so
    /// the frame's rotation is always zero. libyuv scales the I420 down to
    /// the surface before the RGBA conversion.
    fn store(&self, frame: &BoxVideoFrame) {
        let Ok(surface) = self.0.lock().map(|held| held.surface) else {
            return;
        };
        let source = (frame.buffer.width(), frame.buffer.height());
        let (width, height) = surface.fit(source.0, source.1);
        let scaled = ((width, height) != source)
            .then(|| frame.buffer.to_i420().scale(width as i32, height as i32));
        let buffer: &dyn VideoBuffer = match &scaled {
            Some(scaled) => scaled,
            None => &*frame.buffer,
        };
        self.publish(width, height, Instant::now(), |pixels| {
            buffer.to_argb(
                VideoFormatType::ABGR,
                pixels,
                width * 4,
                width as i32,
                height as i32,
            );
        });
    }

    /// False, keeping the last frame, when the frame exceeds the ABI's bounds.
    fn publish(
        &self,
        width: u32,
        height: u32,
        received: Instant,
        convert: impl FnOnce(&mut [u8]),
    ) -> bool {
        let Some(length) = rgba_length(width, height) else {
            return false;
        };
        let Ok(mut held) = self.0.lock() else {
            return false;
        };
        let mut pixels = std::mem::take(&mut held.spare);
        pixels.resize(length, 0);
        convert(&mut pixels);
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

    /// The ABI status: 1 with the frame copied, 2 when `pixels` is too small
    /// (`info` then holds the size needed), 0 when nothing newer than
    /// `after` exists, -1 when the store is poisoned.
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

/// The packed RGBA size of a frame within the ABI's bounds.
pub fn rgba_length(width: u32, height: u32) -> Option<usize> {
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

    fn store(frames: &Frames, value: u8) -> bool {
        frames.publish(16, 16, Instant::now(), |pixels| pixels.fill(value))
    }

    #[test]
    fn surfaces_shrink_frames_to_fit_with_their_aspect_and_never_enlarge() {
        let surface = |width, height| Surface { width, height };
        assert_eq!(surface(320, 180).fit(1280, 720), (320, 180));
        assert_eq!(surface(320, 320).fit(1280, 720), (320, 180));
        assert_eq!(surface(1000, 180).fit(1280, 720), (320, 180));
        assert_eq!(surface(180, 320).fit(720, 1280), (180, 320));
        assert_eq!(surface(333, 1000).fit(1280, 720), (333, 187));
        assert_eq!(surface(1920, 1080).fit(1280, 720), (1280, 720));
        assert_eq!(surface(1, 1).fit(1280, 720), (1, 1));
        assert_eq!(Surface::default().fit(1280, 720), (1280, 720));
        assert_eq!(surface(320, 0).fit(1280, 720), (1280, 720));
    }

    #[test]
    fn copies_the_latest_frame_once_per_sequence_without_a_backlog() {
        let frames = Frames::default();
        let mut pixels = [0; 16 * 16 * 4];
        let mut info = FrameInfo::default();
        assert_eq!(frames.copy(0, &mut pixels, &mut info), 0);
        assert!(store(&frames, 25));
        assert!(store(&frames, 180));
        assert_eq!(frames.copy(0, &mut pixels, &mut info), 1);
        assert_eq!(
            (info.sequence, info.width, info.height, info.rgba_bytes),
            (2, 16, 16, 1024)
        );
        assert_eq!(pixels[0], 180, "the obsolete frame was overwritten");
        assert_eq!(frames.copy(info.sequence, &mut pixels, &mut info), 0);
    }

    #[test]
    fn short_buffer_reports_required_size_and_preserves_the_frame() {
        let frames = Frames::default();
        assert!(store(&frames, 70));
        let mut info = FrameInfo::default();
        let mut short = [42; 10];
        assert_eq!(frames.copy(0, &mut short, &mut info), 2);
        assert_eq!(info.rgba_bytes, 1024);
        assert_eq!(short, [42; 10]);
    }

    #[test]
    fn oversized_frames_keep_the_last_complete_frame() {
        let frames = Frames::default();
        assert!(store(&frames, 70));
        assert!(!frames.publish(3840, 2160, Instant::now(), |pixels| pixels.fill(1)));
        let mut pixels = [0; 1024];
        let mut info = FrameInfo::default();
        assert_eq!(frames.copy(0, &mut pixels, &mut info), 1);
        assert_eq!((info.sequence, info.width, info.height), (1, 16, 16));
        assert_eq!(pixels, [70; 1024]);
    }
}
