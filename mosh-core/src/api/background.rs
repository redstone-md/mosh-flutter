//! Installation execution, independent of chat unlock or mounted UI polling.
mod changes;
mod execution;
mod types;

use crate::frb_generated::StreamSink;
pub use crate::persistence::BackgroundNotification;
pub use types::{BackgroundMode, BackgroundReachability, BackgroundStatus};

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
    admit_user_work, automatic_downloads_allowed, execution_lease, network_permitted, reconcile,
};
