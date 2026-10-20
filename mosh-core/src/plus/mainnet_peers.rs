use super::{
    protocol::ProductionProof, Certificate, Issuer, PlusFrame, PlusPeerBadge, PlusRuntime,
};
use serde::{Deserialize, Serialize};

#[derive(Clone, Serialize, Deserialize)]
pub(super) struct PeerProof {
    counter: u64,
    writer: String,
    visible: bool,
    certificates: Vec<Certificate>,
    aliases: Vec<String>,
}

impl PeerProof {
    pub(super) fn trusted_by(&self, issuer: &Issuer, account: &str) -> bool {
        self.certificates
            .iter()
            .all(|certificate| issuer.verify_claims(certificate, account).is_ok())
    }
}

impl PlusRuntime {
    pub(super) fn mainnet_frame(
        &self,
        context: &str,
        peer: &str,
        author: &str,
        sign: impl FnOnce(&[u8]) -> Result<Vec<u8>, String>,
        now: u64,
    ) -> Result<Option<PlusFrame>, String> {
        if !self.state.ever_visible {
            return Ok(None);
        }
        let Some(ownership) =
            crate::message_deletion::ownership::create(Some(&self.store), Some(peer), author)
                .map_err(|_| "PLUS account proof unavailable")?
        else {
            return Ok(None);
        };
        if crate::message_deletion::ownership::verify(&ownership, author)? != self.state.account_id
        {
            return Err("PLUS account changed".into());
        }
        let mut certificates = Vec::new();
        if self.state.visible {
            let available: Vec<_> = self
                .state
                .mainnet
                .certificates
                .values()
                .filter(|c| self.issuer.verify_claims(c, &self.state.account_id).is_ok())
                .collect();
            if let Some(current) = available
                .iter()
                .filter(|c| self.issuer.verify(c, &self.state.account_id, now).is_ok())
                .max_by_key(|c| c.expires_at_ms)
            {
                certificates.push((*current).clone());
            }
            if let Some(next) = available
                .iter()
                .filter(|c| {
                    c.mainnet
                        .as_ref()
                        .is_some_and(|claims| claims.valid_from_ms > now)
                })
                .min_by_key(|c| c.mainnet.as_ref().map(|claims| claims.valid_from_ms))
            {
                certificates.push((*next).clone());
            }
        }
        let proof = ProductionProof {
            counter: self.state.mainnet.visibility_counter,
            writer: self.state.mainnet.visibility_writer.clone(),
            visible: self.state.visible,
            certificates,
        };
        let mut frame = PlusFrame {
            context: context.into(),
            author: author.into(),
            ownership,
            revision: proof.counter,
            certificate: None,
            production: Some(proof),
            signature: String::new(),
        };
        frame.signature = hex::encode(sign(&frame.input()?)?);
        Ok(Some(frame))
    }

    pub(super) fn accept_mainnet_peer(
        &mut self,
        frame: &PlusFrame,
        context: &str,
        author: &str,
        aliases: &[String],
        now: u64,
    ) -> Result<(), String> {
        let account = frame.verify(context, author)?;
        let proof = frame
            .production
            .as_ref()
            .ok_or("PLUS proof network mismatch")?;
        if proof.writer.is_empty()
            || proof.writer.len() > 128
            || proof.certificates.len() > 2
            || !proof.visible && !proof.certificates.is_empty()
        {
            return Err("invalid PLUS proof".into());
        }
        for certificate in &proof.certificates {
            self.issuer.verify_claims(certificate, &account)?;
        }
        let old = self.state.mainnet.peers.get(&account);
        if old.is_none() && self.state.mainnet.peers.len() >= 2048 {
            return Err("PLUS peer limit reached".into());
        }
        let mut next = old.cloned().unwrap_or(PeerProof {
            counter: 0,
            writer: String::new(),
            visible: false,
            certificates: Vec::new(),
            aliases: Vec::new(),
        });
        match (proof.counter, proof.writer.as_str()).cmp(&(next.counter, next.writer.as_str())) {
            std::cmp::Ordering::Less => return Ok(()),
            std::cmp::Ordering::Equal if next.visible != proof.visible => {
                return Err("conflicting PLUS visibility".into())
            }
            _ => {
                next.counter = proof.counter;
                next.writer = proof.writer.clone();
                next.visible = proof.visible;
            }
        }
        next.certificates.retain(|c| c.expires_at_ms > now);
        for certificate in &proof.certificates {
            if certificate.expires_at_ms > now && !next.certificates.contains(certificate) {
                next.certificates.push(certificate.clone());
            }
        }
        if proof.visible {
            for alias in aliases {
                if alias.len() > 256 {
                    return Err("invalid PLUS alias".into());
                }
                if !next.aliases.contains(alias) {
                    next.aliases.push(alias.clone());
                }
            }
        }
        if next.aliases.len() > 128 || next.certificates.len() > 64 {
            return Err("PLUS peer evidence limit reached".into());
        }
        let mut state = self.state.clone();
        state.mainnet.peers.insert(account, next);
        self.save(state)
    }

    pub(super) fn mainnet_peer_badges(&self, now: u64) -> Vec<PlusPeerBadge> {
        self.state
            .mainnet
            .peers
            .iter()
            .filter(|(_, proof)| proof.visible)
            .filter_map(|(account, proof)| {
                proof
                    .certificates
                    .iter()
                    .filter(|c| self.issuer.verify(c, account, now).is_ok())
                    .map(|c| c.expires_at_ms)
                    .max()
                    .map(|until| (proof, until))
            })
            .flat_map(|(proof, until)| {
                proof.aliases.iter().map(move |identity| PlusPeerBadge {
                    identity: identity.clone(),
                    expires_at_ms: until,
                })
            })
            .collect()
    }
}
