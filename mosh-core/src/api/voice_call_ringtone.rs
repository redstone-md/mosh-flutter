//! CPAL-backed two-tone ringtone for incoming and outgoing voice calls.

use std::sync::{Arc, Mutex};
use std::thread;
use std::time::Duration;

use cpal::traits::{DeviceTrait, StreamTrait};
use cpal::{OutputCallbackInfo, SampleFormat, Stream, StreamConfig};
use flutter_rust_bridge::frb;

use crate::diagnostics_log::{self as dlog, kinds, LogLevel};

const FIRST_FREQUENCY_HZ: f64 = 440.0;
const SECOND_FREQUENCY_HZ: f64 = 480.0;
const ATTACK_SECONDS: f64 = 0.05;
const ON_SECONDS: f64 = 0.4;
const RELEASE_SECONDS: f64 = 0.45;
const PERIOD_SECONDS: f64 = 1.0;
const MAX_SECONDS: f64 = 30.0;
const MIN_GAIN: f64 = 0.0001;
const PEAK_GAIN: f64 = 0.15;

/// The mutable phase state lives only on CPAL's callback thread.
struct SignalGenerator {
    sample_rate: f64,
    next_sample: u64,
}

impl SignalGenerator {
    fn next(&mut self) -> f32 {
        let elapsed = self.next_sample as f64 / self.sample_rate;
        self.next_sample = self.next_sample.saturating_add(1);
        ringtone_sample(elapsed)
    }
}

fn gain_at(phase: f64) -> f64 {
    if phase < ATTACK_SECONDS {
        MIN_GAIN * (PEAK_GAIN / MIN_GAIN).powf(phase / ATTACK_SECONDS)
    } else if phase < ON_SECONDS {
        PEAK_GAIN
    } else if phase < RELEASE_SECONDS {
        PEAK_GAIN
            * (MIN_GAIN / PEAK_GAIN).powf((phase - ON_SECONDS) / (RELEASE_SECONDS - ON_SECONDS))
    } else {
        MIN_GAIN
    }
}

fn ringtone_sample(elapsed: f64) -> f32 {
    if !(0.0..MAX_SECONDS).contains(&elapsed) {
        return 0.0;
    }
    let phase = elapsed % PERIOD_SECONDS;
    let gain = gain_at(phase);
    let angle = std::f64::consts::TAU * elapsed;
    let tone = (angle * FIRST_FREQUENCY_HZ).sin() + (angle * SECOND_FREQUENCY_HZ).sin();
    (gain * tone) as f32
}

fn write_f32(data: &mut [f32], channels: usize, generator: &mut SignalGenerator) {
    for frame in data.chunks_mut(channels) {
        let value = generator.next();
        frame.fill(value);
    }
}

fn write_i16(data: &mut [i16], channels: usize, generator: &mut SignalGenerator) {
    for frame in data.chunks_mut(channels) {
        let value = (generator.next().clamp(-1.0, 1.0) * i16::MAX as f32).round() as i16;
        frame.fill(value);
    }
}

fn write_u16(data: &mut [u16], channels: usize, generator: &mut SignalGenerator) {
    for frame in data.chunks_mut(channels) {
        let normalized = generator.next().clamp(-1.0, 1.0) * 0.5 + 0.5;
        frame.fill((normalized * u16::MAX as f32).round() as u16);
    }
}

fn build_stream(
    device: &cpal::Device,
    config: &StreamConfig,
    sample_format: SampleFormat,
) -> Result<Stream, String> {
    let channels = config.channels as usize;
    if channels == 0 {
        return Err("cpal ringtone: output device reported zero channels".to_string());
    }
    let generator = SignalGenerator {
        sample_rate: config.sample_rate as f64,
        next_sample: 0,
    };

    let stream = match sample_format {
        SampleFormat::F32 => {
            let mut generator = generator;
            device.build_output_stream(
                *config,
                move |data: &mut [f32], _info: &OutputCallbackInfo| {
                    write_f32(data, channels, &mut generator);
                },
                |error| {
                    dlog::write(
                        LogLevel::Error,
                        kinds::VOICE,
                        "ringtone",
                        &format!("cpal stream error: {error:?}"),
                    )
                },
                None,
            )
        }
        SampleFormat::I16 => {
            let mut generator = generator;
            device.build_output_stream(
                *config,
                move |data: &mut [i16], _info: &OutputCallbackInfo| {
                    write_i16(data, channels, &mut generator);
                },
                |error| {
                    dlog::write(
                        LogLevel::Error,
                        kinds::VOICE,
                        "ringtone",
                        &format!("cpal stream error: {error:?}"),
                    )
                },
                None,
            )
        }
        SampleFormat::U16 => {
            let mut generator = generator;
            device.build_output_stream(
                *config,
                move |data: &mut [u16], _info: &OutputCallbackInfo| {
                    write_u16(data, channels, &mut generator);
                },
                |error| {
                    dlog::write(
                        LogLevel::Error,
                        kinds::VOICE,
                        "ringtone",
                        &format!("cpal stream error: {error:?}"),
                    )
                },
                None,
            )
        }
        format => return Err(format!("cpal ringtone: unsupported sample format {format}")),
    }
    .map_err(|error| format!("cpal ringtone: build output stream: {error:?}"))?;

    stream
        .play()
        .map_err(|error| format!("cpal ringtone: stream.play: {error:?}"))?;
    Ok(stream)
}

/// Opaque owner of the CPAL stream. The slot is shared with the 30-second
/// cleanup task so the stream is released even when the Dart handle is leaked.
#[frb(opaque)]
pub struct VoiceCallRingtone {
    stream: Arc<Mutex<Option<Stream>>>,
}

#[frb(sync)]
pub fn voice_call_ringtone_start(
    output_device_id: Option<String>,
) -> Result<VoiceCallRingtone, String> {
    let device = crate::audio_devices::resolve_output_device(output_device_id.as_deref())?;
    let supported = device
        .default_output_config()
        .map_err(|error| format!("cpal ringtone: default output config: {error:?}"))?;
    let sample_format = supported.sample_format();
    let config = supported.config();
    let stream = build_stream(&device, &config, sample_format)?;
    let stream_slot = Arc::new(Mutex::new(Some(stream)));
    let cleanup_slot = Arc::clone(&stream_slot);
    thread::Builder::new()
        .name("mosh-ringtone-timeout".to_string())
        .spawn(move || {
            thread::sleep(Duration::from_secs(MAX_SECONDS as u64));
            if let Ok(mut guard) = cleanup_slot.lock() {
                guard.take();
            }
        })
        .map_err(|error| format!("cpal ringtone: cleanup thread: {error}"))?;
    Ok(VoiceCallRingtone {
        stream: stream_slot,
    })
}

#[frb(sync)]
pub fn voice_call_ringtone_stop(ringtone: &VoiceCallRingtone) -> Result<(), String> {
    let mut guard = ringtone
        .stream
        .lock()
        .map_err(|error| format!("cpal ringtone: stop mutex poisoned: {error}"))?;
    guard.take();
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::{
        gain_at, ringtone_sample, ATTACK_SECONDS, MAX_SECONDS, MIN_GAIN, ON_SECONDS, PEAK_GAIN,
        RELEASE_SECONDS,
    };

    #[test]
    fn gain_matches_react_attack_hold_release_and_silence() {
        assert!((gain_at(0.0) - MIN_GAIN).abs() < f64::EPSILON);
        assert!((gain_at(ATTACK_SECONDS) - PEAK_GAIN).abs() < f64::EPSILON);
        assert!((gain_at(ON_SECONDS) - PEAK_GAIN).abs() < f64::EPSILON);
        assert!(gain_at((ON_SECONDS + RELEASE_SECONDS) / 2.0) < PEAK_GAIN);
        assert_eq!(gain_at(RELEASE_SECONDS), MIN_GAIN);
        assert_eq!(gain_at(0.9), MIN_GAIN);
    }

    #[test]
    fn tone_is_silent_during_off_period_and_after_timeout() {
        assert!((ringtone_sample(0.5) as f64).abs() < MIN_GAIN);
        assert_eq!(ringtone_sample(MAX_SECONDS), 0.0);
        assert_eq!(ringtone_sample(MAX_SECONDS + 0.1), 0.0);
    }

    #[test]
    fn tone_contains_both_oscillators_during_ring_on_period() {
        let elapsed = 0.2005;
        let sample = ringtone_sample(elapsed);
        let expected = PEAK_GAIN
            * ((std::f64::consts::TAU * elapsed * 440.0).sin()
                + (std::f64::consts::TAU * elapsed * 480.0).sin());
        assert!(expected.abs() > 0.01);
        assert!((sample as f64 - expected).abs() < 1e-6);
    }
}
