use super::{Certificate, Issuer, PlusFrame, PlusPeerBadge, PlusRuntime};
use serde::{Deserialize, Serialize};

#[derive(Clone, Serialize, Deserialize)]
pub(super) struct PeerEvidence {
    revision: u64,
    certificate: Option<Certificate>,
    aliases: Vec<String>,
}

impl PeerEvidence {
    pub(super) fn trusted_by(&self, issuer: &Issuer, account: &str) -> bool {
        self.certificate
            .as_ref()
            .is_none_or(|certificate| issuer.verify(certificate, account, 0).is_ok())
    }
}

impl PlusRuntime {
    pub fn frame(
        &self,
        context: &str,
        local_peer: &str,
        author: &str,
        sign: impl FnOnce(&[u8]) -> Result<Vec<u8>, String>,
        now_ms: u64,
    ) -> Result<Option<PlusFrame>, String> {
        if self.issuer.mainnet_key_id.is_some() {
            return self.mainnet_frame(context, local_peer, author, sign, now_ms);
        }
        if !self.state.ever_visible {
            return Ok(None);
        }
        // Peers expire the same certificate locally. Sending a different value
        // under the original revision would conflict with its signed opt-in.
        if self.state.visible
            && self
                .state
                .certificate
                .as_ref()
                .is_some_and(|c| c.expires_at_ms <= now_ms)
        {
            return Ok(None);
        }
        let Some(ownership) =
            crate::message_deletion::ownership::create(Some(&self.store), Some(local_peer), author)
                .map_err(|_| "PLUS account proof unavailable")?
        else {
            return Ok(None);
        };
        if crate::message_deletion::ownership::verify(&ownership, author)? != self.state.account_id
        {
            return Err("PLUS account changed".into());
        }
        let certificate = self
            .state
            .certificate
            .as_ref()
            .filter(|c| self.state.visible && c.expires_at_ms > now_ms)
            .cloned();
        let mut frame = PlusFrame {
            context: context.into(),
            author: author.into(),
            ownership,
            revision: self.state.revision,
            certificate,
            signature: String::new(),
            production: None,
        };
        frame.signature = hex::encode(sign(&frame.input()?)?);
        Ok(Some(frame))
    }

    /// Aliases must come from the caller's authenticated conversation carrier.
    pub fn accept_peer(
        &mut self,
        frame: &PlusFrame,
        context: &str,
        author: &str,
        aliases: &[String],
        now_ms: u64,
    ) -> Result<(), String> {
        if self.issuer.mainnet_key_id.is_some() {
            return self.accept_mainnet_peer(frame, context, author, aliases, now_ms);
        }
        if frame.production.is_some() {
            return Err("PLUS proof network mismatch".into());
        }
        let account = frame.verify(context, author)?;
        let known = self.state.peers.get(&account);
        if known.is_none() && frame.certificate.is_none() {
            return Ok(());
        }
        if let Some(old) = self.state.peers.get(&account) {
            if old.revision > frame.revision {
                return Ok(());
            }
            if old.revision == frame.revision && old.certificate != frame.certificate {
                return Err("conflicting PLUS advertisement".into());
            }
        } else if self.state.peers.len() >= 2048 {
            return Err("PLUS peer cache limit reached".into());
        }
        if let Some(certificate) = &frame.certificate {
            if certificate.expires_at_ms <= now_ms {
                return Err("expired PLUS certificate".into());
            }
            if !known.is_some_and(|p| p.certificate.as_ref() == Some(certificate)) {
                self.issuer.verify(certificate, &account, now_ms)?;
            }
        }
        let mut mapped = self
            .state
            .peers
            .get(&account)
            .map(|p| p.aliases.clone())
            .unwrap_or_default();
        // A withdrawal updates the account revision without allocating aliases.
        if frame.certificate.is_some() {
            for alias in aliases {
                if alias.len() > 256 {
                    return Err("invalid PLUS identity alias".into());
                }
                if !mapped.contains(alias) {
                    mapped.push(alias.clone());
                }
            }
        }
        if mapped.len() > 128 {
            return Err("PLUS identity alias limit reached".into());
        }
        if self
            .state
            .peers
            .get(&account)
            .is_some_and(|p| p.revision == frame.revision && p.aliases == mapped)
        {
            return Ok(());
        }
        let mut next = self.state.clone();
        next.peers.insert(
            account,
            PeerEvidence {
                revision: frame.revision,
                certificate: frame.certificate.clone(),
                aliases: mapped,
            },
        );
        self.save(next)
    }

    pub(super) fn peer_badges(&self, now_ms: u64) -> Vec<PlusPeerBadge> {
        if self.issuer.mainnet_key_id.is_some() {
            return self.mainnet_peer_badges(now_ms);
        }
        self.state
            .peers
            .values()
            .filter_map(|p| {
                p.certificate
                    .as_ref()
                    .filter(|c| c.expires_at_ms > now_ms)
                    .map(|c| (p, c))
            })
            .flat_map(|(p, c)| {
                p.aliases.iter().map(move |identity| PlusPeerBadge {
                    identity: identity.clone(),
                    expires_at_ms: c.expires_at_ms,
                })
            })
            .collect()
    }
}
