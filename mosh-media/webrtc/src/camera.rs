//! mosh-core's local preview through libwebrtc's libyuv: a camera frame
//! becomes RGBA once, at the size its surface shows.
use crate::frames::{MAX_RGBA_BYTES, Surface};
use crate::video::i420;
use libwebrtc::video_frame::{VideoBuffer, VideoFormatType};
use std::panic::{AssertUnwindSafe, catch_unwind};

/// Converts a packed I420 camera frame to RGBA, shrunk to fit the surface
/// (`Surface::fit`) first, and writes the result's size. 1 when converted,
/// -1 for an invalid frame or a short output buffer.
///
/// # Safety
/// `planes` is readable for `length` bytes, `rgba` exclusively writable for
/// `capacity` bytes, and the size output is aligned and writable.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn mosh_media_preview_i420(
    width: u32,
    height: u32,
    planes: *const u8,
    length: usize,
    surface: Surface,
    rgba: *mut u8,
    capacity: usize,
    size: *mut [u32; 2],
) -> i32 {
    if planes.is_null()
        || rgba.is_null()
        || size.is_null()
        || length > MAX_RGBA_BYTES
        || capacity > MAX_RGBA_BYTES
    {
        return -1;
    }
    catch_unwind(AssertUnwindSafe(|| {
        // SAFETY: the caller retains the readable frame until return.
        let input = unsafe { std::slice::from_raw_parts(planes, length) };
        let Some(mut frame) = i420(width, height, input) else {
            return -1;
        };
        let (fitted_width, fitted_height) = surface.fit(width, height);
        let needed = fitted_width as usize * fitted_height as usize * 4;
        if capacity < needed {
            return -1;
        }
        if (fitted_width, fitted_height) != (width, height) {
            frame = frame.scale(fitted_width as i32, fitted_height as i32);
        }
        // SAFETY: the caller retains the disjoint writable output, checked
        // to hold the fitted frame, and the size output until return.
        let output = unsafe { std::slice::from_raw_parts_mut(rgba, needed) };
        let fitted: &dyn VideoBuffer = &frame;
        // libyuv names the RGBA byte order ABGR.
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

    /// A frame of one colour as packed I420.
    fn solid(width: usize, height: usize, [y, u, v]: [u8; 3]) -> Vec<u8> {
        let mut planes = vec![y; width * height];
        planes.extend(vec![u; width * height / 4]);
        planes.extend(vec![v; width * height / 4]);
        planes
    }

    fn preview(
        planes: &[u8],
        (width, height): (u32, u32),
        surface: Surface,
        capacity: usize,
    ) -> (i32, Vec<u8>, [u32; 2]) {
        let mut output = vec![0; capacity];
        let mut size = [0; 2];
        // SAFETY: independent buffers with these lengths are retained here.
        let status = unsafe {
            mosh_media_preview_i420(
                width,
                height,
                planes.as_ptr(),
                planes.len(),
                surface,
                output.as_mut_ptr(),
                output.len(),
                &mut size,
            )
        };
        (status, output, size)
    }

    #[test]
    fn a_frame_that_fits_its_surface_becomes_rgba_whole() {
        // Black and white luma with neutral chroma, in BT.601 video range.
        let planes = [16, 16, 235, 235, 128, 128];
        let (status, output, size) = preview(&planes, (2, 2), Surface::default(), 16);
        assert_eq!((status, size), (1, [2, 2]));
        assert!(output[..3].iter().all(|channel| *channel <= 1));
        assert!(output[8..11].iter().all(|channel| *channel >= 254));
        assert_eq!([output[3], output[15]], [255, 255]);
    }

    #[test]
    fn a_larger_frame_is_shrunk_to_its_surface_with_its_colours() {
        // BT.601 video range for RGB (220, 30, 30).
        let red = solid(64, 36, [91, 100, 211]);
        let surface = Surface {
            width: 16,
            height: 16,
        };
        let (status, output, size) = preview(&red, (64, 36), surface, 16 * 16 * 4);
        assert_eq!((status, size), (1, [16, 9]));
        for pixel in output[..16 * 9 * 4].chunks_exact(4) {
            assert!(
                pixel[0] > 200 && pixel[1] < 50 && pixel[2] < 50 && pixel[3] == 255,
                "{pixel:?}"
            );
        }
        assert_eq!(
            preview(&red, (64, 36), surface, 16 * 9 * 4 - 1).0,
            -1,
            "short output"
        );
    }

    #[test]
    fn frames_that_are_not_packed_i420_are_rejected() {
        let planes = solid(2, 2, [16, 128, 128]);
        for (width, height, length) in
            [(2, 2, 5), (0, 2, 6), (3, 2, 6), (2, 3, 6), (u32::MAX, 2, 6)]
        {
            let (status, ..) = preview(&planes[..length], (width, height), Surface::default(), 64);
            assert_eq!(status, -1, "{width}x{height} in {length} bytes");
        }
    }
}
