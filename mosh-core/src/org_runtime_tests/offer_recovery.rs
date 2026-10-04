use super::*;
use crate::test_temp_directory::TempDirectory;

struct Fixture {
    runtime: OrgRuntime,
    store: Arc<Persistence>,
    member: SigningKey,
    own_peer: String,
    _directory: TempDirectory,
}

#[derive(Clone, Copy)]
enum Resolution {
    AcceptDm,
    DismissDm,
    AcceptGroup,
    DismissGroup,
}

impl Fixture {
    fn new() -> Self {
        drain_received_messages();
        let directory = TempDirectory::new("mosh-org-offer-recovery");
        let store = Arc::new(
            Persistence::open_with_dek(&directory.path().join("history.redb"), [85; 32]).unwrap(),
        );
        store.put_moss_identity(&identity_blob([86; 32])).unwrap();
        let own_peer = org_signing::peer_id_hex(&SigningKey::from_bytes(&[86; 32]));
        let member = SigningKey::from_bytes(&[87; 32]);
        let member_peer = org_signing::peer_id_hex(&member);
        let moss = Arc::new(MossFfiRuntime::load_default().unwrap());
        let mut runtime = OrgRuntime::from_shared(moss, Some(store.clone()));
        runtime
            .join_org(JoinOrgRequest {
                bundle_uri: org_bundle("offer-recovery-mesh"),
                display_name: "Alice".into(),
                listen_port: 0,
                static_peer: None,
            })
            .unwrap();
        runtime.ingest_for_test(
            &org_key_hex(),
            &roster_wire(&signed_roster(
                1,
                &[
                    (&own_peer, "Alice", "admin"),
                    (&member_peer, "Bob", "member"),
                ],
            )),
        );
        Self {
            runtime,
            store,
            member,
            own_peer,
            _directory: directory,
        }
    }

    fn deliver(&mut self, resolution: Resolution, id: &str) {
        let message = match resolution {
            Resolution::AcceptDm | Resolution::DismissDm => OrgMessage::DmOffer {
                offer_id: id.into(),
                target_peer_id: self.own_peer.clone(),
                from_name: "Bob".into(),
                invite_uri:
                    "mosh://invite?mesh=peer&session=peer#fp=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
                        .into(),
            },
            Resolution::AcceptGroup | Resolution::DismissGroup => OrgMessage::GroupOffer {
                offer_id: id.into(),
                target_peer_id: self.own_peer.clone(),
                from_name: "Bob".into(),
                group_label: None,
                group_invite_uri:
                    "mosh://group?mesh=peer&group=peer#fp=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA".into(),
            },
        };
        let payload = signed_wire(&self.member, "offer-recovery-mesh", &message);
        self.runtime.ingest_for_test(&org_key_hex(), &payload);
    }

    fn resolve(&mut self, resolution: Resolution, id: &str) -> Result<(), OrgError> {
        match resolution {
            Resolution::AcceptDm => self.runtime.accept_dm_offer(&org_key_hex(), id).map(|_| ()),
            Resolution::DismissDm => self.runtime.dismiss_dm_offer(&org_key_hex(), id),
            Resolution::AcceptGroup => self
                .runtime
                .accept_group_offer(&org_key_hex(), id)
                .map(|_| ()),
            Resolution::DismissGroup => self.runtime.dismiss_group_offer(&org_key_hex(), id),
        }
    }

    fn restart(&mut self) {
        self.runtime = OrgRuntime::from_shared(
            Arc::new(MossFfiRuntime::load_default().unwrap()),
            Some(self.store.clone()),
        );
        self.runtime.rehydrate();
    }

    fn offer_count(&mut self) -> usize {
        let snapshot = self.runtime.poll(&org_key_hex()).unwrap();
        snapshot.dm_offers.len() + snapshot.group_offers.len()
    }
}

fn resolutions() -> [Resolution; 4] {
    [
        Resolution::AcceptDm,
        Resolution::DismissDm,
        Resolution::AcceptGroup,
        Resolution::DismissGroup,
    ]
}

#[test]
fn resolved_dm_and_group_offers_do_not_reappear_after_restart() {
    let _lock = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    for resolution in resolutions() {
        let mut fixture = Fixture::new();
        fixture.deliver(resolution, "resolved");
        assert_eq!(fixture.offer_count(), 1);
        fixture.resolve(resolution, "resolved").unwrap();
        fixture.restart();
        fixture.deliver(resolution, "resolved");
        assert_eq!(
            fixture.offer_count(),
            0,
            "resolved offer replay must stay dismissed"
        );
    }
}

#[test]
fn unresolved_offers_can_replay_after_restart() {
    let _lock = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    for resolution in [Resolution::AcceptDm, Resolution::AcceptGroup] {
        let mut fixture = Fixture::new();
        fixture.deliver(resolution, "pending");
        assert_eq!(fixture.offer_count(), 1);
        fixture.restart();
        fixture.deliver(resolution, "pending");
        assert_eq!(
            fixture.offer_count(),
            1,
            "seeing an offer must not persist a resolution"
        );
    }
}

#[test]
fn refused_resolution_keeps_each_offer_and_link_unchanged_for_retry() {
    let _lock = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    for resolution in resolutions() {
        let mut fixture = Fixture::new();
        fixture.deliver(resolution, "retry");
        let fault = fixture.store.refuse_org_record_writes();
        assert!(matches!(
            fixture.resolve(resolution, "retry"),
            Err(OrgError::Persistence(_))
        ));
        assert_eq!(fixture.offer_count(), 1);
        assert!(fixture
            .runtime
            .poll(&org_key_hex())
            .unwrap()
            .dm_links
            .is_empty());
        drop(fault);
        fixture.restart();
        fixture.deliver(resolution, "retry");
        assert_eq!(fixture.offer_count(), 1);
        fixture.resolve(resolution, "retry").unwrap();
        fixture.restart();
        fixture.deliver(resolution, "retry");
        assert_eq!(fixture.offer_count(), 0);
    }
}

#[test]
fn legacy_org_records_load_without_resolved_offer_metadata() {
    let _lock = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let mut fixture = Fixture::new();
    let bytes = fixture
        .store
        .get_org_record(&org_key_hex())
        .unwrap()
        .unwrap();
    let mut legacy: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    legacy.as_object_mut().unwrap().remove("resolved_offer_ids");
    fixture
        .store
        .put_org_record(&org_key_hex(), &serde_json::to_vec(&legacy).unwrap())
        .unwrap();
    fixture.restart();
    fixture.deliver(Resolution::AcceptDm, "legacy-pending");
    assert_eq!(fixture.offer_count(), 1);
}
