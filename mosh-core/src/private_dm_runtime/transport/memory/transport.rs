use super::*;

impl DmTransport for MemoryTransport {
    fn authenticate_invite(
        &self,
        invite: &str,
        crypto: &crate::mls_crypto::MlsSessionCrypto,
    ) -> Result<String, String> {
        match self.identity.as_ref() {
            Some(identity) => {
                super::super::super::invite_ownership::sign_invite(invite, identity, crypto)
            }
            None => Ok(invite.to_string()),
        }
    }

    fn authenticate_key_package(
        &self,
        payload: &[u8],
        mesh: &str,
        crypto: &crate::mls_crypto::MlsSessionCrypto,
    ) -> Result<Option<String>, String> {
        self.identity
            .as_ref()
            .map(|identity| sign_key_package(identity, crypto, mesh, payload))
            .transpose()
    }

    fn open_room(
        &self,
        _room: &str,
        _channels: &[String],
        _listen_port: u16,
        _static_peer: Option<String>,
    ) -> Result<(), String> {
        Ok(())
    }

    fn close_room(&self, _room: &str, _channels: &[String], _label: &str) {}

    fn subscribe(&self, _room: &str, _channel: &str) -> Result<(), String> {
        let refused = self
            .net
            .lock()
            .endpoints
            .get(&self.peer_id)
            .is_some_and(|endpoint| endpoint.refuse_subscribes);
        if refused {
            Err("subscribe refused".to_string())
        } else {
            Ok(())
        }
    }

    fn unsubscribe(&self, _room: &str, _channel: &str) -> Result<(), String> {
        Ok(())
    }

    fn publish(&self, _room: &str, channel: &str, payload: &[u8]) -> Result<(), PublishError> {
        let mut state = self.net.lock();
        let refused = state
            .endpoints
            .get(&self.peer_id)
            .is_some_and(|endpoint| endpoint.refuse_publishes);
        let targets: Vec<(String, Option<DropRule>)> = state
            .links
            .iter()
            .filter(|((from, _), link)| *from == self.peer_id && link.reach != PeerTransport::None)
            .map(|((_, to), link)| (to.clone(), link.drop_if.clone()))
            .collect();
        if refused || targets.is_empty() {
            return Err(PublishError::NoPeers("no peers reachable".to_string()));
        }
        let fail = state
            .endpoints
            .get(&self.peer_id)
            .is_some_and(|endpoint| endpoint.fail_publishes);
        if fail {
            return Err(PublishError::Other("publish failed".to_string()));
        }
        for (to, drop_if) in targets {
            if drop_if.is_some_and(|rule| rule(channel, payload)) {
                continue;
            }
            if let Some(endpoint) = state.endpoints.get_mut(&to) {
                let queue = if is_call_media_inbound(channel) {
                    &mut endpoint.media_inbox
                } else {
                    &mut endpoint.inbox
                };
                queue.push(MossReceivedMessage {
                    channel: channel.to_string(),
                    payload: payload.to_vec(),
                });
            }
        }
        Ok(())
    }

    fn connect_peer(&self, peer_moss_id: &str) -> Result<(), String> {
        let mut state = self.net.lock();
        if let Some(endpoint) = state.endpoints.get_mut(&self.peer_id) {
            endpoint.connect_requests.push(peer_moss_id.to_string());
        }
        Ok(())
    }

    fn reach(&self, peer_moss_id: &str) -> PeerTransport {
        let state = self.net.lock();
        if state.reports_fail(&self.peer_id) {
            return PeerTransport::None;
        }
        state
            .links
            .get(&(self.peer_id.clone(), peer_moss_id.to_string()))
            .map_or(PeerTransport::None, Link::visible_reach)
    }

    fn local_peer_id(&self) -> Option<String> {
        Some(self.peer_id.clone())
    }

    fn mesh_info(&self) -> Option<MeshInfo> {
        let state = self.net.lock();
        if state.reports_fail(&self.peer_id) {
            return None;
        }
        let peer_details = self.reachable_peers(&state);
        Some(MeshInfo {
            mesh_id: "memory".to_string(),
            peer_count: peer_details.len() as i32,
            peer_details,
            ..Default::default()
        })
    }

    /// A stream frame lands on the far end under the reserved stream
    /// channel, framed, exactly the way the moss stream callback files it.
    fn send_to_peer_stream(&self, peer_id: &str, payload: &[u8]) -> Result<(), String> {
        let mut state = self.net.lock();
        let reachable = state
            .links
            .get(&(self.peer_id.clone(), peer_id.to_string()))
            .is_some_and(|link| link.visible_reach() != PeerTransport::None);
        let Some(endpoint) = state.endpoints.get_mut(&self.peer_id) else {
            return Err("no such endpoint".to_string());
        };
        endpoint.stream_attempts += 1;
        if endpoint.fail_streams || !reachable {
            return Err("stream refused".to_string());
        }
        if let Some(target) = state.endpoints.get_mut(peer_id) {
            target.inbox.push(MossReceivedMessage {
                channel: stream_inbox_channel(&self.peer_id),
                payload: payload.to_vec(),
            });
        }
        Ok(())
    }

    fn drain(&self) -> Vec<MossReceivedMessage> {
        let mut state = self.net.lock();
        state
            .endpoints
            .get_mut(&self.peer_id)
            .map(|endpoint| std::mem::take(&mut endpoint.inbox))
            .unwrap_or_default()
            .into_iter()
            .map(passthrough_or_deframe)
            .collect()
    }

    fn drain_media(&self) -> Vec<MossReceivedMessage> {
        let mut state = self.net.lock();
        state
            .endpoints
            .get_mut(&self.peer_id)
            .map(|endpoint| std::mem::take(&mut endpoint.media_inbox))
            .unwrap_or_default()
    }
}
