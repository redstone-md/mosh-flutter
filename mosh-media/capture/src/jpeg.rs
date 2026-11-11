//! Motion JPEG camera frames decoded straight to I420: mozjpeg hands over
//! the YCbCr planes the JPEG stores, so no RGB is ever made.
use crate::i420::{self, mean};
use anyhow::Context;
use mozjpeg::{ColorSpace, CompInfo, CompInfoExt, Decompress};
use std::panic::{AssertUnwindSafe, catch_unwind};

/// JPEG stores full-range YCbCr; the encoder and the preview read video
/// range. Fixed point within one level of 219/255 and 224/255, so the loops
/// that call these vectorize.
fn luma_range(sample: u8) -> u8 {
    ((u16::from(sample) * 220 + 128) >> 8) as u8 + 16
}

fn chroma_range(sample: u8) -> u8 {
    ((u16::from(sample) * 225) >> 8) as u8 + 16
}

/// Keeps mozjpeg's planes between frames, so a steady stream allocates
/// nothing per frame.
#[derive(Default)]
pub struct Decoder {
    components: [Vec<u8>; 3],
}

impl Decoder {
    /// Decodes `jpeg` into `planes` as packed I420 and returns its size.
    pub fn decode(&mut self, jpeg: &[u8], planes: &mut Vec<u8>) -> anyhow::Result<(u32, u32)> {
        // mozjpeg reports a corrupt stream by unwinding.
        catch_unwind(AssertUnwindSafe(|| self.read(jpeg, planes)))
            .unwrap_or_else(|_| Err(anyhow::anyhow!("corrupt camera JPEG")))
    }

    fn read(&mut self, jpeg: &[u8], planes: &mut Vec<u8>) -> anyhow::Result<(u32, u32)> {
        let decoder = Decompress::new_mem(jpeg).context("reading camera JPEG")?;
        let (width, height) = decoder.size();
        let length = i420::size(width as u32, height as u32)
            .context("camera JPEG too large or odd-sized")?;
        let stored = Stored::of(decoder.color_space(), decoder.components())?;
        let mut decoder = decoder.raw().context("decoding camera JPEG")?;
        self.components.iter_mut().for_each(Vec::clear);
        let [y, u, v] = &mut self.components;
        decoder.read_raw_data(&mut [&mut *y, &mut *u, &mut *v]);
        decoder.finish().context("decoding camera JPEG")?;

        planes.resize(length, 0);
        let (luma, chroma) = planes.split_at_mut(width * height);
        for (target, source) in luma
            .chunks_exact_mut(width)
            .zip(y.chunks(stored.strides[0]))
        {
            for (target, source) in target.iter_mut().zip(source) {
                *target = luma_range(*source);
            }
        }
        let (target_u, target_v) = chroma.split_at_mut(width * height / 4);
        let [_, stride_u, stride_v] = stored.strides;
        stored.subsample(u, stride_u, width / 2, target_u);
        stored.subsample(v, stride_v, width / 2, target_v);
        Ok((width as u32, height as u32))
    }
}

/// How a JPEG stores its planes: mozjpeg pads each row to whole blocks, and
/// the chroma may be kept at full width or height.
struct Stored {
    strides: [usize; 3],
    /// Chroma samples per I420 chroma sample, across and down: 1 or 2.
    chroma: (usize, usize),
}

impl Stored {
    /// Cameras send YCbCr with chroma halved across (4:2:2) or both ways
    /// (4:2:0); full-size chroma works the same. Anything else is refused.
    fn of(space: ColorSpace, components: &[CompInfo]) -> anyhow::Result<Self> {
        let [y, u, v] = components else {
            anyhow::bail!("camera JPEG is not YCbCr");
        };
        let luma = y.sampling();
        anyhow::ensure!(
            space == ColorSpace::JCS_YCbCr
                && matches!(luma, (1 | 2, 1 | 2))
                && u.sampling() == (1, 1)
                && v.sampling() == (1, 1),
            "unsupported camera JPEG sampling"
        );
        Ok(Self {
            strides: [y, u, v].map(CompInfoExt::row_stride),
            chroma: (usize::from(3 - luma.0), usize::from(3 - luma.1)),
        })
    }

    /// Writes one stored chroma plane, its rows `stride` apart, at I420's
    /// half size both ways, in video range, averaging the samples the JPEG
    /// kept beyond that.
    fn subsample(&self, source: &[u8], stride: usize, width: usize, target: &mut [u8]) {
        let (across, down) = self.chroma;
        for (row, target) in target.chunks_exact_mut(width).enumerate() {
            // With chroma already halved down, both rows are the same one.
            let top = &source[row * down * stride..][..width * across];
            let bottom = &source[(row * down + down - 1) * stride..][..width * across];
            if across == 1 {
                for ((sample, top), bottom) in target.iter_mut().zip(top).zip(bottom) {
                    *sample = chroma_range(mean(&[*top, *bottom]));
                }
            } else {
                let pairs = top.chunks_exact(2).zip(bottom.chunks_exact(2));
                for (sample, (top, bottom)) in target.iter_mut().zip(pairs) {
                    *sample = chroma_range(mean(&[top[0], top[1], bottom[0], bottom[1]]));
                }
            }
        }
    }
}

/// A baseline JPEG, as cameras send, of `width` by `height` pixels, `pixel`
/// giving the RGB of each by its index, with its chroma stored at `chroma`
/// luma pixels per sample.
#[cfg(test)]
pub(crate) fn encode(
    width: usize,
    height: usize,
    chroma: (u8, u8),
    quality: f32,
    pixel: impl Fn(usize) -> [u8; 3],
) -> Vec<u8> {
    let rgb: Vec<u8> = (0..width * height).flat_map(pixel).collect();
    let mut compress = mozjpeg::Compress::new(ColorSpace::JCS_RGB);
    // mozjpeg's own default is a progressive file, which decodes far slower.
    compress.set_fastest_defaults();
    compress.set_size(width, height);
    compress.set_quality(quality);
    compress.set_chroma_sampling_pixel_sizes(chroma, chroma);
    let mut started = compress.start_compress(Vec::new()).expect("a JPEG writer");
    started.write_scanlines(&rgb).expect("written rows");
    started.finish().expect("a finished JPEG")
}

#[cfg(test)]
mod tests {
    use super::*;
    use mozjpeg::Compress;

    fn jpeg(
        width: usize,
        height: usize,
        chroma: (u8, u8),
        column: impl Fn(usize) -> [u8; 3],
    ) -> Vec<u8> {
        encode(width, height, chroma, 95.0, |index| column(index % width))
    }

    fn decode(jpeg: &[u8]) -> anyhow::Result<((u32, u32), Vec<u8>)> {
        let mut planes = Vec::new();
        let size = Decoder::default().decode(jpeg, &mut planes)?;
        Ok((size, planes))
    }

    fn near(samples: &[u8], expected: u8) -> bool {
        samples.iter().all(|sample| sample.abs_diff(expected) <= 3)
    }

    #[test]
    fn camera_samplings_decode_to_i420_in_video_range() {
        // BT.601 video range for RGB (220, 30, 30) is Y 91, U 100, V 211.
        // 20x12 is not a whole number of JPEG blocks either way.
        for chroma in [(2, 1), (2, 2), (1, 1), (1, 2)] {
            let (size, planes) = decode(&jpeg(20, 12, chroma, |_| [220, 30, 30])).unwrap();
            assert_eq!((size, planes.len()), ((20, 12), 360), "{chroma:?}");
            let (y, uv) = planes.split_at(240);
            assert!(near(y, 91), "{chroma:?} luma {y:?}");
            assert!(near(&uv[..60], 100), "{chroma:?} U {uv:?}");
            assert!(near(&uv[60..], 211), "{chroma:?} V {uv:?}");
        }
    }

    #[test]
    fn full_range_black_and_white_land_on_video_range_in_their_columns() {
        let halves = |x| if x < 16 { [255; 3] } else { [0; 3] };
        let (size, planes) = decode(&jpeg(32, 16, (2, 1), halves)).unwrap();
        assert_eq!(size, (32, 16));
        for row in planes[..32 * 16].chunks_exact(32) {
            assert!(near(&row[..16], 235) && near(&row[16..], 16), "{row:?}");
        }
        assert!(near(&planes[32 * 16..], 128));
    }

    #[test]
    fn corrupt_grey_and_odd_sized_jpegs_are_refused_without_a_panic() {
        assert!(decode(b"not a jpeg").is_err());
        assert!(decode(&jpeg(21, 12, (2, 1), |_| [9; 3])).is_err());
        let mut grey = Compress::new(ColorSpace::JCS_GRAYSCALE);
        grey.set_size(16, 16);
        let mut started = grey.start_compress(Vec::new()).unwrap();
        started.write_scanlines(&[128; 256]).unwrap();
        assert!(decode(&started.finish().unwrap()).is_err());
    }
}
