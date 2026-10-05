//! Inbound routing, protocol ticks and live-call synchronization.

use super::*;

impl PrivateDmRuntime {
    /// One protocol step with no caller behind it: take in what arrived and
    /// tick every session. The bridge runs it on its own thread, so
    /// handshakes, keepalives, the outbox and re-sends keep going while the
    /// UI is not polling (a hidden window, a throttled timer).
    pub fn service(&mut self) {
        self.drain_inbound();
    }

    /// Take in every frame that arrived, then give each session its tick.
    /// Called on every runtime entry point and by [`Self::service`].
    pub(super) fn drain_inbound(&mut self) {
        self.drain_inbound_at(now_ms());
    }

    /// [`Self::drain_inbound`] on a given clock: the frames drained here are
    /// stamped with `now` when the tick records the counterpart's proof.
    pub(super) fn drain_inbound_at(&mut self, now: u64) {
        self.receive_inbound();
        self.tick(now);
    }

    /// Receive membership/control updates without publishing queued messages.
    /// Deletion must persist cancellation before the next outbox tick.
    pub(super) fn receive_inbound(&mut self) {
        self.prepare_devices();
        for message in self.transport.drain() {
            self.route_frame(message);
        }
    }

    /// Hand one frame to the session it names. Voice-call media never comes
    /// here: it has its own queue (`CallMedia`).
    ///
    /// A single bad inbound frame must never abort the drain — otherwise it
    /// would also fail the caller (e.g. send_message drains first). After a
    /// restart the in-memory replay-dedup set is empty, so the mesh
    /// re-delivers already-consumed MLS messages; decrypting those fails with
    /// "secret deleted to preserve forward secrecy". That is expected, so the
    /// frame is dropped and the drain keeps going.
    pub(super) fn route_frame(&mut self, message: MossReceivedMessage) {
        if message.channel == devices::DEVICE_CHANNEL {
            if let Err(error) = self.receive_device_packet(&message.payload) {
                dlog::write(LogLevel::Warn, kinds::VERIFY, KIND, &error.to_string());
            }
            return;
        }
        if let Some(session_id) = channel_session_id(&message.channel).map(str::to_string) {
            let Some(session) = self.sessions.get_mut(&session_id) else {
                return;
            };
            if session.ensure_device_authorized().is_err() {
                return;
            }
            if let Err(error) = session.handle_moss_message(message) {
                dlog::write(
                    LogLevel::Warn,
                    kinds::FRAME,
                    &session_id,
                    &format!("dropping inbound frame: {error}"),
                );
            }
        }
    }

    /// One heartbeat for every session: reachability, the handshake and hello
    /// repeats, the outbox, the re-sends. Whatever changed an attempt is
    /// written down afterwards, once the mutable borrow is over.
    pub(super) fn tick(&mut self, now: u64) {
        let lost_window = self.lost_window_ms;
        let mut dirty: Vec<(String, String)> = Vec::new();
        let mut ready = Vec::new();
        for (session_id, session) in self.sessions.iter_mut() {
            if !session.service_protocols(now, lost_window) {
                continue;
            }
            ready.push(session_id.clone());
            let changed = session
                .pump_unacked_resends(now)
                .into_iter()
                .chain(session.take_dirty_outbound());
            dirty.extend(changed.map(|message_id| (session_id.clone(), message_id)));
        }
        for (session_id, message_id) in dirty {
            if let Err(error) = self.sessions.persist_send(&session_id, &message_id, false) {
                self.log_persistence_failure(&session_id, &error);
            }
        }
        for session_id in ready {
            if let Err(error) = self.deliver_queued(&session_id) {
                dlog::write(
                    LogLevel::Error,
                    kinds::PERSIST,
                    &session_id,
                    &error.to_string(),
                );
            }
        }
        self.pump_devices(now);
        if let Err(error) = self.sessions.persist_tail() {
            self.log_persistence_failure(KIND, &error);
        }
        self.sync_call_media();
    }

    pub(super) fn log_persistence_failure(
        &self,
        id: &str,
        error: &crate::persistence::PersistenceError,
    ) {
        dlog::write(LogLevel::Error, kinds::PERSIST, id, &error.to_string());
    }

    /// The call media hub the audio loop sends and drains through.
    pub fn call_media(&self) -> Arc<CallMedia> {
        Arc::clone(&self.media)
    }

    /// Tell the media hub which calls are live. Run after every tick and
    /// every call action: the call state machine lives here, the hub only
    /// mirrors its active calls.
    pub(super) fn sync_call_media(&self) {
        let live = self
            .sessions
            .values()
            .filter_map(|session| {
                let call = session.call.as_ref()?;
                (call.phase == CallPhase::Active).then(|| LiveCall {
                    call_id: call.call_id.clone(),
                    room: session.mesh_id.clone(),
                    own_direction_bit: call.direction.seq_direction_bit(),
                })
            })
            .collect();
        self.media.sync(live);
        self.media.collect();
    }
}

impl PrivateDmSession {
    /// Refresh admission and run session protocols before the runtime outbox.
    fn service_protocols(&mut self, now: u64, lost_window: u64) -> bool {
        if self.ensure_device_authorized().is_err() {
            return false;
        }
        if let Err(error) = self.apply_deletions() {
            dlog::write(
                LogLevel::Warn,
                kinds::PERSIST,
                &self.session_id,
                &error.to_string(),
            );
            return false;
        }
        self.pump_attachment_requests();
        let _ = self.sync_deletions(now);
        self.pump_peer_connect();
        self.pump_liveness(now, lost_window);
        self.pump_reach_log();
        self.pump_handshake(now);
        self.pump_hello(now);
        self.pump_peer_announce(now);
        self.pump_call_signaling(now);
        true
    }
}
