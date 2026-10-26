//! Installation execution, independent of chat unlock or mounted UI polling.
pub(crate) mod call_actions;
mod changes;
mod execution;
pub(crate) mod types;

use crate::frb_generated::StreamSink;
pub use crate::persistence::background_calls::{
    BackgroundCallAction, BackgroundCallNotification, BackgroundCallPhase,
};
pub use crate::persistence::BackgroundNotification;
pub(crate) use call_actions::owner_nonce as call_owner_nonce;
pub use call_actions::{BackgroundCallActionOutcome, BackgroundCallActionResult};
pub use types::{BackgroundMode, BackgroundReachability, BackgroundStatus};

/// Only opaque one-use action capabilities authorize a notification action.
pub fn apply_background_call_action(capability: String) -> BackgroundCallActionResult {
    call_actions::apply(&capability).unwrap_or_else(|_| {
        BackgroundCallActionResult::no(BackgroundCallActionOutcome::Unavailable)
    })
}

pub fn set_background_execution(
    interactive: bool,
    waiting_enabled: bool,
) -> Result<BackgroundStatus, String> {
    execution::set(interactive, waiting_enabled)
}

pub fn background_status() -> Result<BackgroundStatus, String> {
    let status = execution::status()?;
    changes::consumed(status.revision);
    Ok(status)
}

/// One replaceable coalesced hint subscriber; the encrypted queue is the truth.
pub fn watch_background_changes(sink: StreamSink<u64>) -> Result<(), String> {
    changes::watch(sink)
}

pub fn pending_background_notifications(limit: u32) -> Result<Vec<BackgroundNotification>, String> {
    let revision = changes::revision();
    let notifications = execution::store()?
        .pending_background_notifications(limit)
        .map_err(|e| e.to_string())?;
    changes::consumed(revision);
    Ok(notifications)
}

pub fn ack_background_notification(id: String, revision: u64) -> Result<(), String> {
    execution::store()?
        .ack_background_notification(&id, revision)
        .map_err(|e| e.to_string())
}

pub(crate) use changes::changed as background_delivery_changed;
pub(crate) use execution::{
    admit_user_work, automatic_downloads_allowed, execution_lease, history_execution_allowed,
    network_permitted, reconcile,
};

#[cfg(target_os = "android")]
pub(crate) use execution::notify_network_changed;
