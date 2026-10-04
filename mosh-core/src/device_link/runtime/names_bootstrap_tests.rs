use super::*;

impl Fixture {
    fn add_peer(&mut self, seed: u8) -> DeviceIdentity {
        let store = Arc::new(
            Persistence::open_with_dek(
                &self._directory.path().join(format!("peer-{seed}")),
                [seed; 32],
            )
            .unwrap(),
        );
        let peer_id = hex::encode(
            SigningKey::from_bytes(&[seed; 32])
                .verifying_key()
                .as_bytes(),
        );
        let mut peer = DeviceIdentity::open(store, &peer_id).unwrap();
        let roster = self
            .runtime
            .identity
            .roster()
            .extend(peer.device().clone(), &self.runtime.identity.key())
            .unwrap();
        self.runtime.identity.adopt_roster(roster.clone()).unwrap();
        adopt(&mut self.peer, &roster);
        adopt(&mut peer, &roster);
        peer
    }

    fn receive_from(&mut self, peer: &DeviceIdentity, mut message: NameMessage) -> Result<()> {
        self.prepare_reply(&peer.device().device_id, &mut message);
        let packet =
            names_wire::seal(peer, &self.runtime.identity.device().device_id, message).unwrap();
        self.runtime.receive(&packet)
    }

    fn assert_waiting(&mut self) {
        let snapshot = self.runtime.chat_names_snapshot().unwrap();
        assert!(snapshot.pending);
        assert!(!snapshot.can_rename);
        for result in [
            self.runtime.rename_chat("channel:general", "Too early"),
            self.runtime.reset_chat_name("channel:general"),
        ] {
            assert_eq!(result.unwrap_err().kind, ChatNameErrorKind::Unavailable);
        }
    }
}

fn adopt(peer: &mut DeviceIdentity, roster: &DeviceRoster) {
    let mut record = peer.record.clone();
    record.roster = roster.clone();
    peer.update(record).unwrap();
}

fn page(peer: &DeviceIdentity, counter: u64, next: Option<String>) -> NameMessage {
    NameMessage::Batch {
        request_id: [0; 16],
        records: vec![NameRecord {
            key: "channel:general".into(),
            name: Some("Later peer".into()),
            version: NameVersion {
                counter,
                actor: peer.device().device_id.clone(),
            },
        }],
        next,
    }
}

#[test]
fn a_new_writer_waits_for_every_peer_before_rename_and_reset() {
    let _guard = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let mut fixture = Fixture::new();
    let peer = fixture.add_peer(43);
    fixture.batch(20, None);
    fixture.assert_waiting();
    fixture
        .receive_from(&peer, page(&peer, 100, Some("channel:general".into())))
        .unwrap();
    fixture.batch(20, None);
    fixture.assert_waiting();
    fixture
        .receive_from(
            &peer,
            NameMessage::Batch {
                request_id: [0; 16],
                records: vec![],
                next: None,
            },
        )
        .unwrap();
    assert!(fixture.runtime.chat_names_snapshot().unwrap().can_rename);
    fixture
        .runtime
        .rename_chat("channel:general", "Accepted")
        .unwrap();
    assert_eq!(fixture.runtime.names.page(None)[0].version.counter, 101);
    fixture.receive_from(&peer, page(&peer, 100, None)).unwrap();
    assert_eq!(
        fixture.runtime.names.name("channel:general"),
        Some("Accepted")
    );
    fixture.restart();
    fixture.runtime.reset_chat_name("channel:general").unwrap();
    assert_eq!(fixture.runtime.names.page(None)[0].version.counter, 102);
    fixture.restart();
    assert!(fixture
        .runtime
        .chat_names_snapshot()
        .unwrap()
        .entries
        .is_empty());
}

#[test]
fn unfinished_bootstrap_restarts_the_pull_round() {
    let _guard = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let mut fixture = Fixture::new();
    let peer = fixture.add_peer(43);
    fixture.batch(20, None);
    fixture.restart();
    fixture.assert_waiting();
    fixture.receive_from(&peer, page(&peer, 100, None)).unwrap();
    fixture.assert_waiting();
    fixture.batch(20, None);
    fixture
        .runtime
        .rename_chat("channel:general", "Accepted")
        .unwrap();
    assert_eq!(fixture.runtime.names.page(None)[0].version.counter, 101);
    fixture.restart();
    assert_eq!(
        fixture.runtime.names.name("channel:general"),
        Some("Accepted")
    );
    fixture.runtime.reset_chat_name("channel:general").unwrap();
}

#[test]
fn a_failed_final_peer_save_does_not_complete_bootstrap() {
    let _guard = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let mut fixture = Fixture::new();
    let peer = fixture.add_peer(43);
    fixture.batch(20, None);
    let fault = fixture.store.refuse_chat_name_writes();
    fixture.runtime.transport.sent_packets.clear();
    let error = fixture
        .receive_from(&peer, page(&peer, 100, None))
        .unwrap_err();
    assert_eq!(error.kind, DeviceLinkErrorKind::Storage);
    assert!(fixture.runtime.transport.sent_packets.is_empty());
    drop(fault);
    fixture.batch(20, None);
    fixture.assert_waiting();
    fixture.receive_from(&peer, page(&peer, 100, None)).unwrap();
    fixture
        .runtime
        .rename_chat("channel:general", "Accepted")
        .unwrap();
    assert_eq!(fixture.runtime.names.page(None)[0].version.counter, 101);
}

#[test]
fn a_roster_change_invalidates_completed_peer_pages() {
    let _guard = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let mut fixture = Fixture::new();
    let mut peer = fixture.add_peer(43);
    fixture.batch(20, None);
    let added = fixture.add_peer(44);
    adopt(&mut peer, fixture.runtime.identity.roster());
    fixture.receive_from(&peer, page(&peer, 100, None)).unwrap();
    fixture
        .receive_from(&added, page(&added, 200, None))
        .unwrap();
    fixture.assert_waiting();
    fixture.batch(20, None);
    fixture
        .runtime
        .rename_chat("channel:general", "Accepted")
        .unwrap();
    assert_eq!(fixture.runtime.names.page(None)[0].version.counter, 201);
}

#[test]
fn removed_peers_do_not_block_initial_sync() {
    let _guard = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let mut fixture = Fixture::new();
    let peer = fixture.add_peer(43);
    fixture.batch(20, None);
    fixture.assert_waiting();
    fixture
        .runtime
        .revoke(peer.device().device_id.clone())
        .unwrap();
    adopt(&mut fixture.peer, fixture.runtime.identity.roster());
    fixture.batch(20, None);
    fixture
        .runtime
        .rename_chat("channel:general", "Accepted")
        .unwrap();
    assert_eq!(fixture.runtime.names.page(None)[0].version.counter, 21);
}

#[test]
fn revocation_disables_rename_after_initial_readiness() {
    let _guard = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let mut fixture = Fixture::new();
    fixture.batch(20, None);
    assert!(fixture.runtime.chat_names_snapshot().unwrap().can_rename);
    let roster = fixture
        .peer
        .roster()
        .revoke(
            &fixture.runtime.identity.device().device_id,
            &fixture.peer.key(),
        )
        .unwrap();
    fixture.runtime.identity.adopt_roster(roster).unwrap();
    assert!(!fixture.runtime.chat_names_snapshot().unwrap().can_rename);
    assert_eq!(
        fixture
            .runtime
            .rename_chat("channel:general", "Denied")
            .unwrap_err()
            .kind,
        ChatNameErrorKind::Unauthorized
    );
}

#[test]
fn a_late_continuation_cannot_complete_a_restarted_pull() {
    let _guard = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let mut fixture = Fixture::new();
    fixture.batch(20, Some("channel:general".into()));
    let old_request = fixture
        .runtime
        .names_pending_pages
        .get(&fixture.peer.device().device_id)
        .unwrap()
        .request_id;
    let stale = names_wire::seal(
        &fixture.peer,
        &fixture.runtime.identity.device().device_id,
        NameMessage::Batch {
            request_id: old_request,
            records: vec![],
            next: None,
        },
    )
    .unwrap();
    fixture.restart();
    fixture.sync();
    fixture.runtime.receive(&stale).unwrap();
    fixture.assert_waiting();
    fixture.batch(100, None);
    fixture
        .runtime
        .rename_chat("channel:general", "Accepted")
        .unwrap();
    assert_eq!(fixture.runtime.names.page(None)[0].version.counter, 101);
}

#[test]
fn a_late_continuation_cannot_complete_a_changed_roster_pull() {
    let _guard = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let mut fixture = Fixture::new();
    fixture.batch(20, Some("channel:general".into()));
    let old_request = fixture
        .runtime
        .names_pending_pages
        .get(&fixture.peer.device().device_id)
        .unwrap()
        .request_id;
    let peer = fixture.add_peer(43);
    fixture.sync();
    let stale = names_wire::seal(
        &fixture.peer,
        &fixture.runtime.identity.device().device_id,
        NameMessage::Batch {
            request_id: old_request,
            records: vec![],
            next: None,
        },
    )
    .unwrap();
    fixture.runtime.receive(&stale).unwrap();
    fixture.receive_from(&peer, page(&peer, 100, None)).unwrap();
    fixture.assert_waiting();
    fixture.batch(20, None);
    fixture
        .runtime
        .rename_chat("channel:general", "Accepted")
        .unwrap();
    assert_eq!(fixture.runtime.names.page(None)[0].version.counter, 101);
}

fn sent_page(fixture: &Fixture) -> ([u8; 16], Option<String>) {
    let (_, message) = names_wire::open(
        &fixture.peer,
        fixture.runtime.transport.sent_packets.last().unwrap(),
    )
    .unwrap();
    match message {
        NameMessage::Request { request_id, after } => (request_id, after),
        _ => panic!("expected a page request"),
    }
}

#[test]
fn retry_reuses_the_pending_page_instead_of_restarting_slow_pulls() {
    let _guard = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let mut fixture = Fixture::new();
    fixture.sync();
    let first = sent_page(&fixture);
    fixture.sync();
    assert_eq!(sent_page(&fixture), first);
    fixture.batch(20, Some("channel:general".into()));
    let next = sent_page(&fixture);
    assert_ne!(next.0, first.0);
    assert_eq!(next.1.as_deref(), Some("channel:general"));
    fixture.sync();
    assert_eq!(sent_page(&fixture), next);
    fixture.assert_waiting();
    fixture.batch(100, None);
    fixture
        .runtime
        .rename_chat("channel:general", "Accepted")
        .unwrap();
    assert_eq!(fixture.runtime.names.page(None)[0].version.counter, 101);
}
