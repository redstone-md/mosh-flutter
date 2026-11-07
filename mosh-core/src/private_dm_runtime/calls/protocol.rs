use serde::{Deserialize, Serialize};

/// Routing, identity and action are all inside the authenticated MLS message.
#[derive(Clone, Serialize, Deserialize)]
pub(super) struct CallControl {
    pub session_id: String,
    pub call_id: String,
    pub signer: String,
    pub sequence: u64,
    pub peer: String,
    pub name: String,
    pub action: CallAction,
    /// The sender's media engine protocol. Peers on different protocols
    /// cannot connect media, so they end the call with `update_required`.
    #[serde(default = "legacy_media_protocol")]
    pub media_protocol: u32,
}

/// Reason and call event kind for peers whose media engines cannot talk.
pub(super) const UPDATE_REQUIRED: &str = "update_required";

/// The call event recorded when a call ends for `reason`: an unanswered call
/// that a device refused for its engine asks to update Mosh too.
pub(super) fn end_kind(call: &crate::private_dm_runtime::CallState, reason: &str) -> &'static str {
    let kind = call.end_kind();
    if reason == UPDATE_REQUIRED || (call.refused_by_other_engine && kind == "missed") {
        UPDATE_REQUIRED
    } else {
        kind
    }
}

impl CallControl {
    /// Whether the sender's media engine can connect to ours.
    pub(super) fn same_media_protocol(&self) -> bool {
        self.media_protocol == crate::native_call::media_protocol()
    }
}

fn legacy_media_protocol() -> u32 {
    crate::native_call::LEGACY_MEDIA_PROTOCOL
}

#[derive(Clone, Serialize, Deserialize)]
pub(super) enum CallAction {
    Media(crate::native_call::types::Signal),
    /// Braced so an older client's offer, which carried its own media keys,
    /// still parses and ends with `update_required` instead of ringing on.
    Offer {},
    Answer,
    Occupied {
        caller: String,
        receiver: Option<String>,
    },
    Selected {
        receiver: String,
    },
    Decline {
        reason: String,
    },
    End {
        caller: String,
        reason: String,
    },
}

impl CallAction {
    /// The reason a `Decline` or `End` gives; empty for other actions.
    pub(super) fn end_reason(&self) -> &str {
        match self {
            Self::Decline { reason } | Self::End { reason, .. } => reason,
            _ => "",
        }
    }
}

impl crate::private_dm_runtime::CallState {
    pub(super) fn outbound_control(&self) -> Option<CallAction> {
        use crate::private_dm_runtime::{CallDirection, CallPhase};
        Some(match self.phase {
            CallPhase::Outgoing => CallAction::Offer {},
            CallPhase::Accepting => CallAction::Answer,
            CallPhase::Active if self.direction == CallDirection::Caller => CallAction::Selected {
                receiver: self.selected_signer.clone()?,
            },
            CallPhase::Active | CallPhase::Ringing => CallAction::Occupied {
                caller: self.caller_signer.clone(),
                receiver: self.selected_signer.clone(),
            },
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_control_from_before_media_protocols_speaks_the_legacy_one() {
        let control: CallControl = serde_json::from_value(serde_json::json!({
            "session_id": "s", "call_id": "c", "signer": "a", "sequence": 1,
            "peer": "p", "name": "n", "action": "Answer"
        }))
        .unwrap();
        assert_eq!(
            control.media_protocol,
            crate::native_call::LEGACY_MEDIA_PROTOCOL
        );
    }
}
