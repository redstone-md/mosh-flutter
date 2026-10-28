use super::*;

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[frb(non_opaque)]
#[serde(rename_all = "snake_case")]
pub enum BackgroundCallPhase {
    Incoming,
    Outgoing,
    Accepting,
    Active,
    Ended,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[frb(non_opaque)]
#[serde(rename_all = "snake_case")]
pub enum BackgroundCallAction {
    Answer,
    Decline,
    Hangup,
}

#[derive(Clone, Serialize, Deserialize)]
#[frb(non_opaque)]
pub struct BackgroundCallNotification {
    pub phase: BackgroundCallPhase,
    pub call_id: String,
    /// Zero is an ongoing call: its current native state remains authoritative.
    pub expires_at_ms: u64,
    pub answer_capability: Option<String>,
    pub decline_capability: Option<String>,
    pub hangup_capability: Option<String>,
}

impl std::fmt::Debug for BackgroundCallNotification {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("BackgroundCallNotification")
            .field("phase", &self.phase)
            .field("call_id", &self.call_id)
            .finish_non_exhaustive()
    }
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub(crate) struct BackgroundCallState {
    pub session_id: String,
    pub call_id: String,
    pub phase: BackgroundCallPhase,
    pub expires_at_ms: u64,
    pub sender: String,
    pub binding: String,
}

#[derive(Clone, Serialize, Deserialize)]
pub(super) struct CallRecord {
    pub id: String,
    pub owner: String,
    pub revision: u64,
    pub acknowledged: bool,
    pub state: BackgroundCallState,
    pub answer: Option<String>,
    pub decline: Option<String>,
    pub hangup: Option<String>,
}

impl CallRecord {
    pub(super) fn replace(
        &mut self,
        owner: &str,
        state: BackgroundCallState,
    ) -> Result<(), PersistenceError> {
        self.revision = self
            .revision
            .checked_add(1)
            .ok_or_else(|| PersistenceError::Json("call revision exhausted".into()))?;
        self.owner = owner.into();
        self.state = state;
        self.acknowledged = false;
        self.answer = (self.state.phase == BackgroundCallPhase::Incoming).then(capability);
        self.decline = (self.state.phase == BackgroundCallPhase::Incoming).then(capability);
        self.hangup = matches!(
            self.state.phase,
            BackgroundCallPhase::Outgoing
                | BackgroundCallPhase::Accepting
                | BackgroundCallPhase::Active
        )
        .then(capability);
        Ok(())
    }

    pub(super) fn notification(self) -> BackgroundNotification {
        BackgroundNotification {
            id: self.id,
            revision: self.revision,
            target: BridgeConversationRef {
                kind: BridgeConversationKind::Dm,
                id: self.state.session_id,
            },
            occurrence_id: self.state.call_id.clone(),
            sent_at_ms: 0,
            message_count: 0,
            sender: Some(self.state.sender),
            text: None,
            call: Some(BackgroundCallNotification {
                phase: self.state.phase,
                call_id: self.state.call_id,
                expires_at_ms: self.state.expires_at_ms,
                answer_capability: self.answer,
                decline_capability: self.decline,
                hangup_capability: self.hangup,
            }),
        }
    }
}

fn capability() -> String {
    hex::encode(rand::random::<[u8; 32]>())
}
