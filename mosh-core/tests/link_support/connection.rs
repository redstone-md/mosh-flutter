//! A refused setup dial must reach the parent instead of killing its peer.
use super::{Peer, OBSERVATION_BUDGET};
use mosh_core::moss_ffi::{MossFfiError, MossNode};
use serde_json::{json, Value};
use std::time::{Duration, Instant};

const MOSS_ERR_CONNECT_FAILED: i32 = -10;

impl Peer {
    pub fn connect(&mut self, other: &Self) {
        // Public bridge scenarios deliberately rely on automatic discovery.
        if self.api {
            return;
        }
        let address = format!("127.0.0.1:{}", other.port);
        let command = json!({"action":"connect", "argument":address});
        let deadline = Instant::now() + OBSERVATION_BUDGET;
        let pause = Duration::from_millis(100);
        loop {
            let response = self.ask_until(command.clone(), deadline);
            if response["connected"] == true {
                return;
            }
            assert!(
                response["retryable"] == true && Instant::now() + pause < deadline,
                "connect to {address} failed within {OBSERVATION_BUDGET:?}: {response}"
            );
            std::thread::sleep(pause);
        }
    }
}

pub(super) fn command(node: &MossNode, address: &str) -> Value {
    match node.connect(address) {
        Ok(()) => json!({"connected":true}),
        Err(error) => json!({
            "connected":false,
            "retryable": matches!(&error, MossFfiError::Operation {
                name: "connect", code: MOSS_ERR_CONNECT_FAILED,
            }),
            "error": error.to_string(),
        }),
    }
}
