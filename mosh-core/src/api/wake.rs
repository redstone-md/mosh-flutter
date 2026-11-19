//! Waking iPhones through the build's wake service, for DMs and groups
//! alike (conversation::wake). Each runtime keeps its own chats' wake
//! state; this is where Dart reaches both. Asking never starts a runtime:
//! until something else does, nothing can be waiting in it.

use std::sync::Mutex;

use crate::conversation::wake::preview::PreviewChat;
use crate::conversation::wake::WakeSetup;
pub use crate::conversation::wake::{WakeAddress, WakeRequest};
use crate::diagnostics_log::{self as dlog, kinds, LogLevel};

/// What a runtime started later learns at its start.
static SETUP: Mutex<WakeSetup> = Mutex::new(WakeSetup {
    own: None,
    service: None,
});

/// The wake setup so far, for a runtime starting now.
pub(crate) fn setup() -> WakeSetup {
    SETUP.lock().map(|setup| setup.clone()).unwrap_or_default()
}

/// This installation's wake address, announced in every chat so members
/// can wake it through their wake service. An empty handle withdraws it.
pub fn set_wake_address(service: String, handle: String) {
    let address = WakeAddress { service, handle };
    let line = if address.withdrawn() {
        "wake address withdrawn"
    } else {
        "wake address set"
    };
    dlog::write(LogLevel::Info, kinds::WAKE, "wake", line);
    update(|setup| setup.own = Some(address));
}

/// The build's wake service: members are woken only through it, whatever
/// service they announce.
pub fn set_wake_service(service: String) {
    update(|setup| setup.service = Some(service));
}

/// Changes the setup and hands it to both runtimes, if started.
fn update(change: impl FnOnce(&mut WakeSetup)) {
    let Ok(mut held) = SETUP.lock() else {
        return;
    };
    change(&mut held);
    let setup = held.clone();
    drop(held);
    super::private_dm::with_started(|runtime| runtime.set_wake(setup.clone()));
    super::private_group::with_started(|runtime| runtime.set_wake(setup));
}

/// Why this iPhone's wake registration did not finish, for the field log;
/// never a token or a handle. A finished one logs "wake address set".
pub fn note_wake_registration(problem: String) {
    dlog::write(LogLevel::Warn, kinds::WAKE, "registration", &problem);
}

/// The wakes asked for since the last call; Dart sends each to its service.
pub fn take_wake_requests() -> Vec<WakeRequest> {
    let mut requests =
        super::private_dm::with_started(|runtime| runtime.take_wake_requests()).unwrap_or_default();
    requests.extend(
        super::private_group::with_started(|runtime| runtime.take_wake_requests())
            .unwrap_or_default(),
    );
    requests
}

/// What this iPhone's notification extension needs to show previews: each
/// chat with a preview key, under the name the user sees for it.
pub fn preview_chats() -> Vec<PreviewChat> {
    let mut chats =
        super::private_dm::with_started(|runtime| runtime.preview_chats()).unwrap_or_default();
    // Without the account runtime the contacts' own names stand.
    if let Ok(names) = super::conversation::names::personal_names() {
        for chat in &mut chats {
            let key = format!("dm:{}", chat.chat_id);
            if let Some(entry) = names
                .entries
                .iter()
                .find(|entry| entry.conversation_key == key)
            {
                chat.name = entry.name.clone();
            }
        }
    }
    chats.extend(
        super::private_group::with_started(|runtime| runtime.preview_chats()).unwrap_or_default(),
    );
    chats
}

/// The service refused a texts wake for `chat` to `handle` for good; its
/// texts go with the next one.
pub fn wake_refused(chat: String, handle: String) {
    super::private_dm::with_started(|runtime| runtime.wake_refused(&chat));
    super::private_group::with_started(|runtime| runtime.wake_refused(&chat, &handle));
}

/// The service no longer knows `handle`, so no chat wakes it again.
pub fn forget_wake_handle(handle: String) {
    super::private_dm::with_started(|runtime| runtime.forget_wake_handle(&handle));
    super::private_group::with_started(|runtime| runtime.forget_wake_handle(&handle));
}
