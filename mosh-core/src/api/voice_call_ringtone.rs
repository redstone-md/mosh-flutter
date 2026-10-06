//! CPAL playback of the bundled call ringtone for incoming and outgoing voice calls.

use std::sync::{Arc, Mutex};
use std::thread;
use std::time::Duration;

use cpal::traits::{DeviceTrait, StreamTrait};
use cpal::{OutputCallbackInfo, SampleFormat, Stream, StreamConfig};
use flutter_rust_bridge::frb;

#[path = "ringtone_recording.rs"]
mod recording;

const MAX_SECONDS: f64 = 30.0;

struct SignalGenerator {
    sample_rate: f64,
    next_sample: u64,
}

impl SignalGenerator {
    fn sample(&self, channel: usize, channels: usize) -> f32 {
        let elapsed = self.next_sample as f64 / self.sample_rate;
        if elapsed >= MAX_SECONDS {
            0.0
        } else {
            recording::sample(elapsed, channel, channels)
        }
    }
}

fn write<T: cpal::Sample + cpal::FromSample<f32>>(
    data: &mut [T],
    channels: usize,
    generator: &mut SignalGenerator,
) {
    for frame in data.chunks_mut(channels) {
        for (channel, value) in frame.iter_mut().enumerate() {
            *value = T::from_sample(generator.sample(channel, channels));
        }
        generator.next_sample = generator.next_sample.saturating_add(1);
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
        SampleFormat::F32 => output_stream::<f32>(device, config, generator),
        SampleFormat::I16 => output_stream::<i16>(device, config, generator),
        SampleFormat::U16 => output_stream::<u16>(device, config, generator),
        format => return Err(format!("cpal ringtone: unsupported sample format {format}")),
    }
    .map_err(|error| format!("cpal ringtone: build output stream: {error:?}"))?;

    stream
        .play()
        .map_err(|error| format!("cpal ringtone: stream.play: {error:?}"))?;
    Ok(stream)
}

fn output_stream<T: cpal::SizedSample + cpal::FromSample<f32>>(
    device: &cpal::Device,
    config: &StreamConfig,
    mut generator: SignalGenerator,
) -> Result<Stream, cpal::Error> {
    let channels = config.channels as usize;
    device.build_output_stream(
        *config,
        move |data: &mut [T], _info: &OutputCallbackInfo| write(data, channels, &mut generator),
        |error| crate::audio_devices::log_stream_error("ringtone", &error),
        None,
    )
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
    use super::*;

    #[test]
    #[ignore = "requires a running output device; run explicitly with PulseAudio or hardware"]
    fn selected_output_releases_the_real_stream_on_repeated_stop() {
        let device = crate::audio_devices::resolve_output_device(None).unwrap();
        let id = device.id().unwrap().to_string();
        for _ in 0..3 {
            let ringtone = voice_call_ringtone_start(Some(id.clone())).unwrap();
            assert!(ringtone.stream.lock().unwrap().is_some());
            thread::sleep(Duration::from_millis(150));
            voice_call_ringtone_stop(&ringtone).unwrap();
            voice_call_ringtone_stop(&ringtone).unwrap();
            assert!(ringtone.stream.lock().unwrap().is_none());
        }
        let supported = device.default_output_config().unwrap();
        let mut invalid = supported.config();
        invalid.channels = 0;
        assert!(build_stream(&device, &invalid, SampleFormat::F32).is_err());
        assert!(build_stream(&device, &supported.config(), SampleFormat::I8).is_err());
    }

    #[test]
    fn sample_rate_conversion_preserves_the_recording_time() {
        let cd = SignalGenerator {
            sample_rate: 44_100.0,
            next_sample: 4_410,
        };
        let device = SignalGenerator {
            sample_rate: 48_000.0,
            next_sample: 4_800,
        };
        assert_eq!(cd.sample(0, 2), device.sample(0, 2));
        assert_eq!(cd.sample(1, 2), device.sample(1, 2));
    }

    #[test]
    fn timeout_outputs_silence_in_every_sample_format() {
        let mut generator = SignalGenerator {
            sample_rate: 48_000.0,
            next_sample: 1_440_000,
        };
        let mut float = [1.0_f32; 4];
        write(&mut float, 2, &mut generator);
        assert_eq!(float, [0.0; 4]);
        let mut signed = [1_i16; 4];
        write(&mut signed, 2, &mut generator);
        assert_eq!(signed, [0; 4]);
        let mut unsigned = [1_u16; 4];
        write(&mut unsigned, 2, &mut generator);
        assert_eq!(unsigned, [32_768; 4]);
    }
}
