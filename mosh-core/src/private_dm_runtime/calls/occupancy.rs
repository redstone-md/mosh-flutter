use std::collections::{BTreeSet, HashMap};

const LEASE_MS: u64 = 15_000;

#[derive(Default)]
pub(in crate::private_dm_runtime) struct CallOccupancy {
    devices: HashMap<String, Reservation>,
}

struct Reservation {
    call_id: String,
    caller: String,
    receiver: Option<String>,
    expires: u64,
}

impl CallOccupancy {
    pub(super) fn reserve_selected(&mut self, device: &str, call_id: &str, caller: &str, now: u64) {
        self.expire(now);
        if self.devices.get(device).is_some_and(|reservation| {
            reservation.call_id != call_id || reservation.caller != caller
        }) {
            return;
        }
        self.reserve(device, call_id, caller, Some(device.into()), now);
    }
    pub(super) fn permits_end(&self, sender: &str, call_id: &str) -> Option<bool> {
        let reservations: Vec<_> = self
            .devices
            .values()
            .filter(|r| r.call_id == call_id)
            .collect();
        (!reservations.is_empty()).then(|| {
            reservations
                .iter()
                .any(|r| r.caller == sender || r.receiver.as_deref() == Some(sender))
        })
    }
    pub(super) fn selected(&self, call_id: &str) -> bool {
        self.devices.values().any(|reservation| {
            reservation.call_id == call_id
                && reservation.receiver.is_some()
                && reservation.expires > super::now_ms()
        })
    }
    pub(super) fn reserve(
        &mut self,
        device: &str,
        call_id: &str,
        caller: &str,
        receiver: Option<String>,
        now: u64,
    ) {
        self.expire(now);
        if self.devices.len() >= 64 && !self.devices.contains_key(device) {
            return;
        }
        self.devices.insert(
            device.into(),
            Reservation {
                call_id: call_id.into(),
                caller: caller.into(),
                receiver,
                expires: now.saturating_add(LEASE_MS),
            },
        );
    }

    pub(super) fn release(&mut self, device: &str, call_id: &str) {
        if self
            .devices
            .get(device)
            .is_some_and(|reservation| reservation.call_id == call_id)
        {
            self.devices.remove(device);
        }
    }

    pub(super) fn finish(&mut self, call_id: &str) {
        self.devices
            .retain(|_, reservation| reservation.call_id != call_id);
    }

    pub(super) fn receive_end(&mut self, sender: &str, call_id: &str) {
        self.devices.retain(|_, reservation| {
            reservation.call_id != call_id
                || (reservation.caller != sender && reservation.receiver.as_deref() != Some(sender))
        });
    }

    pub(in crate::private_dm_runtime) fn expire(&mut self, now: u64) {
        self.devices
            .retain(|_, reservation| reservation.expires > now);
    }

    pub(in crate::private_dm_runtime) fn calls(&self, now: u64) -> BTreeSet<String> {
        self.devices
            .values()
            .filter(|reservation| reservation.expires > now)
            .map(|reservation| reservation.call_id.clone())
            .collect()
    }
}

use super::{protocol::CallControl, *};

impl PrivateDmSession {
    pub(super) fn observe_call_selection(&mut self, control: &CallControl, receiver: &str) {
        if self
            .membership
            .as_ref()
            .is_some_and(|membership| membership.call_own(receiver))
        {
            self.call_occupancy.reserve_selected(
                receiver,
                &control.call_id,
                &control.signer,
                now_ms(),
            );
        }
    }
    pub(super) fn authoritative_call_end(&self, control: &CallControl) -> bool {
        let CallAction::End { caller, .. } = &control.action else {
            return false;
        };
        if let Some(call) = self
            .call
            .as_ref()
            .filter(|call| call.matches_id(&control.call_id))
        {
            return control.signer == call.caller_signer
                || call.selected_signer.as_ref() == Some(&control.signer);
        }
        self.call_occupancy
            .permits_end(&control.signer, &control.call_id)
            .unwrap_or(caller == &control.signer)
    }

    pub(super) fn observe_own_call(&mut self, control: &CallControl) {
        if self.authoritative_call_end(control) {
            self.call_controls.close(&control.call_id, true);
            self.call_occupancy.finish(&control.call_id);
        }
        match &control.action {
            CallAction::End { .. } | CallAction::Decline { .. } => self
                .call_occupancy
                .release(&control.signer, &control.call_id),
            CallAction::Occupied { caller, receiver } => self.call_occupancy.reserve(
                &control.signer,
                &control.call_id,
                caller,
                receiver.clone(),
                now_ms(),
            ),
            CallAction::Selected { receiver } => self.call_occupancy.reserve(
                &control.signer,
                &control.call_id,
                &control.signer,
                Some(receiver.clone()),
                now_ms(),
            ),
            _ => self.call_occupancy.reserve(
                &control.signer,
                &control.call_id,
                self.call
                    .as_ref()
                    .filter(|call| call.call_id == control.call_id)
                    .map_or(&control.signer, |call| &call.caller_signer),
                None,
                now_ms(),
            ),
        }
    }
}
