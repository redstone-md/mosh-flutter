//! Fixed, compiled PCM recording. The bundled canonical WAV format is checked
//! by tests; this module does not parse arbitrary files or allocate in callbacks.

const RECORDING: &[u8] = include_bytes!("../../../assets/audio/cipher_stream.wav");
const HEADER_BYTES: usize = 44;
const SAMPLE_RATE: f64 = 44_100.0;
const CHANNELS: usize = 2;
const GAIN: f32 = 0.3;

pub(super) fn sample(elapsed: f64, output_channel: usize, output_channels: usize) -> f32 {
    pcm_sample(
        &RECORDING[HEADER_BYTES..],
        elapsed * SAMPLE_RATE,
        output_channel,
        output_channels,
    ) * GAIN
}

fn pcm_sample(pcm: &[u8], position: f64, channel: usize, output_channels: usize) -> f32 {
    if output_channels > 1 && channel >= CHANNELS {
        return 0.0;
    }
    let frames = pcm.len() / (CHANNELS * 2);
    let index = position.floor() as usize % frames;
    let next = (index + 1) % frames;
    let fraction = position.fract() as f32;
    let at = |frame| {
        if output_channels == 1 {
            (read(pcm, frame, 0) + read(pcm, frame, 1)) * 0.5
        } else {
            read(pcm, frame, channel)
        }
    };
    at(index) * (1.0 - fraction) + at(next) * fraction
}

fn read(pcm: &[u8], frame: usize, channel: usize) -> f32 {
    let offset = (frame * CHANNELS + channel) * 2;
    i16::from_le_bytes([pcm[offset], pcm[offset + 1]]) as f32 / 32768.0
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn recording_matches_the_compiled_pcm_format() {
        assert_eq!(&RECORDING[..4], b"RIFF");
        assert_eq!(&RECORDING[8..16], b"WAVEfmt ");
        assert_eq!(&RECORDING[16..20], &16_u32.to_le_bytes());
        assert_eq!(&RECORDING[20..22], &1_u16.to_le_bytes());
        assert_eq!(&RECORDING[22..24], &2_u16.to_le_bytes());
        assert_eq!(&RECORDING[24..28], &44_100_u32.to_le_bytes());
        assert_eq!(&RECORDING[34..36], &16_u16.to_le_bytes());
        assert_eq!(&RECORDING[36..40], b"data");
        assert_eq!(RECORDING.len() - HEADER_BYTES, 123_479 * 4);
    }

    #[test]
    fn preserves_stereo_and_averages_mono_without_surround_noise() {
        let pcm = [0, 64, 0, 192, 0, 0, 0, 32];
        assert_eq!(pcm_sample(&pcm, 0.0, 0, 2), 0.5);
        assert_eq!(pcm_sample(&pcm, 0.0, 1, 2), -0.5);
        assert_eq!(pcm_sample(&pcm, 0.0, 0, 1), 0.0);
        assert_eq!(pcm_sample(&pcm, 0.0, 3, 6), 0.0);
    }

    #[test]
    fn interpolates_between_frames_and_loops_at_the_recording_boundary() {
        let pcm = [0, 0, 0, 0, 0, 64, 0, 64];
        assert_eq!(pcm_sample(&pcm, 0.5, 0, 2), 0.25);
        assert_eq!(pcm_sample(&pcm, 1.5, 0, 2), 0.25);
        assert_eq!(pcm_sample(&pcm, 2.0, 0, 2), 0.0);
        assert_eq!(pcm_sample(&pcm, 2.5, 0, 2), 0.25);
    }

    #[test]
    fn the_recording_has_an_audible_phrase_and_a_silent_loop_boundary() {
        assert_eq!(sample(0.0, 0, 2), 0.0);
        let phrase: f32 = (1_000..60_000)
            .map(|i| sample(i as f64 / SAMPLE_RATE, 0, 2).abs())
            .sum();
        assert!(phrase > 100.0);
        assert_eq!(sample(2.7, 0, 2), 0.0);
        assert_eq!(sample(2.7, 1, 2), 0.0);
    }
}
