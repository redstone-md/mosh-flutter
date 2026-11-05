//! One engine in its own process, so process-global native state never mixes.
use crate::{engine, frame};
use anyhow::Result;
use std::io::{BufWriter, stdin, stdout};
use std::sync::mpsc;
use std::time::Duration;

pub fn run(engine_path: &str, caller: bool) -> Result<()> {
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
    let mut out = BufWriter::new(stdout().lock());
    let mut buffer = [0; engine::MAX_PACKET];
    loop {
        match rx.recv_timeout(Duration::from_millis(1)) {
            Ok((frame::PACKET, packet)) => engine.receive(&packet),
            Ok((frame::COMMAND, command)) => {
                let command: serde_json::Value = serde_json::from_slice(&command)?;
                if command["action"] == "stop" {
                    return Ok(());
                }
                let reply = engine
                    .ask(&command)
                    .unwrap_or_else(|error| serde_json::json!({"error": error.to_string()}));
                frame::write(&mut out, frame::REPLY, reply.to_string().as_bytes())?;
            }
            Ok(_) => {}
            Err(mpsc::RecvTimeoutError::Timeout) => {}
            Err(mpsc::RecvTimeoutError::Disconnected) => return Ok(()),
        }
        while let Some(length) = engine.packet(&mut buffer) {
            frame::write(&mut out, frame::PACKET, &buffer[..length])?;
        }
    }
}
