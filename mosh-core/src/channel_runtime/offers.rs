use super::*;

impl ChannelSession {
    pub(super) fn publish_dm_offer(
        &self,
        target_fingerprint: String,
        invite_uri: String,
    ) -> Result<(), ChannelRuntimeError> {
        let offer = DmOffers::mint(
            self.display_name.clone(),
            self.device_fingerprint.clone(),
            target_fingerprint,
            invite_uri,
        );
        let origin = crate::message_deletion::MessageOrigin::sign(
            &format!("channel-offer:{}", self.name),
            &offer.offer_id,
            &offer.signing_bytes().map_err(ChannelRuntimeError::Codec)?,
            self.node
                .identity_signer()
                .map_err(|e| ChannelRuntimeError::Moss(e.to_string()))?,
            self.deletions.store.as_ref(),
        )
        .map_err(ChannelRuntimeError::Codec)?;
        publish_json(
            &self.node,
            &self.mesh_id,
            &self.blob_topic,
            &ChannelBlobEnvelope::DmOffer {
                offer,
                origin: Some(origin),
            },
        )
    }

    pub(super) fn verify_offer(
        &self,
        offer: &DmOffer,
        origin: &crate::message_deletion::MessageOrigin,
    ) -> Result<(), String> {
        origin.verify(
            &format!("channel-offer:{}", self.name),
            &offer.offer_id,
            &offer.signing_bytes()?,
        )?;
        if origin.author != offer.from_fingerprint {
            return Err("channel offer author mismatch".into());
        }
        crate::private_dm_runtime::invite_ownership::verify_offered_invite(
            &offer.invite_uri,
            &offer.from_fingerprint,
            &offer.target_fingerprint,
        )
    }
}
