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
            offer_id: format!("offer-{}", &sha256_hex(invite_uri.as_bytes())[..16]),
            from_device,
            from_fingerprint,
            target_fingerprint,
            invite_uri,
        }
    }

    /// Files an offer that just arrived. It is kept only when it names us,
    /// did not come from us, and is not one we already hold.
    pub fn receive(&mut self, offer: DmOffer, own_fingerprint: &str) {
        if offer.target_fingerprint != own_fingerprint
            || offer.from_fingerprint == own_fingerprint
            || self.holds(&offer.offer_id)
        {
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

    fn holds(&self, offer_id: &str) -> bool {
        self.offers.iter().any(|offer| offer.offer_id == offer_id)
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
