//! Roster member offers and the local DM links they establish.

use super::*;

impl OrgRuntime {
    /// Consume a pending offer; the returned view carries the invite URI
    /// for the DM runtime's accept path and the peer to link afterwards.
    pub fn accept_dm_offer(
        &mut self,
        org_pubkey: &str,
        offer_id: &str,
    ) -> Result<OrgDmOfferView, OrgError> {
        let offer = self.peek_dm_offer(org_pubkey, offer_id)?;
        self.resolve_offer(org_pubkey, offer_id, Some((&offer.from_peer_id, None)))?;
        Ok(offer)
    }

    pub(crate) fn peek_dm_offer(
        &mut self,
        org_pubkey: &str,
        offer_id: &str,
    ) -> Result<OrgDmOfferView, OrgError> {
        self.session_mut(org_pubkey)?
            .dm_offers
            .iter()
            .find(|offer| offer.offer_id == offer_id)
            .cloned()
            .ok_or_else(|| OrgError::Codec(format!("unknown dm offer {offer_id}")))
    }

    /// Consume a pending group offer; the view carries the invite URI for
    /// the group runtime's join path.
    pub fn accept_group_offer(
        &mut self,
        org_pubkey: &str,
        offer_id: &str,
    ) -> Result<OrgGroupOfferView, OrgError> {
        let offer = self.peek_group_offer(org_pubkey, offer_id)?;
        self.resolve_offer(org_pubkey, offer_id, None)?;
        Ok(offer)
    }

    pub(crate) fn peek_group_offer(
        &mut self,
        org_pubkey: &str,
        offer_id: &str,
    ) -> Result<OrgGroupOfferView, OrgError> {
        self.session_mut(org_pubkey)?
            .group_offers
            .iter()
            .find(|offer| offer.offer_id == offer_id)
            .cloned()
            .ok_or_else(|| OrgError::Codec(format!("unknown group offer {offer_id}")))
    }

    pub fn dismiss_group_offer(
        &mut self,
        org_pubkey: &str,
        offer_id: &str,
    ) -> Result<(), OrgError> {
        if !self
            .session_mut(org_pubkey)?
            .group_offers
            .iter()
            .any(|offer| offer.offer_id == offer_id)
        {
            return Ok(());
        }
        self.resolve_offer(org_pubkey, offer_id, None)
    }

    pub fn dismiss_dm_offer(&mut self, org_pubkey: &str, offer_id: &str) -> Result<(), OrgError> {
        if !self
            .session_mut(org_pubkey)?
            .dm_offers
            .iter()
            .any(|offer| offer.offer_id == offer_id)
        {
            return Ok(());
        }
        self.resolve_offer(org_pubkey, offer_id, None)
    }

    /// Offer a DM to a roster member: lib.rs creates the invite via the DM
    /// runtime first, then routes the URI here. The link is recorded
    /// immediately so the sender's UI can navigate before the session id is
    /// known; `link_dm` fills it in.
    pub fn send_dm_offer(
        &mut self,
        org_pubkey: &str,
        target_peer_id: &str,
        invite_uri: &str,
    ) -> Result<(), OrgError> {
        let session = self.session_mut(org_pubkey)?;
        let message = OrgMessage::DmOffer {
            offer_id: random_id()?,
            target_peer_id: target_peer_id.to_string(),
            from_name: session.display_name.clone(),
            invite_uri: invite_uri.to_string(),
        };
        publish_signed(session, &message)?;
        upsert_link(&mut session.dm_links, target_peer_id, None);
        let record = session.to_record();
        self.persist_record(record).map(|_| ())
    }

    /// Offer an org-bound group to a roster member over org-control.
    pub fn send_group_offer(
        &mut self,
        org_pubkey: &str,
        target_peer_id: &str,
        group_invite_uri: &str,
        group_label: Option<String>,
    ) -> Result<(), OrgError> {
        let session = self.session_mut(org_pubkey)?;
        let message = OrgMessage::GroupOffer {
            offer_id: random_id()?,
            target_peer_id: target_peer_id.to_string(),
            from_name: session.display_name.clone(),
            group_label,
            group_invite_uri: group_invite_uri.to_string(),
        };
        publish_signed(session, &message)
    }

    pub(crate) fn validate_group_targets(
        &mut self,
        org_pubkey: &str,
        targets: &[String],
    ) -> Result<(), OrgError> {
        self.drain_inbound();
        let session = self.session_mut(org_pubkey)?;
        if !session.in_roster() {
            return Err(OrgError::Codec("org membership is pending".into()));
        }
        if let Some(target) = targets
            .iter()
            .find(|target| !session.sender_in_roster(target))
        {
            return Err(OrgError::Codec(format!(
                "group invitation target is not in org roster: {target}"
            )));
        }
        Ok(())
    }

    /// Attach the DM session id to an org link once the DM runtime created
    /// or accepted the session. Links are never deleted on revocation — the
    /// DM outlives org membership (spec §6), the UI just badges it.
    pub fn link_dm(
        &mut self,
        org_pubkey: &str,
        peer_id: &str,
        session_id: &str,
    ) -> Result<(), OrgError> {
        let session = self.session_mut(org_pubkey)?;
        upsert_link(&mut session.dm_links, peer_id, Some(session_id.to_string()));
        let record = session.to_record();
        self.persist_record(record).map(|_| ())
    }
}
