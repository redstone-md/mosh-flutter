use std::sync::{Arc, Mutex};

use cpal::{BufferSize, StreamConfig};
use ringbuf::{traits::Producer, traits::Split, HeapRb};

use ringbuf::traits::{Consumer, Observer};

use super::{
    should_resync, trim_to_target, Renderer, PLAYBACK_RESYNC_S, PRIME_SAMPLES, SAMPLE_RATE,
};

/// A renderer over a ring holding `source`, for a device of `channels`
/// at `rate` Hz, that plays as soon as anything is buffered. The
/// resampling tests are about the samples, not the playout delay.
fn renderer(source: &[i16], channels: u16, rate: u32) -> Renderer {
    let mut r = renderer_with_prime(source, channels, rate, source.len().max(1));
    r.prime_samples = 1;
    r
}

fn renderer_with_prime(source: &[i16], channels: u16, rate: u32, capacity: usize) -> Renderer {
    let ring = HeapRb::<i16>::new(capacity);
    let (mut producer, consumer) = ring.split();
    producer.push_slice(source);
    let config = StreamConfig {
        channels,
        sample_rate: rate,
        buffer_size: BufferSize::Default,
    };
    Renderer::new(Arc::new(Mutex::new(consumer)), &config)
}

fn occupied(r: &Renderer) -> usize {
    r.consumer.lock().expect("lock").occupied_len()
}

#[test]
fn plays_silence_until_the_playout_delay_is_buffered() {
    let short = vec![1000i16; PRIME_SAMPLES - 1];
    let mut r = renderer_with_prime(&short, 1, SAMPLE_RATE, PRIME_SAMPLES * 2);
    let mut out = [7i16; 64];
    r.fill(&mut out);
    assert!(out.iter().all(|&sample| sample == 0));
    assert_eq!(occupied(&r), PRIME_SAMPLES - 1, "nothing was consumed");
}

#[test]
fn plays_once_the_playout_delay_is_buffered() {
    let full = vec![1000i16; PRIME_SAMPLES];
    let mut r = renderer_with_prime(&full, 1, SAMPLE_RATE, PRIME_SAMPLES * 2);
    let mut out = [0i16; 64];
    r.fill(&mut out);
    assert_eq!(out[0], 0, "one sample of interpolation latency");
    assert!(out[1..].iter().all(|&sample| sample == 1000));
}

#[test]
fn an_underrun_waits_for_the_delay_again() {
    let ring = HeapRb::<i16>::new(16);
    let (mut producer, consumer) = ring.split();
    producer.push_slice(&[5, 5, 5, 5]);
    let config = StreamConfig {
        channels: 1,
        sample_rate: SAMPLE_RATE,
        buffer_size: BufferSize::Default,
    };
    let mut r = Renderer::new(Arc::new(Mutex::new(consumer)), &config);
    r.prime_samples = 4;
    let mut out = [0i16; 8];
    r.fill(&mut out);
    assert_eq!(out, [0, 5, 5, 5, 5, 0, 0, 0], "played, then ran dry");

    // Two late samples are not enough to start again.
    producer.push_slice(&[9, 9]);
    let mut out = [1i16; 4];
    r.fill(&mut out);
    assert_eq!(out, [0, 0, 0, 0]);
    assert_eq!(occupied(&r), 2);
}

#[test]
fn a_long_backlog_is_trimmed_to_the_target_keeping_the_newest() {
    let ring = HeapRb::<i16>::new(16);
    let (mut producer, mut consumer) = ring.split();
    producer.push_slice(&[1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);
    trim_to_target(&mut consumer, 4);
    assert_eq!(consumer.occupied_len(), 4);
    let mut rest = [0i16; 4];
    consumer.pop_slice(&mut rest);
    assert_eq!(rest, [7, 8, 9, 10]);
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
    // Boundary: exactly the threshold does NOT resync (`>`, not `>=`).
    assert!(!should_resync(PLAYBACK_RESYNC_S, PLAYBACK_RESYNC_S));
    // A healthy 0.15 s backlog stays put -- steady state never trips.
    assert!(!should_resync(0.15, PLAYBACK_RESYNC_S));
    // Empty ring never resyncs.
    assert!(!should_resync(0.0, PLAYBACK_RESYNC_S));
}
