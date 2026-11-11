use crate::i420;
use nokhwa::utils::{CameraFormat, FrameFormat};

/// The mode nearest 1280x720 at 30 fps among those the helper converts, and
/// at equal size and rate the one that costs least to bring to I420.
pub fn choose(formats: Vec<CameraFormat>) -> anyhow::Result<CameraFormat> {
    formats
        .into_iter()
        .filter(|format| {
            i420::size(format.width(), format.height()).is_some() && format.frame_rate() > 0
        })
        .filter_map(|format| Some((score(&format)?, format)))
        .min_by_key(|(score, _)| *score)
        .map(|(_, format)| format)
        .ok_or_else(|| anyhow::anyhow!("no supported camera format"))
}

fn score(format: &CameraFormat) -> Option<(u64, u32, u32, u32)> {
    let distance =
        u64::from(format.width().abs_diff(1280)) + u64::from(format.height().abs_diff(720));
    // Planar and packed YUV are copies; RGB needs arithmetic and a JPEG a decode.
    let conversion = match format.format() {
        FrameFormat::NV12 => 0,
        FrameFormat::YUYV => 1,
        FrameFormat::RAWRGB | FrameFormat::RAWBGR => 2,
        FrameFormat::MJPEG => 3,
        FrameFormat::GRAY => return None,
    };
    Some((
        distance,
        format.frame_rate().abs_diff(30),
        if format.frame_rate() > 30 { 1 } else { 0 },
        conversion,
    ))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn selects_actual_720p30_capability_and_rejects_oversized_inputs() {
        let desired = CameraFormat::new_from(1280, 720, FrameFormat::MJPEG, 30);
        assert_eq!(
            choose(vec![
                CameraFormat::new_from(1920, 1080, FrameFormat::MJPEG, 60),
                desired,
                CameraFormat::new_from(1280, 720, FrameFormat::MJPEG, 60)
            ])
            .unwrap(),
            desired
        );
        assert!(
            choose(vec![CameraFormat::new_from(
                3840,
                2160,
                FrameFormat::MJPEG,
                30
            )])
            .is_err()
        );
        assert!(choose(vec![]).is_err());
    }

    #[test]
    fn at_equal_size_and_rate_the_cheapest_format_to_convert_wins() {
        let mode = |format| CameraFormat::new_from(1280, 720, format, 30);
        let offered = vec![
            mode(FrameFormat::MJPEG),
            mode(FrameFormat::GRAY),
            mode(FrameFormat::NV12),
            mode(FrameFormat::YUYV),
        ];
        assert_eq!(choose(offered).unwrap(), mode(FrameFormat::NV12));
        // A USB 2.0 camera reaches 720p30 only as MJPEG; its rate matters more.
        let usb = vec![
            CameraFormat::new_from(1280, 720, FrameFormat::YUYV, 10),
            mode(FrameFormat::MJPEG),
        ];
        assert_eq!(choose(usb).unwrap(), mode(FrameFormat::MJPEG));
        assert!(choose(vec![mode(FrameFormat::GRAY)]).is_err());
        assert!(
            choose(vec![CameraFormat::new_from(
                1281,
                720,
                FrameFormat::NV12,
                30
            )])
            .is_err()
        );
    }
}
