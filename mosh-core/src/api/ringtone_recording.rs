//! Fixed, compiled PCM recordings. The bundled canonical WAV format is checked
//! by tests; this module does not parse arbitrary files or allocate in callbacks.

const HEADER_BYTES: usize = 44;
const SAMPLE_RATE: f64 = 48_000.0;
const CHANNELS: usize = 2;

pub(super) struct Recording {
    wav: &'static [u8],
    gain: f32,
}

// Gains match the loudness of the previous single ringtone.
pub(super) static INCOMING: Recording = Recording {
    wav: include_bytes!("../../../assets/audio/ringtone_incoming.wav"),
    gain: 0.5,
};
pub(super) static OUTGOING: Recording = Recording {
    wav: include_bytes!("../../../assets/audio/ringtone_outgoing.wav"),
    gain: 0.6,
};

impl Recording {
    pub(super) fn sample(
        &self,
        elapsed: f64,
        output_channel: usize,
        output_channels: usize,
    ) -> f32 {
        pcm_sample(
            &self.wav[HEADER_BYTES..],
            elapsed * SAMPLE_RATE,
            output_channel,
            output_channels,
        ) * self.gain
    }
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

    fn assert_canonical(recording: &Recording, frames: usize) {
        let wav = recording.wav;
        assert_eq!(&wav[..4], b"RIFF");
        assert_eq!(&wav[8..16], b"WAVEfmt ");
        assert_eq!(&wav[16..20], &16_u32.to_le_bytes());
        assert_eq!(&wav[20..22], &1_u16.to_le_bytes());
        assert_eq!(&wav[22..24], &2_u16.to_le_bytes());
        assert_eq!(&wav[24..28], &48_000_u32.to_le_bytes());
        assert_eq!(&wav[34..36], &16_u16.to_le_bytes());
        assert_eq!(&wav[36..40], b"data");
        assert_eq!(wav.len() - HEADER_BYTES, frames * 4);
    }

    #[test]
    fn recordings_match_the_compiled_pcm_format() {
        assert_canonical(&INCOMING, 725_674);
        assert_canonical(&OUTGOING, 612_059);
    }

    #[test]
    fn recordings_are_distinct_audible_phrases_with_silent_loop_boundaries() {
        for recording in [&INCOMING, &OUTGOING] {
            let pcm = &recording.wav[HEADER_BYTES..];
            let last = (pcm.len() / (CHANNELS * 2) - 1) as f64;
            for channel in 0..CHANNELS {
                assert_eq!(pcm_sample(pcm, 0.0, channel, 2), 0.0);
                assert_eq!(pcm_sample(pcm, last, channel, 2), 0.0);
            }
            let phrase: f32 = (0..96_000)
                .map(|i| recording.sample(i as f64 / SAMPLE_RATE, 0, 2).abs())
                .sum();
            assert!(phrase > 100.0);
        }
        assert_ne!(INCOMING.wav, OUTGOING.wav);
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
}
