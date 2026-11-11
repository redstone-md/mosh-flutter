//! Camera frames as the call engine encodes them: packed I420 (the Y plane,
//! then U, then V, rows unpadded) in BT.601 video range. Every native camera
//! format becomes that here, without passing through RGBA.
use crate::jpeg;
use anyhow::Context;
use nokhwa::utils::FrameFormat;

/// The packed I420 size of a frame the engine takes; none for odd or
/// oversized sides.
pub fn size(width: u32, height: u32) -> Option<usize> {
    let pixels = u64::from(width) * u64::from(height);
    (width > 0
        && height > 0
        && width <= 1920
        && height <= 1920
        && width.is_multiple_of(2)
        && height.is_multiple_of(2)
        && pixels <= 1920 * 1080)
        .then(|| pixels as usize * 3 / 2)
}

/// A converted frame, borrowed from its converter until the next one.
pub struct Picture<'a> {
    pub width: u32,
    pub height: u32,
    pub planes: &'a [u8],
}

/// Converts camera frames into one reused buffer, so a steady stream
/// allocates nothing per frame.
#[derive(Default)]
pub struct Converter {
    planes: Vec<u8>,
    jpeg: jpeg::Decoder,
}

impl Converter {
    /// `data` is one frame as the camera delivered it. A JPEG carries its own
    /// size; the other formats are exactly `width` by `height` unpadded rows.
    pub fn convert(
        &mut self,
        format: FrameFormat,
        (width, height): (u32, u32),
        data: &[u8],
    ) -> anyhow::Result<Picture<'_>> {
        let (width, height) = if format == FrameFormat::MJPEG {
            self.jpeg.decode(data, &mut self.planes)?
        } else {
            let length = size(width, height).context("camera frame too large or odd-sized")?;
            self.planes.resize(length, 0);
            let (w, h) = (width as usize, height as usize);
            let converted = match format {
                FrameFormat::NV12 => nv12(data, w * h, &mut self.planes),
                FrameFormat::YUYV => yuyv(data, w, &mut self.planes),
                FrameFormat::RAWRGB => rgb(data, w, [0, 1, 2], &mut self.planes),
                FrameFormat::RAWBGR => rgb(data, w, [2, 1, 0], &mut self.planes),
                _ => anyhow::bail!("unsupported camera format {format}"),
            };
            converted.with_context(|| format!("{format} camera frame of the wrong length"))?;
            (width, height)
        };
        Ok(Picture {
            width,
            height,
            planes: &self.planes,
        })
    }
}

/// NV12 differs only in its chroma, one plane of interleaved U and V.
fn nv12(source: &[u8], luma: usize, planes: &mut [u8]) -> Option<()> {
    if source.len() != planes.len() {
        return None;
    }
    let (y, chroma) = planes.split_at_mut(luma);
    y.copy_from_slice(&source[..luma]);
    let (u, v) = chroma.split_at_mut(luma / 4);
    for ((pair, u), v) in source[luma..].chunks_exact(2).zip(u).zip(v) {
        (*u, *v) = (pair[0], pair[1]);
    }
    Some(())
}

/// YUYV packs two pixels as Y0 U Y1 V with chroma on every row; each I420
/// chroma sample averages the two rows it covers.
fn yuyv(source: &[u8], width: usize, planes: &mut [u8]) -> Option<()> {
    let luma = planes.len() / 3 * 2;
    if source.len() != luma * 2 {
        return None;
    }
    let (y, chroma) = planes.split_at_mut(luma);
    for (y, packed) in y.chunks_exact_mut(2).zip(source.chunks_exact(4)) {
        (y[0], y[1]) = (packed[0], packed[2]);
    }
    let (u, v) = chroma.split_at_mut(luma / 4);
    let rows = source
        .chunks_exact(width * 4)
        .map(|pair| pair.split_at(width * 2));
    let chroma = u
        .chunks_exact_mut(width / 2)
        .zip(v.chunks_exact_mut(width / 2));
    for ((top, bottom), (u, v)) in rows.zip(chroma) {
        let samples = top.chunks_exact(4).zip(bottom.chunks_exact(4));
        for ((top, bottom), (u, v)) in samples.zip(u.iter_mut().zip(v)) {
            *u = mean(&[top[1], bottom[1]]);
            *v = mean(&[top[3], bottom[3]]);
        }
    }
    Some(())
}

/// Packed 24-bit RGB with its channels at `order` (red, green, blue). Each
/// chroma sample comes from the mean colour of its 2x2 block.
fn rgb(source: &[u8], width: usize, order: [usize; 3], planes: &mut [u8]) -> Option<()> {
    let luma = planes.len() / 3 * 2;
    if source.len() != luma * 3 {
        return None;
    }
    let colour = |pixel: &[u8]| [pixel[order[0]], pixel[order[1]], pixel[order[2]]];
    let (y, chroma) = planes.split_at_mut(luma);
    for (y, pixel) in y.iter_mut().zip(source.chunks_exact(3)) {
        *y = bt601(colour(pixel), [66, 129, 25], 16);
    }
    let (u, v) = chroma.split_at_mut(luma / 4);
    let rows = source
        .chunks_exact(width * 6)
        .map(|pair| pair.split_at(width * 3));
    let chroma = u
        .chunks_exact_mut(width / 2)
        .zip(v.chunks_exact_mut(width / 2));
    for ((top, bottom), (u, v)) in rows.zip(chroma) {
        let blocks = top.chunks_exact(6).zip(bottom.chunks_exact(6));
        for ((top, bottom), (u, v)) in blocks.zip(u.iter_mut().zip(v)) {
            let block = [
                colour(top),
                colour(&top[3..]),
                colour(bottom),
                colour(&bottom[3..]),
            ];
            let mean = [0, 1, 2].map(|channel| mean(&block.map(|pixel| pixel[channel])));
            *u = bt601(mean, [-38, -74, 112], 128);
            *v = bt601(mean, [112, -94, -18], 128);
        }
    }
    Some(())
}

/// One BT.601 video-range component of a colour, in 8-bit fixed point.
fn bt601(colour: [u8; 3], weights: [i32; 3], offset: i32) -> u8 {
    let sum: i32 = colour
        .iter()
        .zip(weights)
        .map(|(c, w)| i32::from(*c) * w)
        .sum();
    (((sum + 128) >> 8) + offset) as u8
}

/// The rounded mean of a few samples.
pub(crate) fn mean(samples: &[u8]) -> u8 {
    let sum: usize = samples.iter().map(|sample| usize::from(*sample)).sum();
    ((sum + samples.len() / 2) / samples.len()) as u8
}

#[cfg(test)]
mod tests {
    use super::*;

    fn convert(format: FrameFormat, size: (u32, u32), data: &[u8]) -> anyhow::Result<Vec<u8>> {
        let mut converter = Converter::default();
        let picture = converter.convert(format, size, data)?;
        assert_eq!((picture.width, picture.height), size);
        Ok(picture.planes.to_vec())
    }

    #[test]
    fn a_720p_frame_is_1_38_megabytes() {
        assert_eq!(size(1280, 720), Some(1_382_400));
        assert_eq!(size(1920, 1080), Some(3_110_400));
        for (width, height) in [
            (0, 720),
            (1281, 720),
            (1280, 721),
            (1920, 1920),
            (3840, 2160),
        ] {
            assert_eq!(size(width, height), None, "{width}x{height}");
        }
    }

    #[test]
    fn nv12_chroma_is_split_into_its_two_planes() {
        let nv12 = [1, 2, 3, 4, 5, 6, 7, 8, 10, 20, 30, 40];
        assert_eq!(
            convert(FrameFormat::NV12, (4, 2), &nv12).unwrap(),
            [1, 2, 3, 4, 5, 6, 7, 8, 10, 30, 20, 40]
        );
    }

    #[test]
    fn yuyv_keeps_every_luma_sample_and_averages_chroma_over_two_rows() {
        let yuyv = [
            10, 100, 20, 200, 11, 50, 21, 60, // top row
            30, 110, 40, 211, 31, 52, 41, 60, // bottom row
        ];
        assert_eq!(
            convert(FrameFormat::YUYV, (4, 2), &yuyv).unwrap(),
            [10, 20, 11, 21, 30, 40, 31, 41, 105, 51, 206, 60]
        );
    }

    #[test]
    fn rgb_becomes_bt601_video_range_in_either_channel_order() {
        // White, black and a pure red; worked from the BT.601 matrix:
        // Y 235/16/81, and red's chroma U 90, V 240.
        let white_black = [[255; 3], [255; 3], [0; 3], [0; 3]].concat();
        let rows = [white_black.clone(), white_black].concat();
        assert_eq!(
            convert(FrameFormat::RAWRGB, (4, 2), &rows).unwrap(),
            [235, 235, 16, 16, 235, 235, 16, 16, 128, 128, 128, 128]
        );
        let red = convert(FrameFormat::RAWRGB, (2, 2), &[255, 0, 0].repeat(4)).unwrap();
        let blue_first = convert(FrameFormat::RAWBGR, (2, 2), &[0, 0, 255].repeat(4)).unwrap();
        assert_eq!(red, blue_first);
        for (sample, expected) in red.iter().zip([81, 81, 81, 81, 90, 240]) {
            assert!(sample.abs_diff(expected) <= 1, "{red:?}");
        }
    }

    #[test]
    fn frames_of_another_length_size_or_format_are_refused() {
        // A padded buffer would put the chroma at the wrong offset.
        for (format, bytes) in [
            (FrameFormat::NV12, 12),
            (FrameFormat::YUYV, 16),
            (FrameFormat::RAWRGB, 24),
        ] {
            assert!(convert(format, (4, 2), &vec![0; bytes]).is_ok());
            assert!(convert(format, (4, 2), &vec![0; bytes - 1]).is_err());
            assert!(convert(format, (4, 2), &vec![0; bytes + 4]).is_err());
        }
        assert!(convert(FrameFormat::NV12, (3, 2), &[0; 9]).is_err());
        assert!(convert(FrameFormat::GRAY, (4, 2), &[0; 8]).is_err());
    }
}
