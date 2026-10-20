//! Share WebRTC/libyuv's pixel conversion with Android's bounded camera adapter.
use ringrtc::webrtc::media::{VideoFrame, VideoPixelFormat};
use std::panic::{AssertUnwindSafe, catch_unwind};

/// # Safety
/// Planar and RGBA are retained, disjoint buffers with the declared lengths.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn mosh_media_i420_to_rgba(
    width: u32,
    height: u32,
    planar: *const u8,
    length: usize,
    rgba: *mut u8,
    capacity: usize,
) -> i32 {
    let pixels = u64::from(width) * u64::from(height);
    if planar.is_null()
        || rgba.is_null()
        || width == 0
        || height == 0
        || width > 1920
        || height > 1920
        || !width.is_multiple_of(2)
        || !height.is_multiple_of(2)
        || pixels * 4 > crate::frames::MAX_RGBA_BYTES as u64
        || length as u64 != pixels * 3 / 2
        || capacity as u64 != pixels * 4
    {
        return -1;
    }
    catch_unwind(AssertUnwindSafe(|| {
        // SAFETY: caller retains readable I420 and writable RGBA throughout this
        // conversion. Checked lengths match the exact WebRTC format footprint.
        let input = unsafe { std::slice::from_raw_parts(planar, length) };
        let output = unsafe { std::slice::from_raw_parts_mut(rgba, capacity) };
        let frame = VideoFrame::copy_from_slice(width, height, VideoPixelFormat::I420, input);
        i32::from(frame.to_rgba(output))
    }))
    .unwrap_or(-1)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn converts_android_i420_to_owned_rgba_and_rejects_bad_sizes() {
        // Neutral chroma plus black/white luma exercise WebRTC's actual converter.
        let input = [16, 16, 235, 235, 128, 128];
        let mut output = [0; 16];
        // SAFETY: independent exact-sized packed input/output are retained here.
        assert_eq!(
            unsafe { mosh_media_i420_to_rgba(2, 2, input.as_ptr(), 6, output.as_mut_ptr(), 16) },
            1
        );
        assert!(output[..3].iter().all(|channel| *channel <= 1));
        assert!(output[8..11].iter().all(|channel| *channel >= 254));
        assert_eq!(output[3], 255);
        assert_eq!(output[15], 255);
        for (width, height, length, capacity) in [
            (2, 2, 5, 16),
            (2, 2, 6, 15),
            (0, 2, 6, 16),
            (3, 2, 6, 16),
            (u32::MAX, 2, 6, 16),
        ] {
            // SAFETY: invalid declared dimensions are rejected before buffer access.
            assert_eq!(
                unsafe {
                    mosh_media_i420_to_rgba(
                        width,
                        height,
                        input.as_ptr(),
                        length,
                        output.as_mut_ptr(),
                        capacity,
                    )
                },
                -1
            );
        }
    }
}
