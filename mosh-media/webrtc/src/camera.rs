//! Share libwebrtc's libyuv with mosh-core's camera frames: Android's
//! bounded camera adapter and the local preview's scaling.
use crate::frames::{MAX_RGBA_BYTES, Surface, rgba_length};
use crate::video::i420;
use libwebrtc::native::yuv_helper::i420_to_abgr;
use libwebrtc::video_frame::{VideoBuffer, VideoFormatType};
use std::panic::{AssertUnwindSafe, catch_unwind};

/// Converts packed I420 to RGBA (libyuv calls that byte order ABGR).
///
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
        || pixels * 4 > MAX_RGBA_BYTES as u64
        || length as u64 != pixels * 3 / 2
        || capacity as u64 != pixels * 4
    {
        return -1;
    }
    catch_unwind(AssertUnwindSafe(|| {
        // SAFETY: caller retains readable I420 and writable RGBA throughout this
        // conversion. Checked lengths match the exact packed I420 footprint.
        let input = unsafe { std::slice::from_raw_parts(planar, length) };
        let output = unsafe { std::slice::from_raw_parts_mut(rgba, capacity) };
        let luma = pixels as usize;
        let (y, chroma) = input.split_at(luma);
        let (u, v) = chroma.split_at(luma / 4);
        i420_to_abgr(
            y,
            width,
            u,
            width / 2,
            v,
            width / 2,
            output,
            width * 4,
            width as i32,
            height as i32,
        );
        1
    }))
    .unwrap_or(-1)
}

/// Shrinks a packed RGBA frame to fit the surface (`Surface::fit`) through
/// libyuv and writes the result's size. 1 when scaled, 0 when the frame
/// already fits and nothing was written, -1 for invalid input or a short
/// output buffer.
///
/// # Safety
/// `rgba` is readable for `length` bytes, `scaled` exclusively writable for
/// `capacity` bytes, and the size outputs are aligned and writable.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn mosh_media_scale_rgba(
    width: u32,
    height: u32,
    rgba: *const u8,
    length: usize,
    surface: Surface,
    scaled: *mut u8,
    capacity: usize,
    size: *mut [u32; 2],
) -> i32 {
    if rgba.is_null()
        || scaled.is_null()
        || size.is_null()
        || capacity > MAX_RGBA_BYTES
        || rgba_length(width, height) != Some(length)
    {
        return -1;
    }
    let (fitted_width, fitted_height) = surface.fit(width, height);
    if (fitted_width, fitted_height) == (width, height) {
        return 0;
    }
    let needed = fitted_width as usize * fitted_height as usize * 4;
    if capacity < needed {
        return -1;
    }
    catch_unwind(AssertUnwindSafe(|| {
        // SAFETY: the caller retains both disjoint buffers with these lengths
        // and the size output until return.
        let input = unsafe { std::slice::from_raw_parts(rgba, length) };
        let output = unsafe { std::slice::from_raw_parts_mut(scaled, needed) };
        let fitted = i420(width, height, input).scale(fitted_width as i32, fitted_height as i32);
        let fitted: &dyn VideoBuffer = &fitted;
        fitted.to_argb(
            VideoFormatType::ABGR,
            output,
            fitted_width * 4,
            fitted_width as i32,
            fitted_height as i32,
        );
        unsafe { size.write([fitted_width, fitted_height]) };
        1
    }))
    .unwrap_or(-1)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn converts_android_i420_to_owned_rgba_and_rejects_bad_sizes() {
        // Neutral chroma plus black/white luma exercise libyuv's actual converter.
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
            let status = unsafe {
                mosh_media_i420_to_rgba(
                    width,
                    height,
                    input.as_ptr(),
                    length,
                    output.as_mut_ptr(),
                    capacity,
                )
            };
            assert_eq!(status, -1);
        }
    }

    fn scale(
        rgba: &[u8],
        width: u32,
        surface: Surface,
        capacity: usize,
    ) -> (i32, Vec<u8>, [u32; 2]) {
        let mut output = vec![0; capacity];
        let mut size = [0; 2];
        let height = (rgba.len() / 4) as u32 / width;
        // SAFETY: independent buffers with these lengths are retained here.
        let status = unsafe {
            mosh_media_scale_rgba(
                width,
                height,
                rgba.as_ptr(),
                rgba.len(),
                surface,
                output.as_mut_ptr(),
                output.len(),
                &mut size,
            )
        };
        (status, output, size)
    }

    #[test]
    fn scales_rgba_down_to_its_surface_with_libyuv() {
        let red: Vec<u8> = [220, 30, 30, 255].repeat(64 * 36);
        let surface = Surface {
            width: 16,
            height: 16,
        };
        let (status, output, size) = scale(&red, 64, surface, 16 * 16 * 4);
        assert_eq!((status, size), (1, [16, 9]));
        for pixel in output[..16 * 9 * 4].chunks_exact(4) {
            assert!(
                pixel[0] > 200 && pixel[1] < 50 && pixel[3] == 255,
                "{pixel:?}"
            );
        }
        let whole = Surface {
            width: 64,
            height: 64,
        };
        assert_eq!(
            scale(&red, 64, whole, 16).0,
            0,
            "a fitting frame is left as is"
        );
        assert_eq!(scale(&red, 64, Surface::default(), 16).0, 0);
        assert_eq!(
            scale(&red, 64, surface, 16 * 9 * 4 - 1).0,
            -1,
            "short output"
        );
        assert_eq!(scale(&red[1..], 64, surface, 1024).0, -1, "partial frame");
    }
}
