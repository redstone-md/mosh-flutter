//! Per-receiver request leases: a local cache is never an upload completion.
use super::*;
use crate::attachment_runtime::execution::{RequestExecution, RequestPhase as Phase};
use crate::persistence::user_transfers::types::{
    UserTransferDirection as Direction, UserTransferState as State,
};
use std::time::Duration;

#[derive(Default)]
pub(super) struct Serving {
    pending: HashMap<(String, String, String), Pending>,
    tokens: HashMap<String, String>,
    receipts: HashMap<String, (ChunkRequest, Instant, u8)>,
    replies: Vec<ChunkRequest>,
    served: HashMap<String, std::collections::BTreeSet<u64>>,
}
struct Pending {
    request: ChunkRequest,
    expires: Instant,
}

impl Transfer {
    pub(crate) fn may_send_chunk(&self, id: &str) -> bool {
        self.execution_allowed(id)
    }

    pub(crate) fn active_user_transfers(&self) -> usize {
        self.views()
            .iter()
            .filter(|view| view.state == super::super::attachments::AttachmentState::Downloading)
            .count()
            + self.execution.as_ref().map_or(0, |context| {
                context
                    .admissions
                    .iter()
                    .filter(|(attachment, admission)| {
                        admission.direction == Direction::Upload
                            && self.execution_allowed(attachment)
                            && context.serving.pending.values().any(|pending| {
                                pending.request.attachment_id == **attachment
                                    && pending.expires > Instant::now()
                                    && !pending.request.chunk_indices.is_empty()
                            })
                    })
                    .count()
            })
    }

    pub(super) fn refresh_serving(&mut self) -> Result<(), TransferError> {
        let Some(context) = &self.execution else {
            return Ok(());
        };
        let now = Instant::now();
        let updates: Vec<_> = context
            .admissions
            .iter()
            .filter_map(|(attachment, admission)| {
                if admission.direction != Direction::Upload {
                    return None;
                }
                let record = match context.store.user_transfer(&admission.id) {
                    Ok(Some(record)) => record,
                    _ => return None,
                };
                if matches!(
                    record.view.state,
                    State::Cancelled | State::Failed | State::Prepared | State::Complete
                ) {
                    return None;
                }
                let pending = context.serving.pending.values().any(|pending| {
                    pending.request.attachment_id == *attachment
                        && pending.expires > now
                        && !pending.request.chunk_indices.is_empty()
                });
                let state = if !pending {
                    State::WaitingReceiver
                } else if self.execution_allowed(attachment) {
                    State::Running
                } else {
                    State::WaitingExecution
                };
                (record.view.state != state).then(|| (admission.id.clone(), state))
            })
            .collect();
        let context = self.execution.as_mut().unwrap();
        context
            .serving
            .pending
            .retain(|_, value| value.expires > now);
        for (id, state) in updates {
            context
                .store
                .set_user_transfer_state(&id, state)
                .map_err(|error| TransferError::Bytes(error.to_string()))?;
        }
        Ok(())
    }

    pub(super) fn admit_serving(&mut self, request: &ChunkRequest) -> bool {
        let Some(context) = self.execution.as_ref() else {
            return !crate::api::background::managed_execution();
        };
        let Some(metadata) = &request.execution else {
            return crate::api::background::automatic_downloads_allowed();
        };
        let target = transfer_context(&context.target);
        let Ok(Some(author)) = request.verify_execution(&target) else {
            return false;
        };
        let key = (
            request.attachment_id.clone(),
            metadata.receiver.clone(),
            metadata.token.clone(),
        );
        if metadata.phase == Phase::Ack {
            self.accept_completion_ack(request, author);
            return false;
        }
        let Some(admission) = context.admissions.get(&request.attachment_id).cloned() else {
            return metadata.phase == Phase::Request
                && crate::api::background::automatic_downloads_allowed();
        };
        if admission.direction != Direction::Upload {
            return false;
        }
        let Ok(Some(record)) = context.store.user_transfer(&admission.id) else {
            return false;
        };
        if record.view.state == State::Cancelled {
            return false;
        }
        if metadata.phase == Phase::Complete {
            let result = context.store.remember_user_transfer_receiver(
                &admission.id,
                &metadata.receiver,
                &metadata.token,
                metadata.expires_ms,
                true,
            );
            if result.is_ok() {
                let mut ack = request.clone();
                ack.execution.as_mut().unwrap().phase = Phase::Ack;
                ack.execution.as_mut().unwrap().proof = None;
                let context = self.execution.as_mut().unwrap();
                if context.serving.replies.len() < 64 {
                    context.serving.replies.push(ack);
                }
            }
            return false;
        }
        if let Err(error) = context.store.remember_user_transfer_receiver(
            &admission.id,
            &metadata.receiver,
            &metadata.token,
            metadata.expires_ms,
            false,
        ) {
            self.execution.as_mut().unwrap().error = Some(error.to_string());
            return false;
        }
        let now = Instant::now();
        let allowed = self.execution_allowed(&request.attachment_id);
        let context = self.execution.as_mut().unwrap();
        context
            .serving
            .pending
            .retain(|_, value| value.expires > now);
        if context.serving.pending.len() >= 64 && !context.serving.pending.contains_key(&key) {
            return false;
        }
        context.serving.pending.insert(
            key,
            Pending {
                request: request.clone(),
                expires: now + Duration::from_secs(120),
            },
        );
        if !allowed {
            let _ = context
                .store
                .set_user_transfer_state(&admission.id, State::WaitingExecution);
        }
        allowed
    }

    pub(crate) fn pending_serving_requests(&mut self) -> Vec<ChunkRequest> {
        let Some(context) = &self.execution else {
            return Vec::new();
        };
        let now = Instant::now();
        let requests: Vec<_> = context
            .serving
            .pending
            .values()
            .filter(|pending| {
                pending.expires > now
                    && !pending.request.chunk_indices.is_empty()
                    && self.execution_allowed(&pending.request.attachment_id)
            })
            .map(|pending| pending.request.clone())
            .collect();
        // The kind revalidates current membership before serving these saved
        // requests. This is not a trusted bypass around its receive boundary.
        for request in &requests {
            let metadata = request.execution.as_ref().unwrap();
            if let Some(pending) = self.execution.as_mut().unwrap().serving.pending.get_mut(&(
                request.attachment_id.clone(),
                metadata.receiver.clone(),
                metadata.token.clone(),
            )) {
                pending.request.chunk_indices.clear();
            }
        }
        requests
    }

    pub(crate) fn chunks_published(&mut self, frames: &[ChunkFrame]) {
        let Some(context) = &mut self.execution else {
            return;
        };
        for frame in frames {
            let Some(admission) = context.admissions.get(&frame.attachment_id) else {
                continue;
            };
            if admission.direction != Direction::Upload {
                continue;
            }
            for pending in context
                .serving
                .pending
                .values_mut()
                .filter(|pending| pending.request.attachment_id == frame.attachment_id)
            {
                pending
                    .request
                    .chunk_indices
                    .retain(|index| *index != frame.chunk_index);
            }
            let served = context
                .serving
                .served
                .entry(frame.attachment_id.clone())
                .or_default();
            if !served.insert(frame.chunk_index) {
                continue;
            }
            if let Ok(Some(record)) = context.store.user_transfer(&admission.id) {
                if record.view.state == State::Cancelled {
                    continue;
                }
                if let Some(manifest) = record.manifest {
                    let bytes = served
                        .iter()
                        .map(|index| {
                            u64::from(manifest.chunk_size).min(
                                manifest
                                    .total_size
                                    .saturating_sub(index * u64::from(manifest.chunk_size)),
                            )
                        })
                        .sum();
                    if let Err(error) =
                        context
                            .store
                            .record_user_upload_progress(&admission.id, bytes, false)
                    {
                        context.error = Some(error.to_string());
                    }
                }
            }
        }
    }

    pub(super) fn decorate_requests(&mut self, requests: &mut Vec<ChunkRequest>) {
        let Some(context) = &mut self.execution else {
            return;
        };
        for request in requests.iter_mut() {
            let token = context
                .serving
                .tokens
                .entry(request.attachment_id.clone())
                .or_insert_with(|| {
                    context
                        .admissions
                        .get(&request.attachment_id)
                        .and_then(|admission| admission.id.strip_prefix("transfer-"))
                        .map(str::to_owned)
                        .unwrap_or_else(|| hex::encode(rand::random::<[u8; 16]>()))
                });
            request.execution = Some(RequestExecution {
                token: token.clone(),
                phase: Phase::Request,
                receiver: String::new(),
                proof: None,
                expires_ms: 0,
            });
        }
        requests.append(&mut context.serving.replies);
        let now = Instant::now();
        for (request, after, attempts) in context.serving.receipts.values_mut() {
            if *attempts < 6 && *after <= now {
                requests.push(request.clone());
                *attempts += 1;
                *after = now + Duration::from_secs(10);
            }
        }
    }

    pub(super) fn queue_completion(&mut self, attachment: &str) {
        if self.is_preview(attachment) {
            return;
        }
        let Some(context) = &mut self.execution else {
            return;
        };
        let Some(token) = context.serving.tokens.get(attachment) else {
            return;
        };
        let request = ChunkRequest {
            attachment_id: attachment.into(),
            chunk_indices: Vec::new(),
            execution: Some(RequestExecution {
                token: token.clone(),
                phase: Phase::Complete,
                receiver: String::new(),
                proof: None,
                expires_ms: 0,
            }),
        };
        context
            .serving
            .receipts
            .insert(attachment.into(), (request, Instant::now(), 0));
    }

    fn accept_completion_ack(&mut self, request: &ChunkRequest, author: &str) {
        let Some(manifest) = self.manifest_for(&request.attachment_id) else {
            return;
        };
        if manifest
            .origin
            .as_ref()
            .is_none_or(|origin| origin.author != author)
        {
            return;
        }
        let context = self.execution.as_mut().unwrap();
        if let Some((receipt, _, _)) = context.serving.receipts.get(&request.attachment_id) {
            if receipt.execution.as_ref().unwrap().token
                == request.execution.as_ref().unwrap().token
            {
                context.serving.receipts.remove(&request.attachment_id);
            }
        }
    }
}

pub(crate) fn transfer_context(target: &crate::api::conversation::BridgeConversationRef) -> String {
    use crate::api::conversation::BridgeConversationKind as Kind;
    format!(
        "transfer:{}:{}",
        match target.kind {
            Kind::Dm => "dm",
            Kind::Group => "group",
            Kind::Channel => "channel",
        },
        target.id
    )
}
