//! Real Moss between the two workers: each starts its own node, the bench
//! connects them over loopback, and media goes as directed Moss packets
//! through the media host's bounded carrier.
use anyhow::{Context, Result};
use mosh_core::moss_ffi::{
    MossFfiRuntime, MossNode, PACKET_INBOX_CHANNEL_PREFIX, drain_received_messages,
};
use serde_json::{Value, json};
use std::sync::Arc;

#[path = "../../media-host/src/transport.rs"]
mod transport;

pub struct Carrier {
    node: Arc<MossNode>,
    send: Option<Box<dyn Fn(Vec<u8>) + Send + Sync>>,
    transport: Option<transport::Transport>,
    channel: String,
}

impl Carrier {
    /// Starts a node without discovery or trackers; returns it with the
    /// identity the other worker connects to.
    pub fn start(mesh: &str) -> Result<(Self, Value)> {
        let runtime = Arc::new(MossFfiRuntime::load_default()?);
        let config = json!({"trackers": [], "listen_port": 0, "dht_enabled": false,
            "lan_discovery_enabled": false,
            "nat": {"upnp_enabled": false, "natpmp_enabled": false, "pcp_enabled": false}});
        let node = Arc::new(runtime.init_node(mesh, &config.to_string())?);
        node.set_packet_callback()?;
        node.start()?;
        let info: Value = serde_json::from_str(&node.mesh_info_json().context("Moss info")?)?;
        let hello = json!({"peer": node.public_key_hex(), "port": info["listen_port"]});
        let carrier = Self {
            node,
            send: None,
            transport: None,
            channel: String::new(),
        };
        Ok((carrier, hello))
    }

    pub fn connect(&mut self, address: &str, peer: &str) -> Result<()> {
        self.node.connect(address)?;
        let transport = transport::Transport::new(self.node.clone(), peer.into());
        self.send = Some(Box::new(transport.sender()));
        self.transport = Some(transport);
        self.channel = format!("{PACKET_INBOX_CHANNEL_PREFIX}{peer}");
        Ok(())
    }

    pub fn send(&self, packet: Vec<u8>) {
        if let Some(send) = &self.send {
            send(packet);
        }
    }

    /// Carrier counters; null before `connect`.
    pub fn stats(&self) -> Value {
        self.transport
            .as_ref()
            .map_or(Value::Null, transport::Transport::snapshot)
    }

    pub fn received(&self) -> Vec<Vec<u8>> {
        drain_received_messages()
            .into_iter()
            .filter(|message| {
                message.channel == self.channel && message.payload.starts_with(transport::MAGIC)
            })
            .map(|message| message.payload)
            .collect()
    }
}
