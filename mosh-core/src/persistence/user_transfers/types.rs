//! User attachment execution is distinct from an offered or locally cached file.
use crate::api::conversation::BridgeConversationRef;
use crate::attachment_runtime::AttachmentManifest;
use flutter_rust_bridge::frb;
use serde::{Deserialize, Serialize};

#[frb(non_opaque)]
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum UserTransferDirection {
    Upload,
    Download,
}

#[frb(non_opaque)]
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum UserTransferState {
    Prepared,
    WaitingReceiver,
    WaitingExecution,
    Running,
    Paused,
    Complete,
    Failed,
    Cancelled,
}

#[frb(non_opaque)]
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct UserTransfer {
    pub id: String,
    pub target: BridgeConversationRef,
    pub attachment_id: Option<String>,
    pub direction: UserTransferDirection,
    pub state: UserTransferState,
    pub completed_bytes: u64,
    pub total_bytes: u64,
    pub revision: u64,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub(crate) struct TransferRecord {
    pub view: UserTransfer,
    pub manifest: Option<AttachmentManifest>,
    #[serde(default)]
    pub receivers: std::collections::BTreeMap<String, Receiver>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub(crate) struct Receiver {
    pub expires_ms: u64,
    pub complete: bool,
}
