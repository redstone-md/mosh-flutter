//! Safe Moss adapter with feature-local ABI, callbacks, configuration, and node operations.
use crate::moss_runtime::{MossDynamicRuntime, MossRuntimeError};
use libloading::{Library, Symbol};
use std::{
    ffi::{c_void, CStr, CString},
    mem::ManuallyDrop,
    os::raw::c_char,
    sync::{Arc, LazyLock, Mutex, RwLock},
    time::Duration,
};

mod callbacks;
mod config;
mod identity;
mod info;
mod node;
mod packets;
mod runtime;
mod streams;
mod symbols;
#[cfg(test)]
mod test_faults;
#[cfg(debug_assertions)]
mod test_network;
#[cfg(test)]
mod tests;

pub use crate::stream_transport::STREAM_INBOX_CHANNEL_PREFIX;
#[cfg(test)]
pub use callbacks::clear_moss_keystore;
#[cfg(test)]
pub(crate) use callbacks::replace_test_keystore;
pub use callbacks::{
    clear_event_log, drain_received_messages, push_app_event, set_moss_keystore,
    snapshot_event_log, wait_for_payload,
};
use callbacks::{keystore_load, keystore_save, on_moss_event, on_moss_message, on_stream_payload};
pub use config::{current_bind_interface, node_config_json, set_bind_interface};
pub use info::library_version_once;
pub use packets::PACKET_INBOX_CHANNEL_PREFIX;
use symbols::*;
#[cfg(test)]
pub use test_faults::*;
#[cfg(test)]
pub static MOSS_TEST_LOCK: Mutex<()> = Mutex::new(());

const MOSS_OK: i32 = 0;
const MOSS_ERR_NO_PEERS: i32 = -6;
/// `Moss_Start` could not bind its listen port (moss errors.go).
const MOSS_ERR_LISTEN_FAILED: i32 = -13;
const DEFAULT_WAIT_MS: u64 = 3000;
const POLL_MS: u64 = 50;
// Ed25519 public keys are fixed at 32 bytes in the Moss ABI.
const MOSS_PUBKEY_LEN: usize = 32;

pub type MossHandle = i64;

pub trait MossKeyStore: Send + Sync {
    fn load_identity(&self) -> Option<Vec<u8>>;
    fn save_identity(&self, bytes: &[u8]);
}

#[derive(Clone, Debug)]
pub struct MossEvent {
    pub event_type: i32,
    pub detail_json: String,
    pub epoch_millis: u64,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct MossReceivedMessage {
    pub channel: String,
    pub payload: Vec<u8>,
}

#[derive(Debug)]
pub enum MossFfiError {
    Runtime(MossRuntimeError),
    Symbol(String),
    InvalidCString(String),
    Operation { name: &'static str, code: i32 },
    DeliveryTimeout,
    IdentityUnavailable,
    InjectedPublishFailure(String),
    NoPeers,
}

impl MossFfiError {
    /// True for the soft refusal a caller may want to swallow or retry, as
    /// opposed to a real transport or symbol failure.
    pub fn is_no_peers(&self) -> bool {
        matches!(self, Self::NoPeers)
    }

    /// True when `Moss_Start` could not bind its listen port.
    pub fn is_listen_failed(&self) -> bool {
        matches!(self, Self::Operation { code, .. } if *code == MOSS_ERR_LISTEN_FAILED)
    }
}

impl std::fmt::Display for MossFfiError {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Runtime(error) => write!(formatter, "{error}"),
            Self::Symbol(symbol) => write!(formatter, "Moss symbol unavailable: {symbol}"),
            Self::InvalidCString(value) => write!(formatter, "Moss string contains NUL: {value}"),
            Self::Operation { name, code } => write!(formatter, "Moss {name} failed: {code}"),
            Self::DeliveryTimeout => write!(formatter, "Moss delivery timed out"),
            Self::IdentityUnavailable => {
                write!(formatter, "Moss identity signer could not be verified")
            }
            Self::InjectedPublishFailure(message) => write!(formatter, "{message}"),
            Self::NoPeers => write!(formatter, "no peers yet, so the message did not go out"),
        }
    }
}

impl std::error::Error for MossFfiError {}

impl From<MossRuntimeError> for MossFfiError {
    fn from(error: MossRuntimeError) -> Self {
        Self::Runtime(error)
    }
}

pub struct MossFfiRuntime {
    _library: ManuallyDrop<Library>,
    init: MossInit,
    start: MossStart,
    stop: MossStop,
    subscribe: MossSubscribe,
    unsubscribe: MossSubscribe,
    join_room: MossJoinRoom,
    leave_room: MossSubscribe,
    subscribe_room: MossRoomChannel,
    unsubscribe_room: MossRoomChannel,
    publish_room: MossPublishRoom,
    connect: MossConnect,
    connect_to_peer: MossConnect,
    publish: MossPublish,
    set_callback: MossSetCallback,
    set_event_callback: MossSetEventCallback,
    get_mesh_info: MossGetMeshInfo,
    get_nat_type: MossGetNatType,
    get_public_key: MossGetPublicKey,
    free: MossFree,
    set_key_store: MossSetKeyStore,
    version: Option<MossVersionFn>,
    last_error: Option<MossLastErrorFn>,
    peer_rtt: Option<MossPeerRttFn>,
    open_stream: Option<MossOpenStreamFn>,
    send_stream: Option<MossSendStreamFn>,
    on_stream: Option<MossOnStreamFn>,
    send_to_peer: Option<MossSendToPeerFn>,
    set_packet_callback: Option<MossSetPacketCallbackFn>,
}

pub struct MossNode {
    runtime: Arc<MossFfiRuntime>,
    handle: MossHandle,
    identity_signer: Option<ed25519_dalek::SigningKey>,
}

#[derive(Debug, Clone, Default)]
pub struct MossNodeConfig {
    pub listen_port: u16,
    pub static_peer: Option<String>,
    pub bind_interface: Option<String>,
}
