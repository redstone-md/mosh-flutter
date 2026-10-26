//! One attachment owner borrows durable admissions; OS grants remain memory-only.
use super::*;
use crate::api::conversation::{BridgeConversationKind as Kind, BridgeConversationRef};
use crate::conversation::attachments::AttachmentState;
use crate::persistence::user_transfers::types::{
    UserTransferDirection as Direction, UserTransferState as State,
};
use crate::persistence::{HistoryTables, Persistence};

pub(super) struct Execution {
    pub(super) store: Arc<Persistence>,
    pub(super) target: BridgeConversationRef,
    pub(super) admissions: HashMap<String, Admission>,
    pub(super) error: Option<String>,
    pub(super) serving: super::serving::Serving,
    pub(super) checkpoints: HashMap<String, Vec<ChunkFrame>>,
}

#[derive(Clone)]
pub(super) struct Admission {
    pub(super) id: String,
    pub(super) direction: Direction,
    pub(super) state: State,
}

impl Transfer {
    pub(crate) fn attach_execution(
        &mut self,
        store: Arc<Persistence>,
        tables: HistoryTables,
        id: &str,
    ) {
        let kind = match tables.outbound_scope {
            "private_dm" => Kind::Dm,
            "private_group" => Kind::Group,
            "channel" => Kind::Channel,
            _ => return,
        };
        let target = BridgeConversationRef {
            kind,
            id: id.into(),
        };
        let mut context = Execution {
            store,
            target,
            admissions: HashMap::new(),
            error: None,
            serving: Default::default(),
            checkpoints: Default::default(),
        };
        match context.store.user_transfers() {
            Ok(records) => {
                for record in records
                    .into_iter()
                    .filter(|record| record.target == context.target)
                {
                    if let Some(id) = record.attachment_id {
                        context.admissions.insert(
                            id,
                            Admission {
                                id: record.id,
                                direction: record.direction,
                                state: record.state,
                            },
                        );
                    }
                }
            }
            Err(error) => context.error = Some(error.to_string()),
        }
        self.execution = Some(context);
        self.restore_execution_checkpoints();
    }

    pub(crate) fn bind_user_admission(
        &mut self,
        id: Option<&str>,
        manifest: &AttachmentManifest,
    ) -> Result<(), TransferError> {
        let Some(id) = id else {
            return Ok(());
        };
        let context = self
            .execution
            .as_mut()
            .ok_or_else(|| TransferError::Bytes("transfer storage unavailable".into()))?;
        context
            .store
            .bind_user_transfer(id, &context.target, manifest)
            .map_err(|error| TransferError::Bytes(error.to_string()))?;
        let record = context
            .store
            .user_transfer(id)
            .map_err(|error| TransferError::Bytes(error.to_string()))?
            .ok_or_else(|| TransferError::Bytes("transfer admission missing".into()))?;
        context.error = None;
        context.admissions.insert(
            manifest.attachment_id.clone(),
            Admission {
                id: id.into(),
                direction: record.view.direction,
                state: record.view.state,
            },
        );
        Ok(())
    }
}

impl Transfer {
    pub(crate) fn download_manifest(&self, id: &str) -> Option<AttachmentManifest> {
        self.slots
            .incoming(id)
            .then(|| self.manifest_for(id))
            .flatten()
    }

    pub(crate) fn bind_download_admission(
        &mut self,
        attachment_id: &str,
        id: &str,
    ) -> Result<(), TransferError> {
        let manifest = self
            .manifest_for(attachment_id)
            .ok_or_else(|| TransferError::Bytes("unknown attachment manifest".into()))?;
        self.bind_user_admission(Some(id), &manifest)?;
        if !self.slots.incoming(attachment_id) {
            self.slots.resume_sent(attachment_id);
            self.runtime.resume_outgoing(attachment_id);
        }
        Ok(())
    }

    pub(super) fn execution_allowed(&self, attachment_id: &str) -> bool {
        if !crate::api::background::managed_execution()
            || crate::api::background::automatic_downloads_allowed()
        {
            return true;
        }
        let Some(context) = &self.execution else {
            return false;
        };
        if context.error.is_some() {
            return false;
        }
        let id = attachment_id
            .strip_suffix("/preview")
            .unwrap_or(attachment_id);
        let Some(admission) = context.admissions.get(id) else {
            return false;
        };
        #[cfg(target_os = "android")]
        {
            crate::api::background::transfer_grants::allowed(&admission.id)
        }
        #[cfg(not(target_os = "android"))]
        {
            let _ = admission;
            false
        }
    }

    pub(super) fn may_download(&self, attachment_id: &str) -> bool {
        if self.is_preview(attachment_id) {
            crate::api::background::automatic_downloads_allowed()
        } else {
            self.execution_allowed(attachment_id)
        }
    }

    pub(super) fn require_download_admission(
        &self,
        attachment_id: &str,
    ) -> Result<(), TransferError> {
        if self.is_preview(attachment_id) || !crate::api::background::managed_execution() {
            return Ok(());
        }
        let context = self
            .execution
            .as_ref()
            .ok_or_else(|| TransferError::Bytes("transfer storage unavailable".into()))?;
        if let Some(error) = &context.error {
            return Err(TransferError::Bytes(error.clone()));
        }
        let id = context
            .admissions
            .get(attachment_id)
            .ok_or_else(|| TransferError::Bytes("user transfer admission missing".into()))?;
        let record = context
            .store
            .user_transfer(&id.id)
            .map_err(|error| TransferError::Bytes(error.to_string()))?
            .ok_or_else(|| TransferError::Bytes("user transfer admission missing".into()))?;
        if record.view.direction != Direction::Download || record.view.state == State::Cancelled {
            return Err(TransferError::Bytes(
                "download admission is not active".into(),
            ));
        }
        Ok(())
    }

    pub(super) fn cancel_execution(&self, attachment_id: &str) -> Result<(), TransferError> {
        if let Some(context) = &self.execution {
            if let Some(id) = context.admissions.get(attachment_id) {
                context
                    .store
                    .set_user_transfer_state(&id.id, State::Cancelled)
                    .map_err(|error| TransferError::Bytes(error.to_string()))?;
            }
        }
        Ok(())
    }

    pub(super) fn forget_execution(&mut self, attachment_id: &str) {
        let Some(context) = &mut self.execution else {
            return;
        };
        if let Some(id) = context.admissions.remove(attachment_id) {
            if let Err(error) = context.store.remove_user_transfer(&id.id) {
                context.error = Some(error.to_string());
            }
        }
    }
}

impl Transfer {
    /// Persist only genuine state transitions, never another write per UI poll.
    pub(crate) fn refresh_execution(&mut self) -> Result<(), TransferError> {
        self.flush_checkpoints()?;
        self.refresh_serving()?;
        let Some(context) = &self.execution else {
            return Ok(());
        };
        let raw: HashMap<_, _> = self
            .slots
            .views(&self.runtime)
            .into_iter()
            .map(|view| (view.attachment_id, view.state))
            .collect();
        let updates: Vec<_> = context
            .admissions
            .iter()
            .filter_map(|(attachment, admission)| {
                if admission.direction != Direction::Download || admission.state == State::Cancelled
                {
                    return None;
                }
                let state = match raw.get(attachment)? {
                    AttachmentState::Available => State::Complete,
                    AttachmentState::Failed => State::Failed,
                    AttachmentState::Cancelled => State::Cancelled,
                    AttachmentState::Downloading => {
                        if self.may_download(attachment) {
                            State::Running
                        } else {
                            State::Paused
                        }
                    }
                    _ => return None,
                };
                (state != admission.state).then(|| (attachment.clone(), state))
            })
            .collect();
        let context = self.execution.as_mut().unwrap();
        for (attachment, state) in updates {
            let admission = context.admissions.get_mut(&attachment).unwrap();
            context
                .store
                .set_user_transfer_state(&admission.id, state)
                .map_err(|error| TransferError::Bytes(error.to_string()))?;
            admission.state = state;
        }
        Ok(())
    }
}
