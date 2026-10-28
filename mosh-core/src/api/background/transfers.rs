//! User gestures prepare durable work before Android accepts its execution job.
use super::execution;
use crate::api::conversation::{
    self, BridgeAttachmentPayload, BridgeConversationKind as Kind, BridgeConversationRef,
};
pub use crate::persistence::user_transfers::types::{
    UserTransfer, UserTransferDirection, UserTransferState,
};

pub fn prepare_user_attachment_transfer(
    reference: BridgeConversationRef,
    direction: UserTransferDirection,
    attachment_id: Option<String>,
    total_bytes: u64,
) -> Result<UserTransfer, String> {
    let _lease = execution::execution_lease()?;
    if !execution::automatic_downloads_allowed() {
        return Err("a visible user action is required".into());
    }
    let total_bytes = if direction == UserTransferDirection::Download {
        let attachment = attachment_id
            .as_deref()
            .ok_or("download attachment is missing")?;
        download_manifest(&reference, attachment)?
            .ok_or("download attachment is unavailable")?
            .total_size
    } else {
        total_bytes
    };
    execution::store()?
        .prepare_user_transfer(reference, direction, attachment_id, total_bytes)
        .map_err(|error| error.to_string())
}

pub fn send_user_attachment(id: String, payload: BridgeAttachmentPayload) -> Result<(), String> {
    let store = execution::store()?;
    let record = store
        .user_transfer(&id)
        .map_err(|error| error.to_string())?
        .ok_or("unknown user transfer")?;
    if record.view.direction != UserTransferDirection::Upload
        || record.view.state != UserTransferState::Prepared
    {
        return Err("upload admission is not prepared".into());
    }
    let result =
        conversation::send_attachment_admitted(record.view.target, payload, Some(id.clone()))
            .map_err(|error| error.to_string());
    if result.is_err()
        && store
            .user_transfer(&id)
            .map_err(|error| error.to_string())?
            .is_some()
    {
        store
            .set_user_transfer_state(&id, UserTransferState::Failed)
            .map_err(|error| error.to_string())?;
    }
    result
}

pub fn download_user_attachment(id: String) -> Result<(), String> {
    let store = execution::store()?;
    let record = store
        .user_transfer(&id)
        .map_err(|error| error.to_string())?
        .ok_or("unknown user transfer")?;
    if record.view.direction != UserTransferDirection::Download
        || record.view.state != UserTransferState::Prepared
    {
        return Err("download admission is not prepared".into());
    }
    let attachment = record
        .view
        .attachment_id
        .ok_or("download attachment is missing")?;
    bind(&record.view.target, &attachment, &id)?;
    let result = conversation::download_attachment(record.view.target, attachment)
        .map_err(|error| error.to_string());
    if result.is_err()
        && store
            .user_transfer(&id)
            .map_err(|error| error.to_string())?
            .is_some()
    {
        store
            .set_user_transfer_state(&id, UserTransferState::Failed)
            .map_err(|error| error.to_string())?;
    }
    result
}

pub fn cancel_user_attachment_transfer(id: String) -> Result<(), String> {
    let store = execution::store()?;
    let Some(record) = store
        .user_transfer(&id)
        .map_err(|error| error.to_string())?
    else {
        return Ok(()); // Durable deletion already retired this opaque operation.
    };
    if let Some(attachment) = record.view.attachment_id {
        // The kind flushes already verified checkpoint bytes and durably
        // revokes the admission before stopping its in-memory slot.
        if conversation::cancel_attachment(record.view.target, attachment).is_ok() {
            return Ok(());
        }
    }
    // A deleted conversation may already be absent from its runtime.
    store
        .set_user_transfer_state(&id, UserTransferState::Cancelled)
        .map_err(|error| error.to_string())?;
    Ok(())
}

pub fn resume_user_attachment_transfer(id: String) -> Result<(), String> {
    if !execution::automatic_downloads_allowed() {
        return Err("a visible user action is required".into());
    }
    let store = execution::store()?;
    let Some(record) = store
        .user_transfer(&id)
        .map_err(|error| error.to_string())?
    else {
        return Ok(());
    };
    let view = record.view;
    let attachment = view
        .attachment_id
        .ok_or("transfer has no published attachment")?;
    store
        .prepare_user_transfer(
            view.target.clone(),
            view.direction,
            Some(attachment.clone()),
            view.total_bytes,
        )
        .map_err(|error| error.to_string())?;
    if view.direction == UserTransferDirection::Download {
        download_user_attachment(id)
    } else {
        bind(&view.target, &attachment, &id)
    }
}

fn bind(
    reference: &BridgeConversationRef,
    attachment: &str,
    admission: &str,
) -> Result<(), String> {
    match reference.kind {
        Kind::Dm => crate::api::private_dm::ensure_runtime()
            .map_err(|error| error.to_string())?
            .bind_attachment_admission(&reference.id, attachment, admission)
            .map_err(|error| error.to_string()),
        Kind::Group => crate::api::private_group::ensure_runtime()
            .map_err(|error| error.to_string())?
            .bind_attachment_admission(&reference.id, attachment, admission)
            .map_err(|error| error.to_string()),
        Kind::Channel => crate::api::channel::ensure_runtime()
            .map_err(|error| error.to_string())?
            .bind_attachment_admission(&reference.id, attachment, admission)
            .map_err(|error| error.to_string()),
    }
}

fn download_manifest(
    reference: &BridgeConversationRef,
    attachment: &str,
) -> Result<Option<crate::attachment_runtime::AttachmentManifest>, String> {
    match reference.kind {
        Kind::Dm => crate::api::private_dm::ensure_runtime()
            .map_err(|error| error.to_string())?
            .download_manifest(&reference.id, attachment)
            .map_err(|error| error.to_string()),
        Kind::Group => crate::api::private_group::ensure_runtime()
            .map_err(|error| error.to_string())?
            .download_manifest(&reference.id, attachment)
            .map_err(|error| error.to_string()),
        Kind::Channel => crate::api::channel::ensure_runtime()
            .map_err(|error| error.to_string())?
            .download_manifest(&reference.id, attachment)
            .map_err(|error| error.to_string()),
    }
}
