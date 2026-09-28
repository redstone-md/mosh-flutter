use flutter_rust_bridge::frb;
use serde::{Deserialize, Serialize};

const INVALID_QR: &str = "invalid device link";
const EXPIRED: &str = "device link expired";
const BUSY: &str = "a device link is already active";
const INELIGIBLE: &str = "only a fresh desktop can join another user";
const CODE_MISMATCH: &str = "device code does not match";
const REJECTED: &str = "device link declined";
const CONNECTION_LOST: &str = "device link connection interrupted";
const INVALID_ROSTER: &str = "device authorization is invalid";
const STORAGE: &str = "device identity storage failed";
const UNAVAILABLE: &str = "device linking unavailable";

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[frb(non_opaque)]
pub struct DeviceDescriptor {
    pub device_id: String,
    pub signing_public_key: String,
    pub moss_peer_id: String,
    pub name: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[frb(non_opaque)]
pub enum DeviceLinkErrorKind {
    InvalidQr,
    Expired,
    Busy,
    Ineligible,
    CodeMismatch,
    Rejected,
    ConnectionLost,
    InvalidRoster,
    Storage,
    Unavailable,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[frb(non_opaque)]
pub struct DeviceLinkError {
    pub kind: DeviceLinkErrorKind,
    pub message: String,
}

impl DeviceLinkError {
    pub(crate) fn new(kind: DeviceLinkErrorKind) -> Self {
        let message = match kind {
            DeviceLinkErrorKind::InvalidQr => INVALID_QR,
            DeviceLinkErrorKind::Expired => EXPIRED,
            DeviceLinkErrorKind::Busy => BUSY,
            DeviceLinkErrorKind::Ineligible => INELIGIBLE,
            DeviceLinkErrorKind::CodeMismatch => CODE_MISMATCH,
            DeviceLinkErrorKind::Rejected => REJECTED,
            DeviceLinkErrorKind::ConnectionLost => CONNECTION_LOST,
            DeviceLinkErrorKind::InvalidRoster => INVALID_ROSTER,
            DeviceLinkErrorKind::Storage => STORAGE,
            DeviceLinkErrorKind::Unavailable => UNAVAILABLE,
        };
        Self {
            kind,
            message: message.into(),
        }
    }
}

impl std::fmt::Display for DeviceLinkError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.message)
    }
}

impl std::error::Error for DeviceLinkError {}

pub(crate) type Result<T> = std::result::Result<T, DeviceLinkError>;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[frb(non_opaque)]
pub enum DeviceLinkPhase {
    Idle,
    ShowingQr,
    Connecting,
    AwaitingApproval,
    AwaitingConfirmation,
    Delivering,
    Linked,
    Failed,
}

#[derive(Debug, Clone, Serialize)]
#[frb(non_opaque)]
pub struct DeviceLinkSnapshot {
    pub user_id: String,
    pub own_device_id: String,
    pub devices: Vec<DeviceDescriptor>,
    pub can_join: bool,
    pub phase: DeviceLinkPhase,
    pub qr_uri: Option<String>,
    pub expires_at: Option<u64>,
    pub confirmation_code: Option<String>,
    pub pending_device: Option<DeviceDescriptor>,
    pub error: Option<DeviceLinkErrorKind>,
}
