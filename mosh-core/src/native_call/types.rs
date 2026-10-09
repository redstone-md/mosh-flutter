use flutter_rust_bridge::frb;
use serde::{Deserialize, Serialize};

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub(crate) struct Binding {
    pub session_id: String,
    pub call_id: String,
    pub caller: String,
    pub callee: String,
    pub media_session: Vec<u8>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub(crate) struct Description {
    pub binding: Binding,
    pub offer: bool,
    pub parameters: Vec<u8>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub(crate) enum Signal {
    Description(Description),
    Candidates {
        nonce: Vec<u8>,
        candidates: Vec<String>,
    },
    Camera {
        nonce: Vec<u8>,
        enabled: bool,
    },
}

impl Signal {
    pub fn bounded(&self) -> bool {
        match self {
            Self::Description(description) => {
                description.parameters.len() <= 16_384
                    && description.binding.media_session.len() == 16
            }
            Self::Candidates { nonce, candidates } => {
                nonce.len() == 16
                    && candidates.len() <= 8
                    && candidates.iter().all(|candidate| candidate.len() <= 2048)
            }
            Self::Camera { nonce, .. } => nonce.len() == 16,
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct Context {
    pub session_id: String,
    pub call_id: String,
    pub superseded: Option<String>,
    pub active: bool,
    pub caller: bool,
    pub caller_signer: String,
    pub callee_signer: Option<String>,
    pub peer: String,
}

impl Context {
    pub fn binding(&self, nonce: Vec<u8>) -> Option<Binding> {
        self.active.then_some(Binding {
            session_id: self.session_id.clone(),
            call_id: self.call_id.clone(),
            caller: self.caller_signer.clone(),
            callee: self.callee_signer.clone()?,
            media_session: nonce,
        })
    }

    pub fn matches(&self, session: &str, call: &str) -> bool {
        self.session_id == session
            && (self.call_id == call || self.superseded.as_deref() == Some(call))
    }
}

#[frb(non_opaque)]
#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct Device {
    pub id: String,
    pub name: String,
    #[serde(default = "stable_device")]
    pub stable: bool,
}
fn stable_device() -> bool {
    true
}

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub(crate) struct Choices {
    pub microphone: bool,
    pub microphone_allowed: bool,
    pub camera: bool,
    pub input: Option<String>,
    pub output: Option<String>,
    pub camera_id: Option<String>,
}

#[frb(non_opaque)]
#[derive(Clone, Debug, Default, Serialize)]
pub struct Snapshot {
    pub session_id: String,
    pub call_id: String,
    pub ready: bool,
    pub microphone: bool,
    pub microphone_requested: bool,
    pub microphone_available: bool,
    pub camera: bool,
    pub camera_requested: bool,
    pub camera_starting: bool,
    pub camera_failed: bool,
    pub remote_camera: bool,
    pub reconnecting: bool,
    pub failed: bool,
    pub encoder: Option<String>,
    pub codec: Option<String>,
    pub video_width: u32,
    pub video_height: u32,
    pub video_fps: f64,
    pub packets_dropped: u64,
    pub inputs: Vec<Device>,
    pub outputs: Vec<Device>,
    pub cameras: Vec<Device>,
    pub input: Option<String>,
    pub output: Option<String>,
    pub camera_id: Option<String>,
}

#[frb(non_opaque)]
#[derive(Clone)]
pub struct Frame {
    pub session_id: String,
    pub call_id: String,
    pub sequence: u64,
    pub width: u32,
    pub height: u32,
    pub local: bool,
    pub source_age_ms: u32,
    pub pixels: Vec<u8>,
}

// Pixels must not be included in diagnostic output.
impl std::fmt::Debug for Frame {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("Frame")
            .field("sequence", &self.sequence)
            .field("width", &self.width)
            .field("height", &self.height)
            .finish_non_exhaustive()
    }
}
