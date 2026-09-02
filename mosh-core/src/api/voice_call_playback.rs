//! Opus decoder + cpal output facade for the voice-call playback pipeline.
//!
//! Mirrors the React `mosh/src/features/private-dm/voice-call/audio-playback.ts`
//! flow: WebCodecs `AudioDecoder` -> Web Audio `createBufferSource.start(time)`
//! per-20ms-frame scheduling with `nextStart` chaining and drift-resync (if
//! `start - currentTime > 0.2s`, reset `start = currentTime`). Here the Opus
//! decode happens via `audiopus::coder::Decoder` (vendored libopus, MSVC) and
//! playback is a `cpal::Stream` (Windows WASAPI) fed from a `ringbuf` ring;
//! the cpal `data_callback` pulls decoded PCM off the ring's consumer and
//! zero-fills underruns, while `push_frame` decodes one Opus packet and
//! pushes 960 i16 samples onto the ring's producer.
//!
//! frb contract: the playback is opaque across the FFI seam (it owns a raw
//! libopus `OpusDecoder*` that is `Send` but not `Sync`, plus a `cpal::Stream`
//! that is `Send` but not `Sync` on some backends). Each Dart call borrows the
//! single owned playback mutably, decodes one Opus packet, and the ring feeds
//! the cpal callback asynchronously. Errors are stringified to keep the bridge
//! surface a plain `Result<T, String>` (matches `voice_call_opus_encode`).
//!
//! The `seq` parameter is a Dart `BigInt` on the seam, which frb 2.x bridges
//! to a Rust `u128` (the call frame sequence is non-negative; the mask in
//! `frame_codec.dart` is `(1 << 63) - 1`, well inside `u128`). cpal's pull
//! model does not schedule by timestamp -- the seq is accepted for seam parity
//! with `VoicePlaybackHandle.pushFrame` and otherwise unused here.
//!
//! Ring ownership: the `HeapRb::split()` yields exactly one producer and one
//! consumer. The consumer is shared between the cpal data callback (which
//! `pop_slice`s output buffers) and `push_frame`'s drift-resync path (which
//! `clear`s the backlog), so it lives in an `Arc<Mutex<HeapCons>>` cloned into
//! the `Send` closure. The producer lives in a plain `Mutex` (only
//! `push_frame` touches it). `occupied_len` is an `Observer` method available
//! on the producer, so the resync snapshot needs no consumer lock; only the
//! (rare) `clear` locks the consumer. No path holds both locks at once.

use std::sync::{Arc, Mutex};

use audiopus::{coder::Decoder, Channels, SampleRate};
use cpal::{
    default_host, traits::DeviceTrait, traits::HostTrait, traits::StreamTrait, BufferSize, Device,
    FromSample, OutputCallbackInfo, SampleFormat, SizedSample, Stream, StreamConfig,
};
use flutter_rust_bridge::frb;
use ringbuf::{
    traits::Consumer, traits::Observer, traits::Producer, traits::Split, HeapCons, HeapProd, HeapRb,
};

/// Drift-resync threshold in seconds. Mirrors React's
/// `PLAYBACK_RESYNC_S = 0.2` -- when the ring backlog exceeds 0.2s of audio,
/// drop it and resume from "now" (the equivalent of React resetting
/// `nextStart = currentTime`).
const PLAYBACK_RESYNC_S: f64 = 0.2;

/// One 20 ms Opus frame at 48 kHz mono = 960 samples. Matches the capture
/// side's frame size and React's per-frame scheduling cadence.
const FRAME_SAMPLES: usize = 960;

/// Playback sample rate (48 kHz mono), 1-1 with the Opus decoder config.
const SAMPLE_RATE: u32 = 48_000;

/// Ring capacity in frames. 8 * 960 = 7680 samples (~160 ms of slack), kept
/// *below* the 200 ms resync threshold so steady-state jitter never trips a
/// resync -- only a real stall (callback starved > 200 ms) does.
const RING_FRAMES: usize = 8;

/// Opaque wrapper over the playback pipeline. The `Decoder` owns a libopus
/// `OpusDecoder*` (`Send` but not `Sync`); the `cpal::Stream` is `Send` but not
/// `Sync` on some backends; the ring halves are `Send + Sync`. All four are
/// wrapped in `Mutex` (the consumer via `Arc<Mutex<_>>` so the cpal closure
/// shares it) so the whole struct is `Sync` (frb's `RustAutoOpaqueMoi` pool
/// stores the opaque behind an `Arc<RwLock<..>>` that requires `Sync`),
/// matching the `voice_call_opus_encode` encoder pattern.
#[frb(opaque)]
pub struct VoicePlayback {
    decoder: Mutex<Decoder>,
    producer: Mutex<HeapProd<i16>>,
    consumer: Arc<Mutex<HeapCons<i16>>>,
    stream: Mutex<Option<Stream>>,
}

/// Pure drift-resync predicate, factored out so it has a `#[cfg(test)]` cover
/// (the rest of the pipeline needs a live audio device + the frb cdylib, so it
/// is validated on a device, not in `cargo test`). Returns `true` when the
/// current ring backlog in seconds exceeds the threshold -- the caller then
/// clears the ring and resumes from "now", mirroring React's
/// `start - currentTime > 0.2 ? currentTime : start`.
fn should_resync(occupied_s: f64, threshold_s: f64) -> bool {
    occupied_s > threshold_s
}

/// Turns the 48 kHz mono ring into whatever the output device consumes:
/// linear resampling to the device rate and the same sample on every
/// channel. Underrun (ring empty) reads as silence, mirroring React's
/// `source.start(time)` producing nothing when no buffer is scheduled.
struct Renderer {
    consumer: Arc<Mutex<HeapCons<i16>>>,
    channels: usize,
    /// Source samples per output sample (48000 / device rate).
    step: f64,
    /// Position between `prev` and `next`, in [0, 1).
    pos: f64,
    prev: i16,
    next: i16,
}

impl Renderer {
    fn new(consumer: Arc<Mutex<HeapCons<i16>>>, config: &StreamConfig) -> Self {
        Self {
            consumer,
            channels: config.channels.max(1) as usize,
            step: f64::from(SAMPLE_RATE) / f64::from(config.sample_rate.max(1)),
            pos: 0.0,
            prev: 0,
            next: 0,
        }
    }

    fn fill<T: SizedSample + FromSample<i16>>(&mut self, buf: &mut [T]) {
        // One lock per callback. A poisoned mutex means `stop` raced and the
        // stream is tearing down; render silence and move on.
        let consumer = Arc::clone(&self.consumer);
        let mut guard = consumer.lock().ok();
        for frame in buf.chunks_mut(self.channels) {
            let sample = self.next_sample(&mut guard);
            frame.fill(T::from_sample(sample));
        }
    }

    fn next_sample(&mut self, cons: &mut Option<std::sync::MutexGuard<'_, HeapCons<i16>>>) -> i16 {
        self.pos += self.step;
        while self.pos >= 1.0 {
            self.pos -= 1.0;
            self.prev = self.next;
            self.next = cons.as_mut().and_then(|c| c.try_pop()).unwrap_or(0);
        }
        lerp(self.prev, self.next, self.pos)
    }
}

/// Linear interpolation between two samples, rounded to the nearest i16.
fn lerp(a: i16, b: i16, t: f64) -> i16 {
    (f64::from(a) + (f64::from(b) - f64::from(a)) * t).round() as i16
}

fn build_stream<T: SizedSample + FromSample<i16>>(
    device: &Device,
    config: &StreamConfig,
    mut renderer: Renderer,
) -> Result<Stream, String> {
    device
        .build_output_stream(
            *config,
            move |buf: &mut [T], _info: &OutputCallbackInfo| renderer.fill(buf),
            |err| {
                // Mirrors React's `AudioContext` error path: log-only. The
                // stream stays alive for the call's lifetime; a hard fault
                // surfaces on the next `push_frame` as a poisoned mutex or is
                // cleaned up by `stop`.
                eprintln!("voice_call_playback: cpal stream error: {err:?}");
            },
            None,
        )
        .map_err(|e| format!("cpal build_output_stream: {e:?}"))
}

/// Starts the playback pipeline: an Opus decoder (48 kHz mono) + a cpal output
/// stream in the device's own format, fed from a 7680-sample ring. Synchronous (audio open is blocking on
/// every cpal backend); `Err(String)` if there is no default output device or
/// the stream cannot be built/started. Errors are stringified via `Debug`,
/// matching `voice_call_opus_encode`'s `Result<T, String>` style.
#[frb(sync)]
pub fn voice_call_playback_start() -> Result<VoicePlayback, String> {
    let decoder = Decoder::new(SampleRate::Hz48000, Channels::Mono)
        .map_err(|e| format!("opus decoder init: {e:?}"))?;

    let ring = HeapRb::<i16>::new(RING_FRAMES * FRAME_SAMPLES);
    let (producer, consumer) = ring.split();

    let device = default_host()
        .default_output_device()
        .ok_or_else(|| "cpal: no default output device".to_string())?;

    // Play in the device's own shape. WASAPI shared mode only accepts the
    // mix format (typically 48 kHz stereo f32, sometimes 44.1 kHz), so forcing
    // 48 kHz mono i16 here failed with StreamConfigNotSupported on most
    // machines. The ring stays 48 kHz mono i16 (the Opus contract); the
    // callback resamples and fans out to whatever the device wants.
    let supported = device
        .default_output_config()
        .map_err(|e| format!("cpal default_output_config: {e:?}"))?;
    let sample_format = supported.sample_format();
    let mut config: StreamConfig = supported.config();
    config.buffer_size = BufferSize::Default;

    // The consumer is shared between the cpal callback (via the renderer)
    // and the drift-resync path (clear), so it is wrapped in `Arc<Mutex<_>>`
    // and a clone is moved into the `Send` closure. The struct keeps the
    // other clone; the underlying `Arc<HeapRb>` keeps the ring alive while
    // either half is held (and the `Stream` in the struct owns the closure).
    let consumer = Arc::new(Mutex::new(consumer));
    let renderer = Renderer::new(Arc::clone(&consumer), &config);
    let stream = match sample_format {
        SampleFormat::F32 => build_stream::<f32>(&device, &config, renderer),
        SampleFormat::I16 => build_stream::<i16>(&device, &config, renderer),
        SampleFormat::U16 => build_stream::<u16>(&device, &config, renderer),
        other => Err(format!("cpal: unsupported output sample format {other}")),
    }?;
    stream
        .play()
        .map_err(|e| format!("cpal stream.play: {e:?}"))?;

    Ok(VoicePlayback {
        decoder: Mutex::new(decoder),
        producer: Mutex::new(producer),
        consumer,
        stream: Mutex::new(Some(stream)),
    })
}

/// Decodes one Opus packet and pushes its 960 i16 samples onto the ring. `seq`
/// is the call frame sequence (preserves gaps on the wire, mirroring React's
/// `(seq & SEQ_VALUE_MASK) * 20000us` timestamp), unused by cpal's pull model
/// but accepted for seam parity with `VoicePlaybackHandle.pushFrame`. If the
/// ring backlog exceeds `PLAYBACK_RESYNC_S`, the backlog is dropped first
/// (React's `start = currentTime` resync). On a full ring the push clears the
/// backlog and retries, matching React's no-backpressure `source.start(0)`
/// "play from now" behavior.
#[frb(sync)]
pub fn voice_call_playback_push_frame(
    p: &VoicePlayback,
    _seq: u128,
    opus: Vec<u8>,
) -> Result<(), String> {
    let mut pcm = [0i16; FRAME_SAMPLES];
    let decoded = {
        let mut guard = p
            .decoder
            .lock()
            .map_err(|e| format!("opus decode: mutex poisoned: {e}"))?;
        guard
            .decode(Some(opus.as_slice()), &mut pcm[..], false)
            .map_err(|e| format!("opus decode: {e:?}"))?
    };
    // libopus returns the decoded samples per channel; a 20 ms frame at 48 kHz
    // mono is exactly 960. A short return (e.g. a 2.5/5 ms packet) would
    // under-fill the frame -- treat anything other than a full frame as a
    // framing slip so it surfaces as a hard error rather than a mis-aligned
    // ring write (matches the capture side's strict 1920-byte frame check).
    if decoded != FRAME_SAMPLES {
        return Err(format!(
            "opus decode: expected {FRAME_SAMPLES} samples, got {decoded}"
        ));
    }

    let mut prod = p
        .producer
        .lock()
        .map_err(|e| format!("playback push: producer mutex poisoned: {e}"))?;

    // Drift-resync: if the backlog exceeds the threshold, drop it and resume
    // from "now" (React: `start = currentTime`). `occupied_len` is an
    // `Observer` method on the producer, so the snapshot needs no consumer
    // lock; only the (rare) `clear` locks the consumer. The snapshot is
    // slightly stale relative to the cpal callback's reads but correct enough
    // for a threshold check (the same kind of `currentTime` snapshot React
    // uses). A poisoned consumer mutex means `stop` raced -- treat as
    // already-stopped and skip the push.
    let occupied_s = prod.occupied_len() as f64 / SAMPLE_RATE as f64;
    if should_resync(occupied_s, PLAYBACK_RESYNC_S) {
        if let Ok(mut cons) = p.consumer.lock() {
            cons.clear();
        }
    }

    // Push the decoded frame. If the ring is full (callback stalled longer
    // than the ring's slack without crossing the resync threshold), clear the
    // backlog and retry -- matches React's "play from now" (no backpressure,
    // resume at the live edge). A still-full retry means the callback is
    // wedged; discard the frame rather than block the FFI thread (better to
    // lose one frame than stall decode).
    let pushed = prod.push_slice(&pcm);
    if pushed < FRAME_SAMPLES {
        if let Ok(mut cons) = p.consumer.lock() {
            cons.clear();
        }
        let _ = prod.push_slice(&pcm);
    }
    Ok(())
}

/// Stops the playback pipeline by dropping the `cpal::Stream` (closes the
/// audio output, mirroring React's `context.close()`). The decoder and ring
/// are dropped with the `VoicePlayback` opaque when frb releases it. Inert if
/// already stopped (idempotent -- matches `VoicePlaybackHandle.stop`'s
/// "inert if already stopped" contract).
#[frb(sync)]
pub fn voice_call_playback_stop(p: &VoicePlayback) -> Result<(), String> {
    let mut guard = p
        .stream
        .lock()
        .map_err(|e| format!("playback stop: stream mutex poisoned: {e}"))?;
    if let Some(stream) = guard.take() {
        // Drop the stream first (closes the device); the decoder + ring fall
        // with the `VoicePlayback` opaque when frb releases it.
        drop(stream);
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use std::sync::{Arc, Mutex};

    use cpal::{BufferSize, StreamConfig};
    use ringbuf::{traits::Producer, traits::Split, HeapRb};

    use super::{should_resync, Renderer, PLAYBACK_RESYNC_S, SAMPLE_RATE};

    /// A renderer over a ring holding `source`, for a device of `channels`
    /// at `rate` Hz.
    fn renderer(source: &[i16], channels: u16, rate: u32) -> Renderer {
        let ring = HeapRb::<i16>::new(source.len().max(1));
        let (mut producer, consumer) = ring.split();
        producer.push_slice(source);
        let config = StreamConfig {
            channels,
            sample_rate: rate,
            buffer_size: BufferSize::Default,
        };
        Renderer::new(Arc::new(Mutex::new(consumer)), &config)
    }

    #[test]
    fn same_rate_passes_samples_through_on_every_channel() {
        let mut r = renderer(&[100, 200, 300], 2, SAMPLE_RATE);
        let mut out = [0i16; 8];
        r.fill(&mut out);
        // One sample of latency from the interpolation window, then the
        // source verbatim, duplicated per channel, silence once drained.
        assert_eq!(out, [0, 0, 100, 100, 200, 200, 300, 300]);
    }

    #[test]
    fn a_faster_device_gets_interpolated_samples() {
        let mut r = renderer(&[1000, 2000], 1, SAMPLE_RATE * 2);
        let mut out = [0i16; 6];
        r.fill(&mut out);
        // Two output samples per source sample, midpoints interpolated.
        assert_eq!(out, [0, 0, 500, 1000, 1500, 2000]);
    }

    #[test]
    fn f32_output_is_scaled_from_i16() {
        let mut r = renderer(&[i16::MAX, i16::MIN], 1, SAMPLE_RATE);
        let mut out = [0f32; 3];
        r.fill(&mut out);
        assert_eq!(out[0], 0.0);
        assert!((out[1] - 1.0).abs() < 1e-4);
        assert!((out[2] + 1.0).abs() < 1e-4);
    }

    #[test]
    fn resync_when_over_threshold() {
        // Backlog of 0.25 s exceeds the 0.2 s threshold -> resync.
        assert!(should_resync(0.25, PLAYBACK_RESYNC_S));
        // Boundary: exactly the threshold does NOT resync (`>`, not `>=`),
        // matching React's `start - currentTime > 0.2` strict comparison.
        assert!(!should_resync(PLAYBACK_RESYNC_S, PLAYBACK_RESYNC_S));
        // A healthy 0.15 s backlog stays put -- steady state never trips.
        assert!(!should_resync(0.15, PLAYBACK_RESYNC_S));
        // Empty ring never resyncs.
        assert!(!should_resync(0.0, PLAYBACK_RESYNC_S));
    }
}
