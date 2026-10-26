//! Inspect only generated-fixture provenance, never attachment keys or plaintext.
use super::*;

pub(super) fn assert_original_offer(peer: &mut Peer, id: &str, imported: bool) {
    let facts = peer.stop_and_inspect_background("group", id);
    let rows = facts["messages"].as_array().unwrap();
    assert_eq!(rows.len(), 1, "{facts}");
    assert_eq!(rows[0]["has_offer"], true, "{facts}");
    assert_eq!(rows[0]["has_preview"], true, "{facts}");
    if imported {
        assert_eq!(
            rows[0]["group_history_basis"], "inherited_import",
            "{facts}"
        );
    }
}
