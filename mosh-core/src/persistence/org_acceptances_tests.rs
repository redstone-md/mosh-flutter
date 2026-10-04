use super::*;
use crate::test_temp_directory::TempDirectory;
use serde_json::{json, Value};
use std::sync::Arc;

const ORG: &str = "org-key";
const OFFER: &str = "accepted-offer";
const CONVERSATION: &str = "native-conversation";

struct Fixture {
    store: Arc<Persistence>,
    _directory: TempDirectory,
    group: bool,
}

impl Fixture {
    fn new(group: bool) -> Self {
        let directory = TempDirectory::new("mosh-atomic-org-acceptance");
        let store = Arc::new(
            Persistence::open_with_dek(&directory.path().join("history.redb"), [97; 32]).unwrap(),
        );
        Self {
            store,
            _directory: directory,
            group,
        }
    }

    fn org_record(&self) -> Value {
        let offer = if self.group {
            json!({"offer_id": OFFER, "from_peer_id": "peer", "from_name": "Bob",
                "group_label": null, "group_invite_uri": "mosh://group"})
        } else {
            json!({"offer_id": OFFER, "from_peer_id": "peer", "from_name": "Bob",
                "invite_uri": "mosh://invite"})
        };
        json!({
            "org_pubkey": ORG, "org_name": "Work", "mesh_id": "org-mesh",
            "display_name": "Alice", "listen_port": 0, "static_peer": null,
            "dm_links": [], "resolved_offer_ids": [],
            "pending_acceptances": {OFFER: {
                "kind": if self.group { "group" } else { "dm" },
                "conversation_id": CONVERSATION, "signer_public": vec![7; 32], "offer": offer
            }}
        })
    }

    fn put_org(&self, record: &Value) -> Result<(), PersistenceError> {
        self.store
            .put_org_record(ORG, &serde_json::to_vec(record).unwrap())
    }

    fn recovery_record(&self) -> crate::org_runtime::PersistedOrgRecord {
        let mut record = self.org_record();
        record["pending_acceptances"][OFFER]["recovery"] = json!({
            "provider_snapshot": vec![11; 16], "participant_id": "original-participant",
            "mls_group_id": []
        });
        serde_json::from_value(record).unwrap()
    }

    fn stored_org(&self) -> Value {
        serde_json::from_slice(&self.store.get_org_record(ORG).unwrap().unwrap()).unwrap()
    }

    fn write_native(&self, ready: bool, signer: u8) -> Result<(), PersistenceError> {
        let group_id = if ready { vec![1] } else { vec![] };
        let record = if self.group {
            json!({"group_id": CONVERSATION, "signer_public": vec![signer; 32],
                "mls_group_id": group_id, "joined": ready})
        } else {
            json!({"session_id": CONVERSATION, "signer_public": vec![signer; 32],
                "group_id": group_id})
        };
        let record = serde_json::to_vec(&record).unwrap();
        if self.group {
            self.store
                .put_group_transition(CONVERSATION, &record, b"native snapshot")
        } else {
            self.store
                .put_dm_transition(CONVERSATION, &record, b"native snapshot")
        }
    }

    fn close_native(&self) {
        if self.group {
            self.store.delete_group(CONVERSATION).unwrap();
        } else {
            self.store.delete_session(CONVERSATION).unwrap();
        }
    }

    fn assert_pending(&self) {
        let record = self.stored_org();
        assert!(record["pending_acceptances"].get(OFFER).is_some());
        assert_eq!(record["resolved_offer_ids"], json!([]));
    }

    fn assert_retired(&self) {
        let record = self.stored_org();
        assert!(record["pending_acceptances"].get(OFFER).is_none());
        assert_eq!(record["resolved_offer_ids"], json!([OFFER]));
    }
}

#[test]
fn a_completed_native_join_retires_its_offer_before_immediate_close() {
    for group in [false, true] {
        let fixture = Fixture::new(group);
        fixture.put_org(&fixture.org_record()).unwrap();
        fixture.write_native(true, 7).unwrap();
        fixture.close_native();
        fixture.assert_retired();
    }
}

#[test]
fn a_stale_org_rewrite_cannot_resurrect_a_retired_offer() {
    for group in [false, true] {
        let fixture = Fixture::new(group);
        let mut cached = fixture.org_record();
        fixture.put_org(&cached).unwrap();
        fixture.write_native(true, 7).unwrap();
        fixture.close_native();
        cached["display_name"] = json!("new display name");
        fixture.put_org(&cached).unwrap();
        fixture.assert_retired();
        assert_eq!(fixture.stored_org()["display_name"], "new display name");
    }
}

#[test]
fn org_registration_reconciles_a_join_that_became_durable_first() {
    for group in [false, true] {
        let fixture = Fixture::new(group);
        fixture.write_native(true, 7).unwrap();
        fixture.put_org(&fixture.org_record()).unwrap();
        fixture.assert_retired();
    }
}

#[test]
fn a_refused_native_snapshot_preserves_pending_and_previous_native_state() {
    for group in [false, true] {
        let fixture = Fixture::new(group);
        fixture.put_org(&fixture.org_record()).unwrap();
        fixture.write_native(false, 7).unwrap();
        let fault = if group {
            fixture.store.refuse_group_snapshot_writes()
        } else {
            fixture.store.refuse_dm_snapshot_writes()
        };
        assert!(fixture.write_native(true, 7).is_err());
        fixture.assert_pending();
        drop(fault);
        fixture.put_org(&fixture.org_record()).unwrap();
        fixture.assert_pending();
        fixture.write_native(true, 7).unwrap();
        fixture.assert_retired();
    }
}

#[test]
fn a_refused_org_retirement_aborts_the_native_transition_too() {
    for group in [false, true] {
        let fixture = Fixture::new(group);
        fixture.put_org(&fixture.org_record()).unwrap();
        fixture.write_native(false, 7).unwrap();
        let fault = fixture.store.refuse_org_record_writes();
        assert!(fixture.write_native(true, 7).is_err());
        drop(fault);
        fixture.put_org(&fixture.org_record()).unwrap();
        fixture.assert_pending();
        fixture.write_native(true, 7).unwrap();
        fixture.assert_retired();
    }
}

#[test]
fn matching_conversation_id_without_the_accepting_signer_cannot_retire_an_offer() {
    for group in [false, true] {
        let fixture = Fixture::new(group);
        fixture.put_org(&fixture.org_record()).unwrap();
        fixture.write_native(true, 8).unwrap();
        fixture.put_org(&fixture.org_record()).unwrap();
        fixture.assert_pending();
        fixture.write_native(true, 7).unwrap();
        fixture.assert_retired();
    }
}

#[test]
fn unreadable_unrelated_org_records_do_not_block_native_transitions() {
    for group in [false, true] {
        for blob in [
            encrypt_blob(&[97; 32], b"malformed org JSON").unwrap(),
            b"undecryptable org record".to_vec(),
        ] {
            let fixture = Fixture::new(group);
            fixture.put_org(&fixture.org_record()).unwrap();
            fixture
                .store
                .write(|tx| Persistence::update_row(tx, ORG_RECORDS, "unrelated", Some(&blob)))
                .unwrap();
            fixture.write_native(true, 7).unwrap();
            fixture.assert_retired();
            let snapshot = if group {
                fixture.store.get_group_mls_snapshot(CONVERSATION)
            } else {
                fixture.store.get_mls_snapshot(CONVERSATION)
            };
            assert_eq!(snapshot.unwrap().unwrap(), b"native snapshot");
        }
    }
}

#[test]
fn canonical_writer_returns_retired_metadata_without_its_recovery_snapshot() {
    for group in [false, true] {
        let fixture = Fixture::new(group);
        fixture.write_native(true, 7).unwrap();
        let candidate = fixture.recovery_record();
        let canonical = fixture
            .store
            .put_reconciled_org_record(candidate.clone())
            .unwrap();
        assert!(canonical.pending_acceptances.is_empty());
        assert!(canonical.resolved_offer_ids.contains(OFFER));
        assert_eq!(
            serde_json::to_value(canonical).unwrap(),
            fixture.stored_org()
        );
        fixture.close_native();
        let canonical = fixture.store.put_reconciled_org_record(candidate).unwrap();
        assert!(canonical.pending_acceptances.is_empty());
        fixture.assert_retired();
    }
}

#[test]
fn refused_canonical_writer_preserves_the_original_pending_recovery() {
    for group in [false, true] {
        let fixture = Fixture::new(group);
        let mut candidate = fixture.recovery_record();
        let canonical = fixture
            .store
            .put_reconciled_org_record(candidate.clone())
            .unwrap();
        let previous = serde_json::to_value(canonical).unwrap();
        assert_eq!(previous, fixture.stored_org());
        let fault = fixture.store.refuse_org_record_writes();
        candidate.display_name = "uncommitted name".into();
        candidate.resolved_offer_ids.insert(OFFER.into());
        assert!(fixture.store.put_reconciled_org_record(candidate).is_err());
        drop(fault);
        assert_eq!(fixture.stored_org(), previous);
        fixture.assert_pending();
    }
}
