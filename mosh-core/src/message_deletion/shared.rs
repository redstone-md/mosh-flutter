use super::{
    book::validate_selection,
    protocol::{DeleteAck, DeleteRequest, DeletionMessage},
    types::DeleteMessagesResult,
    DeleteScope, DeletionBook, DeletionRecord, DeletionStatus,
};
use crate::conversation::{
    message_log::{ConversationMessage, MessageLog},
    transfer::Transfer,
};
use crate::outbound_delivery::OutboundAttemptRecord;
use std::collections::HashMap;

pub(crate) struct DeletionActor {
    pub key: String,
    pub name: String,
    pub epoch: u64,
    pub ownership: Option<String>,
}

#[allow(clippy::too_many_arguments)] // All borrows belong to one existing conversation owner.
pub(crate) fn admit<M: ConversationMessage>(
    book: &mut DeletionBook,
    log: &mut MessageLog<M>,
    attempts: &mut HashMap<String, OutboundAttemptRecord>,
    transfer: &mut Transfer,
    ids: &[String],
    actor: &DeletionActor,
    permitted: impl Fn(&M) -> Option<bool>,
    sign: impl Fn(&[u8]) -> Result<String, String>,
) -> Result<DeleteMessagesResult, String> {
    if book.store.is_none() {
        return Err("shared deletion requires encrypted storage".into());
    }
    let selected = validate_selection(log, ids)?;
    let mut records = Vec::new();
    for message in log
        .iter()
        .filter(|m| m.message_id().is_some_and(|id| selected.contains(id)))
    {
        let moderated = permitted(message).ok_or("deletion permission denied")?;
        if message.is_service()
            || message
                .metadata()
                .and_then(|m| m.deletion.as_ref())
                .is_some()
        {
            return Err("message cannot be deleted for everyone".into());
        }
        let origin = message
            .metadata()
            .and_then(|m| m.origin.clone())
            .ok_or("unverified original author")?;
        let mut request = DeleteRequest {
            operation: crate::message_id::occurrence_id("delete"),
            target: origin,
            actor: actor.key.clone(),
            actor_name: actor.name.clone(),
            moderated,
            epoch: actor.epoch,
            signature: String::new(),
            ownership: actor.ownership.clone(),
        };
        request.signature = sign(&request.input()?)?;
        request.verify(&book.context)?;
        records.push(canonical(request, DeletionStatus::Pending, None)?);
    }
    book.install(log, attempts, transfer, &records)?;
    Ok(DeleteMessagesResult {
        deleted_count: records.len(),
        local_only_count: 0,
        pending_count: records.len(),
    })
}

pub(crate) fn canonical(
    request: DeleteRequest,
    status: DeletionStatus,
    acknowledgement: Option<DeleteAck>,
) -> Result<DeletionRecord, String> {
    Ok(DeletionRecord {
        context: request.target.conversation.clone(),
        key: request.target.key()?,
        scope: DeleteScope::ForEveryone,
        owner: String::new(),
        local_only: false,
        status,
        administrator: request.moderated.then(|| request.actor_name.clone()),
        request: Some(request),
        acknowledgement,
    })
}

pub(crate) fn verify_record<'a>(
    record: &'a DeletionRecord,
    context: &str,
) -> Result<&'a DeleteRequest, String> {
    let request = record.request.as_ref().ok_or("deletion request missing")?;
    request.verify(context)?;
    if (record.status == DeletionStatus::Confirmed) != record.acknowledgement.is_some() {
        return Err("deletion acknowledgement status mismatch".into());
    }
    if record
        != &canonical(
            request.clone(),
            record.status,
            record.acknowledgement.clone(),
        )?
    {
        return Err("deletion record mismatch".into());
    }
    if record.status == DeletionStatus::Confirmed {
        record
            .acknowledgement
            .as_ref()
            .ok_or("unconfirmed deletion")?
            .verify(request)?;
    }
    if record.status == DeletionStatus::Rejected {
        return Err("rejected deletion cannot be forwarded".into());
    }
    Ok(request)
}

#[allow(clippy::too_many_arguments)] // Saved state and the authenticated signing callback are separate concerns.
pub(crate) fn accept<M: ConversationMessage>(
    book: &mut DeletionBook,
    log: &mut MessageLog<M>,
    attempts: &mut HashMap<String, OutboundAttemptRecord>,
    transfer: &mut Transfer,
    record: &DeletionRecord,
    actor: &DeletionActor,
    may_ack: bool,
    sign: impl Fn(&[u8]) -> Result<String, String>,
) -> Result<Option<DeletionMessage>, String> {
    let request = verify_record(record, &book.context)?;
    if book.store.is_none() {
        return Err("cannot acknowledge unsaved deletion".into());
    }
    let mut accepted = record.clone();
    if accepted.acknowledgement.is_none() && may_ack && actor.key != request.actor {
        let mut acknowledgement = DeleteAck {
            request_digest: request.digest()?,
            actor: actor.key.clone(),
            signature: String::new(),
            ownership: actor.ownership.clone(),
        };
        acknowledgement.signature = sign(&acknowledgement.input()?)?;
        accepted.acknowledgement = Some(acknowledgement);
        accepted.status = DeletionStatus::Confirmed;
    }
    book.install(log, attempts, transfer, &[accepted.clone()])?;
    Ok(accepted
        .acknowledgement
        .filter(|ack| ack.actor == actor.key)
        .map(|acknowledgement| DeletionMessage::Ack {
            key: accepted.key,
            acknowledgement,
        }))
}

pub(crate) fn acknowledge<M: ConversationMessage>(
    book: &mut DeletionBook,
    log: &mut MessageLog<M>,
    attempts: &mut HashMap<String, OutboundAttemptRecord>,
    transfer: &mut Transfer,
    key: &str,
    acknowledgement: DeleteAck,
) -> Result<(), String> {
    let Some(mut record) = book
        .records
        .values()
        .find(|r| {
            r.key == key
                && r.request.as_ref().is_some_and(|q| {
                    q.digest().ok().as_deref() == Some(&acknowledgement.request_digest)
                })
        })
        .cloned()
    else {
        return Ok(());
    };
    if record.status == DeletionStatus::Rejected {
        return Ok(());
    }
    acknowledgement.verify(record.request.as_ref().ok_or("missing request")?)?;
    record.status = DeletionStatus::Confirmed;
    record.acknowledgement = Some(acknowledgement);
    book.install(log, attempts, transfer, &[record])
}

pub(crate) fn page(
    book: &DeletionBook,
    after: Option<&str>,
    authority: &super::authority::DeletionAuthority,
) -> DeletionMessage {
    let mut records: Vec<DeletionRecord> = Vec::new();
    let mut bytes = 0;
    let mut next = None;
    for (_, record) in book.records.iter().filter(|(key, r)| {
        r.scope == DeleteScope::ForEveryone
            && r.status != DeletionStatus::Rejected
            && authority.validate(r, &authority.local.key).is_ok()
            && after.is_none_or(|a| key.as_str() > a)
    }) {
        let length = serde_json::to_vec(record).map_or(60000, |b| b.len());
        if !records.is_empty() && (records.len() == 16 || bytes + length > 24000) {
            next = records.last().map(DeletionRecord::storage_key);
            break;
        }
        bytes += length;
        records.push(record.clone());
    }
    DeletionMessage::State { records, next }
}

pub(crate) fn digest(
    book: &DeletionBook,
    authority: &super::authority::DeletionAuthority,
) -> Result<String, String> {
    use sha2::{Digest, Sha256};
    let records: Vec<_> = book
        .records
        .values()
        .filter(|r| {
            r.scope == DeleteScope::ForEveryone
                && r.status != DeletionStatus::Rejected
                && authority.validate(r, &authority.local.key).is_ok()
        })
        .collect();
    Ok(hex::encode(Sha256::digest(
        serde_json::to_vec(&records).map_err(|e| e.to_string())?,
    )))
}
