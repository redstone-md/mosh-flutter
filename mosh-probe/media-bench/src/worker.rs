//! One engine in its own process, so process-global native state never mixes.
//! Packets go to the bench over stdout, or straight over Moss with `mesh`.
use crate::{engine, frame, moss};
use anyhow::{Context, Result};
use std::io::{BufWriter, Write, stdin};
use std::sync::mpsc;
use std::time::Duration;

pub fn run(engine_path: &str, caller: bool, mesh: Option<&str>) -> Result<()> {
    let mut out = BufWriter::new(frames_out());
    let mut carrier = match mesh {
        Some(mesh) => {
            let (carrier, hello) = moss::Carrier::start(mesh)?;
            frame::write(&mut out, frame::REPLY, hello.to_string().as_bytes())?;
            Some(carrier)
        }
        None => None,
    };
    let config = serde_json::json!({"caller": caller, "binding": {
        "session_id": "bench-session", "call_id": "bench-call",
        "caller": "bench-caller", "callee": "bench-callee",
        "media_session": vec![7u8; 16]}});
    let engine = engine::Engine::load(engine_path, &config)?;
    let (tx, rx) = mpsc::channel();
    std::thread::spawn(move || {
        let mut input = stdin().lock();
        while let Ok(frame) = frame::read(&mut input) {
            if tx.send(frame).is_err() {
                break;
            }
        }
    });
    let mut buffer = [0; engine::MAX_PACKET];
    loop {
        match rx.recv_timeout(Duration::from_millis(1)) {
            Ok((frame::PACKET, packet)) => engine.receive(&packet),
            Ok((frame::COMMAND, command)) => {
                let command: serde_json::Value = serde_json::from_slice(&command)?;
                if command["action"] == "stop" {
                    return Ok(());
                }
                if command["action"] == "connect" {
                    let carrier = carrier.as_mut().context("connect needs --moss")?;
                    carrier.connect(
                        command["address"].as_str().context("address")?,
                        command["peer"].as_str().context("peer")?,
                    )?;
                    frame::write(&mut out, frame::REPLY, b"{}")?;
                    continue;
                }
                let mut reply = engine
                    .ask(&command)
                    .unwrap_or_else(|error| serde_json::json!({"error": error.to_string()}));
                if let Some(carrier) = carrier.as_ref().filter(|_| command["action"] == "snapshot")
                {
                    reply["carrier"] = carrier.stats();
                }
                frame::write(&mut out, frame::REPLY, reply.to_string().as_bytes())?;
            }
            Ok(_) => {}
            Err(mpsc::RecvTimeoutError::Timeout) => {}
            Err(mpsc::RecvTimeoutError::Disconnected) => return Ok(()),
        }
        if let Some(carrier) = &carrier {
            for packet in carrier.received() {
                engine.receive(&packet);
            }
        }
        while let Some(length) = engine.packet(&mut buffer) {
            match &carrier {
                Some(carrier) => carrier.send(buffer[..length].to_vec()),
                None => frame::write(&mut out, frame::PACKET, &buffer[..length])?,
            }
        }
    }
}

/// The frame channel. Moss's Go runtime may write to stdout, so frames get
/// a private duplicate and descriptor 1 is pointed at stderr.
#[cfg(unix)]
fn frames_out() -> impl Write {
    use std::os::fd::FromRawFd;
    // SAFETY: plain descriptor duplication; the duplicate is owned by File.
    unsafe {
        let private = libc::dup(1);
        libc::dup2(2, 1);
        std::fs::File::from_raw_fd(private)
    }
}

#[cfg(not(unix))]
fn frames_out() -> impl Write {
    std::io::stdout()
}
