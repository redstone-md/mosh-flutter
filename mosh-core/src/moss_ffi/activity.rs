//! Optional upstream waiting ABI. A missing symbol never means waiting succeeded.
use super::*;
use serde::{Deserialize, Serialize};

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub(crate) enum ActivityMode {
    Active,
    Waiting,
}

#[derive(Debug, Clone, Deserialize)]
pub(crate) struct ActivitySnapshot {
    pub activity_mode: ActivityMode,
    pub requested_activity_mode: ActivityMode,
    pub waiting_reachability: Option<String>,
    pub waiting_attachment_count: u32,
}

impl MossNode {
    pub(crate) fn supports_activity_mode(&self) -> bool {
        self.runtime.set_activity_mode.is_some()
    }

    pub(crate) fn set_activity_mode(&self, mode: ActivityMode) -> Result<(), MossFfiError> {
        let operation = self
            .runtime
            .set_activity_mode
            .ok_or_else(|| MossFfiError::Symbol("Moss_SetActivityMode".into()))?;
        let handle = self.handle()?;
        // SAFETY: the optional approved ABI uses int64 handle/int32 mode. The
        // read lease fences Stop/replacement until the synchronous call returns.
        check_code("set_activity_mode", unsafe {
            operation(*handle, i32::from(mode == ActivityMode::Waiting))
        })
    }

    pub(crate) fn activity_snapshot(&self) -> Option<ActivitySnapshot> {
        if !self.supports_activity_mode() {
            return None;
        }
        serde_json::from_str(&self.mesh_info_json()?).ok()
    }
}
