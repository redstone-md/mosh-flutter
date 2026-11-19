//! What the group runtime does for every group's waking, and what the API
//! asks of it (api/wake.rs).

use super::*;

impl PrivateGroupRuntime {
    /// This device's wake address, announced in every group, and the one
    /// service it wakes members through (api/wake.rs).
    pub(crate) fn set_wake(&mut self, setup: WakeSetup) {
        self.wake = setup;
    }

    /// Every group's wake work for one service turn; what changed a
    /// group's record is saved.
    pub(in crate::private_group_runtime) fn pump_wake(&mut self, now: u64) {
        let setup = self.wake.clone();
        let mut changed = Vec::new();
        for session in self.groups.values_mut() {
            session.pump_wake(now, &setup);
            if std::mem::take(&mut session.wake.dirty) {
                changed.push(session.group_id.clone());
            }
        }
        for group_id in changed {
            if let Err(error) = self.groups.persist_record(&group_id, false) {
                dlog::write(
                    LogLevel::Error,
                    kinds::PERSIST,
                    &group_id,
                    &error.to_string(),
                );
            }
        }
    }

    /// The wakes asked for since the last call, for Dart to send.
    pub fn take_wake_requests(&mut self) -> Vec<WakeRequest> {
        self.groups
            .values_mut()
            .flat_map(|session| std::mem::take(&mut session.wake.due))
            .collect()
    }

    /// The service refused a texts wake to `handle` in `chat` for good: the
    /// texts it carried first go with the next wake to that device.
    pub fn wake_refused(&mut self, chat: &str, handle: &str) {
        let Some(session) = self.groups.get_mut(chat) else {
            return;
        };
        let wake = &mut session.wake;
        let refused = wake
            .devices
            .announced
            .iter()
            .filter(|(_, held)| held.wake_address.handle == handle);
        for (signer, _) in refused {
            if let Some(texts) = wake.texts.get_mut(signer) {
                texts.give_back();
            }
        }
    }

    /// The service no longer knows `handle`: stop waking it.
    pub fn forget_wake_handle(&mut self, handle: &str) {
        for session in self.groups.values_mut() {
            if session.wake.devices.forget(handle) {
                session.wake.dirty = true;
                session.log_wake("wake service no longer knows a member handle");
            }
        }
    }

    /// The groups this device announced a preview key in, with the members
    /// whose signed previews it shows.
    pub fn preview_chats(&self) -> Vec<PreviewChat> {
        self.groups
            .values()
            .filter_map(GroupSession::preview_chat)
            .collect()
    }
}
