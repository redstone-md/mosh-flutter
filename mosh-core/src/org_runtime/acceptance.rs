//! Retain accepted offers until the native conversation has durable MLS state.

use super::*;

#[derive(Clone, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub(crate) enum PendingAcceptance {
    Dm {
        conversation_id: String,
        signer_public: Vec<u8>,
        offer: OrgDmOfferView,
        #[serde(default)]
        recovery: Option<PendingJoinRecovery>,
    },
    Group {
        conversation_id: String,
        signer_public: Vec<u8>,
        offer: OrgGroupOfferView,
        #[serde(default)]
        recovery: Option<PendingJoinRecovery>,
    },
}

/// Private key material is serialized only inside the encrypted org record.
#[derive(Clone, Serialize, Deserialize)]
pub(crate) struct PendingJoinRecovery {
    pub(crate) provider_snapshot: Vec<u8>,
    pub(crate) participant_id: String,
    pub(crate) mls_group_id: Vec<u8>,
    #[serde(default)]
    pub(crate) key_package: Option<Vec<u8>>,
}

pub(crate) struct PreparedJoin {
    pub(crate) crypto: crate::mls_crypto::MlsSessionCrypto,
    pub(crate) participant_id: String,
    pub(crate) key_package: Option<Vec<u8>>,
}

impl PendingJoinRecovery {
    pub(crate) fn prepare(
        identity: &str,
        recovery: Option<(Vec<u8>, Self)>,
    ) -> Result<PreparedJoin, crate::mls_crypto::MlsCryptoError> {
        use crate::mls_crypto::MlsSessionCrypto;
        let (mut crypto, participant_id, package) = match recovery {
            Some((signer, recovery)) => (
                recovery.restore_crypto(identity, &signer)?,
                recovery.participant_id,
                recovery.key_package,
            ),
            None => {
                let crypto = MlsSessionCrypto::new(identity)?;
                let participant = crypto.random_token("participant")?;
                (crypto, participant, None)
            }
        };
        let key_package = if crypto.is_ready() {
            None
        } else {
            Some(match package {
                Some(package) => package,
                None => crypto.key_package_bytes()?,
            })
        };
        Ok(PreparedJoin {
            crypto,
            participant_id,
            key_package,
        })
    }
    pub(crate) fn restore_crypto(
        &self,
        identity: &str,
        signer: &[u8],
    ) -> Result<crate::mls_crypto::MlsSessionCrypto, crate::mls_crypto::MlsCryptoError> {
        use crate::mls_crypto::MlsSessionCrypto;
        if self.mls_group_id.is_empty() {
            MlsSessionCrypto::restore_unjoined(identity, signer, &self.provider_snapshot)
        } else {
            MlsSessionCrypto::restore(
                identity,
                signer,
                &self.provider_snapshot,
                &self.mls_group_id,
            )
        }
    }
}

impl PendingAcceptance {
    pub(crate) fn conversation_id(&self) -> &str {
        match self {
            Self::Dm {
                conversation_id, ..
            }
            | Self::Group {
                conversation_id, ..
            } => conversation_id,
        }
    }

    pub(crate) fn signer_public(&self) -> &[u8] {
        match self {
            Self::Dm { signer_public, .. } | Self::Group { signer_public, .. } => signer_public,
        }
    }
}

impl OrgSession {
    pub(super) fn prune_resolved_acceptances(&mut self) {
        self.pending_acceptances
            .retain(|id, _| !self.resolved_offer_ids.contains(id));
        self.dm_offers
            .retain(|offer| !self.resolved_offer_ids.contains(&offer.offer_id));
        self.group_offers
            .retain(|offer| !self.resolved_offer_ids.contains(&offer.offer_id));
    }
    /// A pre-Welcome join cannot rehydrate; show its retained offer for retry.
    pub(super) fn restore_pending_offers(&mut self) {
        for (id, acceptance) in &self.pending_acceptances {
            if self.resolved_offer_ids.contains(id) {
                continue;
            }
            self.seen_offer_ids.insert(id.clone());
            match acceptance {
                PendingAcceptance::Dm { offer, .. } => self.dm_offers.push(offer.clone()),
                PendingAcceptance::Group { offer, .. } => self.group_offers.push(offer.clone()),
            }
        }
    }
}

impl OrgRuntime {
    /// Publishing failed before polling; the committed recovery offer can retry.
    pub(crate) fn reexpose_acceptance(&mut self, org_pubkey: &str, offer_id: &str) {
        let Some(session) = self.orgs.get_mut(org_pubkey) else {
            return;
        };
        if session.resolved_offer_ids.contains(offer_id) {
            return;
        }
        match session.pending_acceptances.get(offer_id) {
            Some(PendingAcceptance::Dm { offer, .. })
                if !session
                    .dm_offers
                    .iter()
                    .any(|pending| pending.offer_id == offer_id) =>
            {
                session.dm_offers.push(offer.clone());
            }
            Some(PendingAcceptance::Group { offer, .. })
                if !session
                    .group_offers
                    .iter()
                    .any(|pending| pending.offer_id == offer_id) =>
            {
                session.group_offers.push(offer.clone());
            }
            _ => {}
        }
    }
    pub(crate) fn offer_recovery(
        &mut self,
        org_pubkey: &str,
        offer_id: &str,
    ) -> Result<Option<(Vec<u8>, PendingJoinRecovery)>, OrgError> {
        let session = self.session_mut(org_pubkey)?;
        Ok(session
            .pending_acceptances
            .get(offer_id)
            .and_then(|pending| {
                let (PendingAcceptance::Dm { recovery, .. }
                | PendingAcceptance::Group { recovery, .. }) = pending;
                recovery
                    .clone()
                    .map(|recovery| (pending.signer_public().to_vec(), recovery))
            }))
    }
    /// Keep the link and retryable offer until native persistence proves admission.
    pub(crate) fn complete_dm_offer(
        &mut self,
        org_pubkey: &str,
        offer_id: &str,
        session_id: &str,
        signer_public: Vec<u8>,
        recovery: PendingJoinRecovery,
    ) -> Result<(), OrgError> {
        let offer = self.peek_dm_offer(org_pubkey, offer_id)?;
        let peer_id = offer.from_peer_id.clone();
        self.commit_offer(
            org_pubkey,
            offer_id,
            Some((&peer_id, Some(session_id.to_string()))),
            Some(PendingAcceptance::Dm {
                conversation_id: session_id.to_string(),
                signer_public,
                offer,
                recovery: Some(recovery),
            }),
        )
    }

    pub(crate) fn complete_group_offer(
        &mut self,
        org_pubkey: &str,
        offer_id: &str,
        group_id: &str,
        signer_public: Vec<u8>,
        recovery: PendingJoinRecovery,
    ) -> Result<(), OrgError> {
        let offer = self.peek_group_offer(org_pubkey, offer_id)?;
        self.commit_offer(
            org_pubkey,
            offer_id,
            None,
            Some(PendingAcceptance::Group {
                conversation_id: group_id.to_string(),
                signer_public,
                offer,
                recovery: Some(recovery),
            }),
        )
    }

    pub(super) fn resolve_offer(
        &mut self,
        org_pubkey: &str,
        offer_id: &str,
        link: Option<(&str, Option<String>)>,
    ) -> Result<(), OrgError> {
        self.commit_offer(org_pubkey, offer_id, link, None)
    }

    fn commit_offer(
        &mut self,
        org_pubkey: &str,
        offer_id: &str,
        link: Option<(&str, Option<String>)>,
        acceptance: Option<PendingAcceptance>,
    ) -> Result<(), OrgError> {
        let store = self.persistence.clone();
        let session = self.session_mut(org_pubkey)?;
        let mut record = session.to_record();
        if let Some((peer_id, session_id)) = link {
            upsert_link(&mut record.dm_links, peer_id, session_id);
        }
        if let Some(acceptance) = acceptance {
            record
                .pending_acceptances
                .insert(offer_id.to_string(), acceptance);
        } else {
            record.pending_acceptances.remove(offer_id);
            record.resolved_offer_ids.insert(offer_id.to_string());
        }
        let record = super::storage::persist_org_record(store.as_deref(), record)?;
        session.dm_links = record.dm_links;
        session.resolved_offer_ids = record.resolved_offer_ids;
        session.pending_acceptances = record.pending_acceptances;
        session.prune_resolved_acceptances();
        session.dm_offers.retain(|offer| offer.offer_id != offer_id);
        session
            .group_offers
            .retain(|offer| offer.offer_id != offer_id);
        Ok(())
    }
}
