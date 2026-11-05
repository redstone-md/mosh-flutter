//! Mouth-to-ear delay through PulseAudio null sinks: tone bursts go into
//! the caller's microphone sink, and their onsets in that sink's monitor
//! and in the callee's speaker monitor are compared. Playback buffering
//! cancels out; a calibration run measures what remains.
use anyhow::Result;
use std::io::{Read, Write};
use std::process::{Child, Command, Stdio};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

const RATE: usize = 48_000;
const CHUNK: usize = RATE / 50;
const BURST: usize = RATE / 20;
const PERIOD: usize = RATE;

pub struct Probe {
    children: Vec<Child>,
    reference: Arc<Mutex<Vec<Instant>>>,
    heard: Arc<Mutex<Vec<Instant>>>,
}

/// One PulseAudio server per peer, so each engine's default devices are
/// its own microphone and speaker sinks; see README.md.
pub fn server(side: usize) -> String {
    let directory = std::env::var("MOSH_BENCH_PULSE").unwrap_or_else(|_| "/tmp/mosh-pa".into());
    format!("unix:{directory}/{}.sock", ["a", "b"][side])
}

fn pacat(mode: &str, side: usize, device: &str) -> Result<Child> {
    Ok(Command::new("pacat")
        .args([
            mode,
            "--server",
            &server(side),
            "--device",
            device,
            "--format=s16le",
            "--rate=48000",
            "--channels=1",
            "--latency-msec=10",
            "--process-time-msec=5",
            "--raw",
        ])
        .env("PULSE_LATENCY_MSEC", "10")
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()?)
}

/// Plays a 50 ms 1 kHz burst every second, paced in real time.
fn play(mut input: impl Write + Send + 'static) {
    std::thread::spawn(move || {
        let start = Instant::now();
        for chunk in 0usize.. {
            let bytes: Vec<u8> = (chunk * CHUNK..(chunk + 1) * CHUNK)
                .flat_map(|n| {
                    let sample = if n % PERIOD < BURST {
                        ((n as f64 / RATE as f64) * std::f64::consts::TAU * 1000.0).sin() * 12_000.0
                    } else {
                        0.0
                    };
                    (sample as i16).to_le_bytes()
                })
                .collect();
            if input.write_all(&bytes).is_err() {
                return;
            }
            let due = start + Duration::from_millis(20 * (chunk as u64 + 1));
            std::thread::sleep(due.saturating_duration_since(Instant::now()));
        }
    });
}

/// Timestamps the start of every burst a recording hears.
fn listen(mut output: impl Read + Send + 'static, onsets: Arc<Mutex<Vec<Instant>>>) {
    std::thread::spawn(move || {
        let mut buffer = [0u8; CHUNK * 2];
        let mut quiet = 0usize;
        while output.read_exact(&mut buffer).is_ok() {
            let arrived = Instant::now();
            for (i, pair) in buffer.chunks_exact(2).enumerate() {
                let level = i16::from_le_bytes([pair[0], pair[1]]).unsigned_abs();
                if level > 1500 && quiet > RATE / 4 {
                    let behind = Duration::from_secs_f64((CHUNK - i) as f64 / RATE as f64);
                    onsets.lock().unwrap().push(arrived - behind);
                }
                quiet = if level > 1500 { 0 } else { quiet + 1 };
            }
        }
    });
}

impl Probe {
    /// Bursts go into the `from` peer's microphone; its monitor is the
    /// reference and the `to` peer's speaker monitor is where they come out.
    pub fn start(from: usize, to: usize) -> Result<Self> {
        let mut player = pacat("--playback", from, "mic")?;
        let mut reference_recorder = pacat("--record", from, "mic.monitor")?;
        let mut recorder = pacat(
            "--record",
            to,
            if from == to {
                "mic.monitor"
            } else {
                "spk.monitor"
            },
        )?;
        let reference = Arc::new(Mutex::new(Vec::new()));
        let heard = Arc::new(Mutex::new(Vec::new()));
        listen(reference_recorder.stdout.take().unwrap(), reference.clone());
        listen(recorder.stdout.take().unwrap(), heard.clone());
        play(player.stdin.take().unwrap());
        Ok(Self {
            children: vec![player, reference_recorder, recorder],
            reference,
            heard,
        })
    }

    /// Delay from each burst at the microphone to its first onset at the speaker.
    pub fn delays_ms(&self) -> Vec<f64> {
        let reference = self.reference.lock().unwrap();
        let heard = self.heard.lock().unwrap();
        reference
            .iter()
            .filter_map(|sent| {
                let earliest = *sent - Duration::from_millis(20);
                heard
                    .iter()
                    .find(|at| {
                        **at >= earliest
                            && at.saturating_duration_since(*sent) < Duration::from_millis(900)
                    })
                    .map(|at| (at.saturating_duration_since(*sent)).as_secs_f64() * 1000.0)
            })
            .collect()
    }
}

impl Drop for Probe {
    fn drop(&mut self) {
        for child in &mut self.children {
            let _ = child.kill();
        }
    }
}

pub fn median(values: &mut [f64]) -> Option<f64> {
    if values.is_empty() {
        return None;
    }
    values.sort_by(f64::total_cmp);
    Some(values[values.len() / 2])
}
