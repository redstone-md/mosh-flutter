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
}

#[derive(Clone, Serialize, Deserialize)]
pub(super) enum CallAction {
    Offer {
        key_b64: String,
        nonce_prefix_b64: String,
    },
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

impl crate::voice_call_runtime::CallState {
    pub(super) fn outbound_control(&self) -> Option<CallAction> {
        use crate::voice_call_runtime::{CallDirection, CallPhase};
        Some(match self.phase {
            CallPhase::Outgoing => CallAction::Offer {
                key_b64: self.key_b64.clone(),
                nonce_prefix_b64: self.nonce_prefix_b64.clone(),
            },
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
