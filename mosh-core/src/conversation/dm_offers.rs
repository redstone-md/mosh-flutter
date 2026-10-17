//! The private-DM invitations a conversation carries.
//!
//! Inside a channel or a group, one member can offer another a private DM: it
//! publishes an invitation aimed at that one member, and only the member it
//! names keeps it, until the offer is accepted or dismissed. Those rules are
//! the same in both kinds, so they live here once. How the offer travels, and
//! what accepting it does, stay with the kind.

use serde::{Deserialize, Serialize};

use crate::attachment_crypto::sha256_hex;

/// A request to start a private DM, surfaced inside a channel or group. The
/// initiator publishes it; the targeted member accepts the carried invite.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DmOffer {
    pub offer_id: String,
    pub from_device: String,
    pub from_fingerprint: String,
    pub target_fingerprint: String,
    pub invite_uri: String,
    /// Derived by the receiving carrier. Wire input cannot assert this value.
    #[serde(default, skip_deserializing, skip_serializing_if = "Option::is_none")]
    pub authenticated: Option<bool>,
}

/// The offers aimed at us, oldest first.
#[derive(Default)]
pub struct DmOffers {
    offers: Vec<DmOffer>,
}

impl DmOffers {
    /// Builds the invitation to publish. The id comes from the invite URI, so
    /// the same invitation published twice reads as one offer on the far side.
    pub fn mint(
        from_device: String,
        from_fingerprint: String,
        target_fingerprint: String,
        invite_uri: String,
    ) -> DmOffer {
        DmOffer {
            offer_id: Self::offer_id(&invite_uri),
            from_device,
            from_fingerprint,
            target_fingerprint,
            invite_uri,
            authenticated: None,
        }
    }

    /// Keeps addressed offers with canonical IDs. Authenticated arrivals replace
    /// an unsigned duplicate; later unverified fields cannot downgrade them.
    pub fn receive(&mut self, offer: DmOffer, own_fingerprint: &str) {
        if offer.target_fingerprint != own_fingerprint
            || offer.from_fingerprint == own_fingerprint
            || offer.offer_id != Self::offer_id(&offer.invite_uri)
        {
            return;
        }
        if let Some(old) = self
            .offers
            .iter_mut()
            .find(|old| old.offer_id == offer.offer_id)
        {
            if old.authenticated != Some(true) && offer.authenticated == Some(true) {
                *old = offer;
            }
            return;
        }
        self.offers.push(offer);
    }

    /// Drops one offer. Unknown ids are not an error: gossip can hand the
    /// same offer to a user who already sent it away.
    pub fn dismiss(&mut self, offer_id: &str) {
        self.offers.retain(|offer| offer.offer_id != offer_id);
    }

    /// The offers a snapshot carries.
    pub fn to_vec(&self) -> Vec<DmOffer> {
        self.offers.clone()
    }

    fn offer_id(invite_uri: &str) -> String {
        format!("offer-{}", &sha256_hex(invite_uri.as_bytes())[..16])
    }
}

impl DmOffer {
    pub(crate) fn signing_bytes(&self) -> Result<Vec<u8>, String> {
        let mut unsigned = self.clone();
        unsigned.authenticated = None;
        serde_json::to_vec(&unsigned).map_err(|e| e.to_string())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const US: &str = "fingerprint-us";
    const THEM: &str = "fingerprint-them";

    fn offer_from(from: &str, target: &str, invite_uri: &str) -> DmOffer {
        DmOffers::mint(
            "their laptop".to_string(),
            from.to_string(),
            target.to_string(),
            invite_uri.to_string(),
        )
    }

    #[test]
    fn the_same_invite_uri_always_mints_the_same_id() {
        let first = offer_from(THEM, US, "mosh://invite/one");
        let second = offer_from(THEM, US, "mosh://invite/one");
        let other = offer_from(THEM, US, "mosh://invite/two");

        assert_eq!(first.offer_id, second.offer_id);
        assert_ne!(first.offer_id, other.offer_id);
        assert!(first.offer_id.starts_with("offer-"));
    }

    #[test]
    fn an_offer_aimed_at_us_is_kept() {
        let mut offers = DmOffers::default();

        offers.receive(offer_from(THEM, US, "mosh://invite/one"), US);

        let kept = offers.to_vec();
        assert_eq!(kept.len(), 1);
        assert_eq!(kept[0].invite_uri, "mosh://invite/one");
    }

    #[test]
    fn an_offer_aimed_at_someone_else_is_dropped() {
        let mut offers = DmOffers::default();

        offers.receive(
            offer_from(THEM, "fingerprint-third", "mosh://invite/one"),
            US,
        );

        assert!(offers.to_vec().is_empty());
    }

    #[test]
    fn our_own_offer_coming_back_is_dropped() {
        let mut offers = DmOffers::default();

        // Our own publish, echoed to us because we also target ourselves.
        offers.receive(offer_from(US, US, "mosh://invite/one"), US);

        assert!(offers.to_vec().is_empty());
    }

    #[test]
    fn the_same_offer_twice_is_kept_once() {
        let mut offers = DmOffers::default();

        offers.receive(offer_from(THEM, US, "mosh://invite/one"), US);
        offers.receive(offer_from(THEM, US, "mosh://invite/one"), US);

        assert_eq!(offers.to_vec().len(), 1);
    }

    #[test]
    fn authenticated_offer_replaces_unsigned_fields_and_cannot_be_downgraded() {
        let mut offers = DmOffers::default();
        let mut unsigned = offer_from(THEM, US, "mosh://invite/one");
        unsigned.from_device = "Forged name".into();
        offers.receive(unsigned.clone(), US);
        let mut verified = offer_from(THEM, US, "mosh://invite/one");
        verified.authenticated = Some(true);
        offers.receive(verified, US);
        offers.receive(unsigned, US);
        let saved = offers.to_vec();
        assert_eq!(saved.len(), 1);
        assert_eq!(saved[0].from_device, "their laptop");
        assert_eq!(saved[0].authenticated, Some(true));
    }

    #[test]
    fn copying_an_offer_id_cannot_suppress_a_different_invite() {
        let mut offers = DmOffers::default();
        let verified = offer_from(THEM, US, "mosh://invite/one");
        let mut collision = offer_from("other-peer", US, "mosh://invite/two");
        collision.offer_id = verified.offer_id.clone();
        collision.authenticated = Some(true);
        offers.receive(collision, US);
        offers.receive(verified, US);
        let saved = offers.to_vec();
        assert_eq!(saved.len(), 1);
        assert_eq!(saved[0].invite_uri, "mosh://invite/one");
        assert_eq!(saved[0].from_fingerprint, THEM);
    }

    #[test]
    fn dismiss_drops_that_offer_and_leaves_the_rest() {
        let mut offers = DmOffers::default();
        offers.receive(offer_from(THEM, US, "mosh://invite/one"), US);
        offers.receive(offer_from(THEM, US, "mosh://invite/two"), US);
        let first_id = offers.to_vec()[0].offer_id.clone();

        offers.dismiss(&first_id);
        offers.dismiss("offer-never-existed");

        let left = offers.to_vec();
        assert_eq!(left.len(), 1);
        assert_eq!(left[0].invite_uri, "mosh://invite/two");
    }
}
