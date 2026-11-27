//! Channel lifecycle: rehydrate, join, view, leave, and the DM-offer hooks.

use super::*;

impl ChannelRuntime {
    /// The user has the channel on screen. No inbound drain first: only what
    /// the last poll showed counts as seen.
    pub fn mark_viewed(&mut self, name: &str) -> Result<(), ChannelRuntimeError> {
        let normalized = normalize_name(name)?;
        self.channel_ref(&normalized)?;
        self.channels.mark_read(&normalized);
        Ok(())
    }

    /// Restore joined public channels and local scrollback from encrypted disk.
    pub fn rehydrate(&mut self) {
        for rec in self.channels.stored_records::<PersistedChannelSession>() {
            let node = match self.open_channel_room(
                &rec.mesh_id,
                &rec.topic,
                &rec.blob_topic,
                rec.listen_port,
                rec.static_peer.clone(),
            ) {
                Ok(node) => node,
                Err(error) => {
                    dlog::write(
                        LogLevel::Error,
                        kinds::REHYDRATE,
                        &rec.name,
                        &format!("channel rehydrate: node start failed: {error}"),
                    );
                    continue;
                }
            };
            let mut session = ChannelSession {
                recovery: Default::default(),
                plus_schedule: Default::default(),
                deletions: crate::message_deletion::DeletionBook::new(
                    format!("channel:{}", rec.name),
                    CHANNEL_HISTORY,
                    self.channels.persistence().cloned(),
                ),
                name: rec.name.clone(),
                topic: rec.topic.clone(),
                blob_topic: rec.blob_topic.clone(),
                mesh_id: rec.mesh_id.clone(),
                display_name: rec.display_name.clone(),
                device_fingerprint: node
                    .public_key_hex()
                    .unwrap_or_else(|| rec.device_fingerprint.clone()),
                listen_port: rec.listen_port,
                static_peer: rec.static_peer.clone(),
                node,
                messages: MessageLog::default(),
                seen: SeenFrames::default(),
                transfer: Transfer::new(Arc::clone(self.channels.attachment_store())),
                outbound_attempts: HashMap::new(),
                dm_offers: DmOffers::default(),
            };
            self.channels.replay(
                &rec.name,
                Restore {
                    log: &mut session.messages,
                    attempts: &mut session.outbound_attempts,
                    transfer: &mut session.transfer,
                    local_author: &rec.device_fingerprint,
                },
            );
            self.channels.insert(rec.name, session);
        }
    }

    pub fn join(
        &mut self,
        request: JoinChannelRequest,
    ) -> Result<ChannelSnapshot, ChannelRuntimeError> {
        let normalized = normalize_name(&request.name)?;
        if self.channels.holds(&normalized) {
            return Err(ChannelRuntimeError::DuplicateChannel(normalized));
        }
        let listen_port = request.listen_port;
        let static_peer = request.static_peer.clone();

        let mesh_id = format!("{MESH_PREFIX}{normalized}");
        let topic = format!("{TOPIC_PREFIX}{normalized}");
        let blob_topic = format!("{BLOB_PREFIX}{normalized}");
        let node = self.open_channel_room(
            &mesh_id,
            &topic,
            &blob_topic,
            listen_port,
            static_peer.clone(),
        )?;
        // The room is open on the shared node, so bailing without closing it
        // would pin the node up with subscriptions nothing ever clears.
        let device_fingerprint = match node.public_key_hex() {
            Some(value) => value,
            None => {
                runtime::close_room(
                    &self.shared_node,
                    &node,
                    &mesh_id,
                    &[topic, blob_topic],
                    &format!("{KIND} {normalized}"),
                );
                return Err(ChannelRuntimeError::Moss(
                    "public key unavailable".to_string(),
                ));
            }
        };

        let session = ChannelSession {
            recovery: Default::default(),
            plus_schedule: Default::default(),
            deletions: crate::message_deletion::DeletionBook::new(
                format!("channel:{normalized}"),
                CHANNEL_HISTORY,
                self.channels.persistence().cloned(),
            ),
            name: normalized.clone(),
            topic,
            blob_topic,
            mesh_id,
            display_name: request.display_name,
            device_fingerprint,
            listen_port,
            static_peer,
            node,
            messages: MessageLog::default(),
            seen: SeenFrames::default(),
            transfer: Transfer::new(Arc::clone(self.channels.attachment_store())),
            outbound_attempts: HashMap::new(),
            dm_offers: DmOffers::default(),
        };

        self.channels.insert(normalized.clone(), session);
        self.commit_join(&normalized)
    }

    /// Saves the joined channel's own record before the join answers, so an
    /// unrelated refused write cannot refuse it. A refused save closes the
    /// channel again and leaves no write that could restore it later.
    fn commit_join(&mut self, normalized: &str) -> Result<ChannelSnapshot, ChannelRuntimeError> {
        if let Err(error) = self.channels.persist_record(normalized, true) {
            self.close(normalized);
            return Err(error.into());
        }
        // The first poll starts the channel's history sync. The join already
        // stands, so a refused drain is reported by the next poll instead.
        self.poll(normalized).or_else(|error| {
            dlog::write(
                LogLevel::Warn,
                kinds::PERSIST,
                normalized,
                &error.to_string(),
            );
            self.snapshot(normalized)
        })
    }

    /// Takes a channel out of the runtime and off the shared node, forgetting
    /// its pending writes; what is on disk stays.
    fn close(&mut self, normalized: &str) -> Option<ChannelSession> {
        let session = self.channels.remove(normalized)?;
        runtime::close_room(
            &self.shared_node,
            &session.node,
            &session.mesh_id,
            &[session.topic.clone(), session.blob_topic.clone()],
            &format!("{KIND} {normalized}"),
        );
        self.channels.forget(normalized);
        Some(session)
    }

    /// Publishes a private-DM invitation aimed at one channel member.
    pub fn send_dm_offer(
        &mut self,
        name: &str,
        target_fingerprint: String,
        invite_uri: String,
    ) -> Result<(), ChannelRuntimeError> {
        let normalized = normalize_name(name)?;
        let session = self.channel_mut(&normalized)?;
        session.publish_dm_offer(target_fingerprint, invite_uri)
    }

    pub fn dismiss_dm_offer(
        &mut self,
        name: &str,
        offer_id: &str,
    ) -> Result<(), ChannelRuntimeError> {
        let normalized = normalize_name(name)?;
        let session = self.channel_mut(&normalized)?;
        session.dm_offers.dismiss(offer_id);
        Ok(())
    }

    pub fn leave(&mut self, name: &str) -> Result<ChannelLeaveResult, ChannelRuntimeError> {
        let normalized = normalize_name(name)?;
        match self.close(&normalized) {
            Some(_) => {
                if let Some(p) = self.channels.persistence() {
                    if let Err(error) = p.delete_channel(&normalized) {
                        dlog::write(
                            LogLevel::Warn,
                            kinds::PERSIST,
                            &normalized,
                            &format!("failed to delete persisted channel: {error}"),
                        );
                    }
                }
                Ok(ChannelLeaveResult {
                    name: normalized,
                    closed: true,
                })
            }
            None => Err(ChannelRuntimeError::MissingChannel(normalized)),
        }
    }
}
