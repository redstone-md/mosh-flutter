use nokhwa::{FormatDecoder, pixel_format::RgbAFormat, utils::CameraFormat};

pub fn choose(formats: Vec<CameraFormat>) -> anyhow::Result<CameraFormat> {
    formats
        .into_iter()
        .filter(|format| {
            let (width, height) = (format.width(), format.height());
            width > 0
                && height > 0
                && width <= 1920
                && height <= 1920
                && width as u64 * height as u64 <= 1920 * 1080
                && format.frame_rate() > 0
                && RgbAFormat::FORMATS.contains(&format.format())
        })
        .min_by_key(score)
        .ok_or_else(|| anyhow::anyhow!("no supported camera format"))
}

fn score(format: &CameraFormat) -> (u64, u32, u32) {
    let distance =
        u64::from(format.width().abs_diff(1280)) + u64::from(format.height().abs_diff(720));
    (
        distance,
        format.frame_rate().abs_diff(30),
        if format.frame_rate() > 30 { 1 } else { 0 },
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use nokhwa::utils::FrameFormat;

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
}
