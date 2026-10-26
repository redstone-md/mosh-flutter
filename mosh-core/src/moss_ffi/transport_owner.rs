//! Stable application transport identity around a replaceable native C handle.
//!
//! Read leases cover every FFI operation. Suspension holds the write lease, so
//! Stop cannot race publication/media, and existing session Arcs remain valid.
use super::*;
use std::collections::{BTreeMap, BTreeSet};
use std::ops::Deref;
use std::sync::RwLockReadGuard;

#[derive(Default)]
pub(super) struct Registrations {
    pub rooms: BTreeSet<String>,
    pub subscriptions: BTreeSet<(String, String)>,
    pub global_subscriptions: BTreeSet<String>,
    pub discovery: BTreeMap<String, Vec<String>>,
    pub addresses: BTreeSet<String>,
    pub peers: BTreeSet<String>,
    pub streams: BTreeSet<u32>,
    pub messages: bool,
    pub events: bool,
    pub packets: bool,
}

pub(super) struct NativeNode {
    pub handle: Option<MossHandle>,
    pub registrations: Registrations,
}

impl NativeNode {
    pub fn new(handle: MossHandle) -> Self {
        Self {
            handle: Some(handle),
            registrations: Registrations::default(),
        }
    }
}

pub(super) struct HandleLease<'a>(RwLockReadGuard<'a, NativeNode>);

impl Deref for HandleLease<'_> {
    type Target = MossHandle;
    fn deref(&self) -> &Self::Target {
        self.0
            .handle
            .as_ref()
            .expect("validated native handle lease")
    }
}

impl MossNode {
    pub(super) fn handle(&self) -> Result<HandleLease<'_>, MossFfiError> {
        let state = self
            .native
            .read()
            .unwrap_or_else(|error| error.into_inner());
        state.handle.ok_or(MossFfiError::TransportOffline)?;
        Ok(HandleLease(state))
    }

    pub(super) fn register(
        &self,
        operation: impl FnOnce(MossHandle) -> Result<(), MossFfiError>,
        update: impl FnOnce(&mut Registrations),
    ) -> Result<(), MossFfiError> {
        let mut state = self
            .native
            .write()
            .unwrap_or_else(|error| error.into_inner());
        // A suspended installation can restore/register local room intent;
        // publications still require a live read lease and cannot restart I/O.
        if let Some(handle) = state.handle {
            operation(handle)?;
        }
        update(&mut state.registrations);
        Ok(())
    }

    pub(crate) fn transport_running(&self) -> bool {
        self.native
            .read()
            .unwrap_or_else(|e| e.into_inner())
            .handle
            .is_some()
    }

    /// Only the installation execution owner may call this after admitted work
    /// has drained. It changes transport ownership, never conversation membership.
    pub(crate) fn suspend_transport(&self) -> Result<(), MossFfiError> {
        let mut state = self
            .native
            .write()
            .unwrap_or_else(|error| error.into_inner());
        if let Some(handle) = state.handle {
            // SAFETY: the exclusive lease has drained all calls using this handle.
            check_code("stop", unsafe { (self.runtime.stop)(handle) })?;
            state.handle = None;
        }
        Ok(())
    }

    pub(crate) fn resume_transport(&self) -> Result<(), MossFfiError> {
        let mut state = self
            .native
            .write()
            .unwrap_or_else(|error| error.into_inner());
        if state.handle.is_some() {
            return Ok(());
        }
        let replacement = self.runtime.init_node(&self.mesh_id, &self.config_json)?;
        if self.identity_signer()?.verifying_key() != replacement.identity_signer()?.verifying_key()
        {
            return Err(MossFfiError::IdentityUnavailable);
        }
        replacement.restore(&state.registrations)?;
        let handle = replacement
            .native
            .write()
            .unwrap_or_else(|e| e.into_inner())
            .handle
            .take();
        state.handle = handle;
        Ok(())
    }

    fn restore(&self, registrations: &Registrations) -> Result<(), MossFfiError> {
        if registrations.messages {
            self.set_message_callback()?;
        }
        if registrations.events {
            self.set_event_callback()?;
        }
        if registrations.packets {
            self.set_packet_callback()?;
        }
        for id in &registrations.streams {
            self.register_stream_handler(*id)?;
        }
        self.start()?;
        for room in &registrations.rooms {
            self.join_room(room)?;
        }
        for (room, channel) in &registrations.subscriptions {
            self.subscribe_room(room, channel)?;
        }
        for channel in &registrations.global_subscriptions {
            self.subscribe(channel)?;
        }
        for (room, peers) in &registrations.discovery {
            self.set_room_known_peers(room, peers)?;
        }
        for address in &registrations.addresses {
            self.connect(address)?;
        }
        for peer in &registrations.peers {
            self.connect_to_peer(peer)?;
        }
        Ok(())
    }
}
