//! Verified roster state, authenticated offers and snapshot views.

use super::*;

impl OrgSession {
    pub(super) fn to_record(&self) -> PersistedOrgRecord {
        PersistedOrgRecord {
            org_pubkey: self.org_pubkey.clone(),
            org_name: self.org_name.clone(),
            mesh_id: self.mesh_id.clone(),
            display_name: self.display_name.clone(),
            listen_port: self.listen_port,
            static_peer: self.static_peer.clone(),
            dm_links: self.dm_links.clone(),
            resolved_offer_ids: self.resolved_offer_ids.clone(),
            pending_acceptances: self.pending_acceptances.clone(),
        }
    }

    pub(super) fn in_roster(&self) -> bool {
        self.sender_in_roster(&self.own_peer_id)
    }

    pub(super) fn snapshot(&self) -> OrgSnapshot {
        OrgSnapshot {
            org_pubkey: self.org_pubkey.clone(),
            org_name: self.org_name.clone(),
            mesh_id: self.mesh_id.clone(),
            own_peer_id: self.own_peer_id.clone(),
            confirmation_code: org_signing::confirmation_code(&self.own_peer_id),
            in_roster: self.in_roster(),
            roster_version: self.roster.as_ref().map(|r| r.version),
            members: self
                .roster
                .iter()
                .flat_map(|roster| &roster.members)
                .map(|member| OrgMemberView {
                    moss_peer_id: member.moss_peer_id.clone(),
                    name: member.name.clone(),
                    role: member.role.clone(),
                    is_self: member.moss_peer_id == self.own_peer_id,
                })
                .collect(),
            dm_offers: self.dm_offers.clone(),
            group_offers: self.group_offers.clone(),
            dm_links: self.dm_links.clone(),
        }
    }

    pub(super) fn ctx(&self) -> OrgContext<'_> {
        OrgContext {
            org_pubkey: &self.org_pubkey,
            mesh_id: &self.mesh_id,
            channel_kind: ORG_CHANNEL_KIND,
        }
    }

    /// Announce ourselves to whoever holds the roster. Failures are
    /// non-fatal: the hello re-fires on every poll until we appear in the
    /// roster, which doubles as the retry loop.
    pub(super) fn publish_hello(&self) {
        let message = OrgMessage::Hello {
            moss_peer_id: self.own_peer_id.clone(),
            display_name: self.display_name.clone(),
        };
        if let Err(error) = publish_signed(self, &message) {
            dlog::write(
                LogLevel::Warn,
                kinds::PUBLISH,
                &self.org_pubkey,
                &format!("org hello publish failed: {error}"),
            );
        }
    }

    /// Broadcast our verified roster bytes verbatim (self-authenticating,
    /// travels bare — ADR 0007). Serves newcomers and lagging peers.
    pub(super) fn publish_roster(&mut self) {
        #[cfg(test)]
        {
            self.roster_publishes += 1;
        }
        let Some(bytes) = self.roster_bytes.as_ref() else {
            return;
        };
        let wire = OrgWire::Roster {
            roster_b64: encode(bytes),
        };
        let Ok(payload) = serde_json::to_vec(&wire) else {
            return;
        };
        // Room-scoped: the shared node's own room is the substrate, so a
        // room-less publish would land where no org member listens.
        if let Err(error) =
            self.node
                .publish_room_best_effort(&self.mesh_id, &self.control_channel, &payload)
        {
            dlog::write(
                LogLevel::Warn,
                kinds::PUBLISH,
                &self.org_pubkey,
                &format!("org roster publish failed: {error}"),
            );
        }
    }

    /// One inbound frame from `org-control/<mesh_id>`. Never fails the
    /// caller: bad frames are logged and dropped (spec Error handling).
    pub(super) fn ingest_payload(&mut self, persistence: Option<&Persistence>, payload: &[u8]) {
        let wire: OrgWire = match serde_json::from_slice(payload) {
            Ok(wire) => wire,
            Err(_) => return,
        };
        match wire {
            OrgWire::Roster { roster_b64 } => {
                let Ok(bytes) = decode(&roster_b64) else {
                    return;
                };
                self.absorb_roster_bytes(persistence, &bytes);
            }
            OrgWire::Signed {
                payload_b64,
                peer_id,
                sig_b64,
            } => {
                let (Ok(inner), Ok(sig)) = (decode(&payload_b64), decode(&sig_b64)) else {
                    return;
                };
                let env = OrgSigned {
                    payload: inner,
                    peer_id,
                    sig,
                };
                if org_envelope::verify(&env, &self.ctx()).is_err() {
                    dlog::write(
                        LogLevel::Warn,
                        kinds::VERIFY,
                        &self.control_channel,
                        "org envelope verify failed",
                    );
                    return;
                }
                let message: OrgMessage = match serde_json::from_slice(&env.payload) {
                    Ok(message) => message,
                    Err(_) => return,
                };
                self.handle_message(&env.peer_id, message);
            }
        }
    }

    /// Sender-auth rule: `Hello` is exempt from the roster gate (it is by
    /// definition sent by not-yet-members; the envelope still proves key
    /// possession, and the membership decision is the admin CLI's). Every
    /// other message requires the verified sender to be a roster member.
    pub(super) fn handle_message(&mut self, sender_peer_id: &str, message: OrgMessage) {
        match message {
            OrgMessage::Hello { .. } => {
                if sender_peer_id != self.own_peer_id {
                    // Serve the roster to whoever just arrived.
                    self.publish_roster();
                }
            }
            OrgMessage::DmOffer {
                offer_id,
                target_peer_id,
                from_name,
                invite_uri,
            } => {
                if !self.accept_offer(sender_peer_id, &target_peer_id, &offer_id, "dm") {
                    return;
                }
                self.dm_offers.push(OrgDmOfferView {
                    offer_id,
                    from_peer_id: sender_peer_id.to_string(),
                    from_name,
                    invite_uri,
                });
            }
            OrgMessage::GroupOffer {
                offer_id,
                target_peer_id,
                from_name,
                group_label,
                group_invite_uri,
            } => {
                if !self.accept_offer(sender_peer_id, &target_peer_id, &offer_id, "group") {
                    return;
                }
                self.group_offers.push(OrgGroupOfferView {
                    offer_id,
                    from_peer_id: sender_peer_id.to_string(),
                    from_name,
                    group_label,
                    group_invite_uri,
                });
            }
        }
    }

    /// Deduplicate live offers; durable resolutions also survive a restart.
    fn accept_offer(&mut self, sender: &str, target: &str, id: &str, kind: &str) -> bool {
        if target != self.own_peer_id {
            return false;
        }
        if !self.sender_in_roster(sender) {
            dlog::write(
                LogLevel::Warn,
                kinds::OFFER,
                &self.org_pubkey,
                &format!("org {kind} offer from non-member {sender} dropped"),
            );
            return false;
        }
        !self.resolved_offer_ids.contains(id) && self.seen_offer_ids.insert(id.to_string())
    }

    pub(super) fn sender_in_roster(&self, sender_peer_id: &str) -> bool {
        self.roster
            .as_ref()
            .is_some_and(|r| r.members.iter().any(|m| m.moss_peer_id == sender_peer_id))
    }

    pub(super) fn absorb_roster_bytes(&mut self, persistence: Option<&Persistence>, bytes: &[u8]) {
        let stored_version = self.roster.as_ref().map(|r| r.version);
        match org_roster::verify(bytes, &self.org_pubkey, stored_version) {
            Ok(roster) => {
                // Revocation is NOT event-driven off this diff: the group
                // runtime reconciles its trees against the persisted roster
                // (survives restarts and absorbs from any drain path).
                if let Some(p) = persistence {
                    if let Err(error) = p.put_org_roster(&self.org_pubkey, bytes) {
                        dlog::write(
                            LogLevel::Warn,
                            kinds::PERSIST,
                            &self.org_pubkey,
                            &format!("org roster persist failed: {error}"),
                        );
                    }
                }
                self.roster = Some(roster);
                self.roster_bytes = Some(bytes.to_vec());
            }
            Err(RosterError::Rollback { stored, received }) if received < stored => {
                // The sender is behind — serve them our newer roster.
                // `received == stored` is a plain duplicate broadcast and is
                // dropped silently to avoid re-broadcast ping-pong.
                self.publish_roster();
            }
            Err(RosterError::Rollback { .. }) => {}
            Err(error) => {
                dlog::write(
                    LogLevel::Warn,
                    kinds::VERIFY,
                    &self.org_pubkey,
                    &format!("org roster rejected: {error}"),
                );
            }
        }
    }
}
