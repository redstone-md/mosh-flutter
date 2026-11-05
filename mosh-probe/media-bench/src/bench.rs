//! Two engine workers joined by an emulated link, driven like mosh-core
//! drives a call: offer, answer, start, then candidate ticks.
use crate::link::{Link, Shape};
use crate::{audio, frame};
use anyhow::{Context, Result, bail};
use serde_json::{Value, json};
use std::io::BufWriter;
use std::process::{Child, ChildStdin, Command, Stdio};
use std::sync::mpsc::{Receiver, Sender, channel};
use std::time::{Duration, Instant};

pub struct Options {
    pub engine: String,
    pub seconds: u64,
    pub shape: Shape,
    pub budget_bps: Option<u64>,
    /// Carry packets over two real Moss nodes instead of the emulated link.
    pub moss: bool,
}

struct Worker {
    child: Child,
    input: BufWriter<ChildStdin>,
}

pub struct Bench {
    workers: [Worker; 2],
    events: Receiver<(usize, u8, Vec<u8>)>,
    links: [Link; 2],
    replies: [Option<Value>; 2],
}

impl Bench {
    fn spawn(options: &Options) -> Result<Self> {
        let (tx, events) = channel();
        let mesh = options
            .moss
            .then(|| format!("mosh-bench-{}", std::process::id()));
        let caller = Self::worker(&options.engine, 0, mesh.as_deref(), &tx)?;
        let callee = Self::worker(&options.engine, 1, mesh.as_deref(), &tx)?;
        let mut bench = Self {
            workers: [caller, callee],
            events,
            links: [
                Link::new(options.shape, 0x9e37),
                Link::new(options.shape, 0x7f4a),
            ],
            replies: [None, None],
        };
        if options.moss {
            let hello = [bench.reply(0, "hello")?, bench.reply(1, "hello")?];
            for side in 0..2 {
                let other = &hello[1 - side];
                let address = format!("127.0.0.1:{}", other["port"]);
                let connect =
                    json!({"action": "connect", "address": address, "peer": other["peer"]});
                bench.ask(side, connect)?;
            }
        }
        Ok(bench)
    }

    fn worker(
        engine: &str,
        side: usize,
        mesh: Option<&str>,
        events: &Sender<(usize, u8, Vec<u8>)>,
    ) -> Result<Worker> {
        let role = if side == 0 { "caller" } else { "callee" };
        let mut child = Command::new(std::env::current_exe()?)
            .args(["worker", engine, role])
            .args(mesh)
            .env("PULSE_SERVER", audio::server(side))
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .spawn()?;
        let mut output = child.stdout.take().context("worker stdout")?;
        let events = events.clone();
        std::thread::spawn(move || {
            while let Ok((kind, payload)) = frame::read(&mut output) {
                if events.send((side, kind, payload)).is_err() {
                    break;
                }
            }
        });
        let input = BufWriter::new(child.stdin.take().context("worker stdin")?);
        Ok(Worker { child, input })
    }

    /// Moves packets for up to one millisecond.
    fn pump(&mut self) -> Result<()> {
        match self.events.recv_timeout(Duration::from_millis(1)) {
            Ok((side, frame::PACKET, packet)) => self.links[side].push(packet),
            Ok((side, frame::REPLY, reply)) => {
                self.replies[side] = Some(serde_json::from_slice(&reply)?)
            }
            Ok(_) | Err(std::sync::mpsc::RecvTimeoutError::Timeout) => {}
            Err(error) => bail!("worker exited: {error}"),
        }
        let now = Instant::now();
        for side in 0..2 {
            for packet in self.links[side].due(now) {
                frame::write(&mut self.workers[1 - side].input, frame::PACKET, &packet)?;
            }
        }
        Ok(())
    }

    fn ask(&mut self, side: usize, command: Value) -> Result<Value> {
        frame::write(
            &mut self.workers[side].input,
            frame::COMMAND,
            command.to_string().as_bytes(),
        )?;
        self.reply(side, command["action"].as_str().unwrap_or_default())
    }

    fn reply(&mut self, side: usize, action: &str) -> Result<Value> {
        let deadline = Instant::now() + Duration::from_secs(30);
        loop {
            if let Some(reply) = self.replies[side].take() {
                if let Some(error) = reply["error"].as_str() {
                    bail!("{action} on side {side}: {error}");
                }
                return Ok(reply);
            }
            anyhow::ensure!(Instant::now() < deadline, "{action} timed out");
            self.pump()?;
        }
    }

    fn connect(&mut self, options: &Options) -> Result<Duration> {
        let started = Instant::now();
        let offer = self.ask(0, json!({"action": "offer"}))?;
        let answer = self.ask(1, json!({"action": "remote", "description": offer}))?;
        self.ask(0, json!({"action": "remote", "description": answer}))?;
        for side in 0..2 {
            self.ask(
                side,
                json!({"action": "choices", "microphone": true, "video": false}),
            )?;
            self.ask(side, json!({"action": "start"}))?;
            self.ask(
                side,
                json!({"action": "select", "input": null, "output": null}),
            )?;
            if let Some(max) = options.budget_bps {
                self.ask(side, json!({"action": "budget", "max_bps": max}))?;
            }
        }
        let mut pending: [Vec<Value>; 2] = Default::default();
        loop {
            self.tick(&mut pending)?;
            let connected = (0..2).all(|side| {
                self.ask(side, json!({"action": "snapshot"}))
                    .is_ok_and(|s| {
                        matches!(s["connection"].as_str(), Some("Connected" | "Completed"))
                    })
            });
            if connected {
                return Ok(started.elapsed());
            }
            anyhow::ensure!(
                started.elapsed() < Duration::from_secs(30),
                "never connected"
            );
        }
    }

    fn tick(&mut self, pending: &mut [Vec<Value>; 2]) -> Result<()> {
        for side in 0..2 {
            let candidates = std::mem::take(&mut pending[side]);
            let reply = self.ask(side, json!({"action": "tick", "candidates": candidates}))?;
            if let Some(gathered) = reply["candidates"].as_array() {
                pending[1 - side].extend(gathered.iter().cloned());
            }
        }
        let until = Instant::now() + Duration::from_millis(20);
        while Instant::now() < until {
            self.pump()?;
        }
        Ok(())
    }

    fn cpu_seconds(&self) -> [f64; 2] {
        [0, 1].map(|side| {
            let stat =
                std::fs::read_to_string(format!("/proc/{}/stat", self.workers[side].child.id()))
                    .unwrap_or_default();
            let fields: Vec<&str> = stat
                .rsplit(')')
                .next()
                .unwrap_or("")
                .split_whitespace()
                .collect();
            let ticks: f64 = fields.get(11..13).map_or(0.0, |f| {
                f.iter().filter_map(|v| v.parse::<f64>().ok()).sum()
            });
            ticks / 100.0
        })
    }
}

impl Drop for Bench {
    fn drop(&mut self) {
        for worker in &mut self.workers {
            let _ = frame::write(&mut worker.input, frame::COMMAND, br#"{"action":"stop"}"#);
            let _ = worker.child.wait();
        }
    }
}

pub fn run(options: Options) -> Result<Value> {
    let mut bench = Bench::spawn(&options)?;
    let setup = bench.connect(&options).context("connect")?;
    let mut pending: [Vec<Value>; 2] = Default::default();
    let warmup = Instant::now() + Duration::from_secs(2);
    while Instant::now() < warmup {
        bench.tick(&mut pending)?;
    }
    let probe = audio::Probe::start(0, 1, options.shape.outage.is_some())?;
    let cpu_before = bench.cpu_seconds();
    let started = Instant::now();
    let mut next = started;
    while started.elapsed() < Duration::from_secs(options.seconds) {
        bench.tick(&mut pending)?;
        if Instant::now() >= next {
            next += Duration::from_secs(5);
            let snapshot = bench.ask(1, json!({"action": "snapshot"}))?;
            eprintln!(
                "{:>3}s callee audio {}",
                started.elapsed().as_secs(),
                snapshot["audio"]
            );
        }
    }
    let wall = started.elapsed().as_secs_f64();
    let cpu_after = bench.cpu_seconds();
    let cpu: Vec<f64> = (0..2)
        .map(|s| (cpu_after[s] - cpu_before[s]) * 100.0 / wall)
        .collect();
    let link = |link: &Link| {
        json!({"delivered": link.delivered, "lost": link.lost,
        "overflowed": link.overflowed})
    };
    let snapshots = [
        bench.ask(0, json!({"action": "snapshot"}))?,
        bench.ask(1, json!({"action": "snapshot"}))?,
    ];
    let mut delays = probe.delays_ms();
    let heard = delays.len();
    Ok(json!({
        "setup_ms": setup.as_millis() as u64,
        "recovery_ms": bench.links[0].outage_end()
            .and_then(|end| probe.sound_returns_after(end))
            .map(|after| after.as_millis() as u64),
        "mouth_to_ear_ms": audio::median(&mut delays),
        "bursts_heard": heard,
        "bursts_sent": options.seconds,
        "cpu_percent": cpu,
        "link": {"caller_to_callee": link(&bench.links[0]), "callee_to_caller": link(&bench.links[1])},
        "callee_audio": snapshots[1]["audio"],
        "caller_audio_sender": snapshots[0]["audio_sender"],
        "moss_carrier": [&snapshots[0]["carrier"], &snapshots[1]["carrier"]],
    }))
}

/// The harness's own delay: tone straight from the microphone sink to its monitor.
pub fn calibrate(seconds: u64) -> Result<Value> {
    let probe = audio::Probe::start(0, 0, false)?;
    std::thread::sleep(Duration::from_secs(seconds));
    let mut delays = probe.delays_ms();
    let all = delays.clone();
    Ok(json!({"harness_ms": audio::median(&mut delays), "bursts_heard": delays.len(), "all": all}))
}
