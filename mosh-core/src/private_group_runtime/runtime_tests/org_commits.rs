use super::super::org_commits::FALLBACK_COMMIT_DELAY_MS as DELAY;
use super::*;

/// An org group with two admins that both run the real session logic, `a`
/// on a runtime and `b` beside it, plus two plain members at the crypto
/// layer: `leaver`, who departs, and `member`, who stays and only merges.
/// Frames move between them by hand, so every arrival order is explicit.
struct TwoAdmins {
    runtime: PrivateGroupRuntime,
    b: GroupSession,
    keys: [SigningKey; 2],
    peers: [String; 2],
    stores: [Arc<Persistence>; 2],
    group_id: String,
    leaver_key: SigningKey,
    leaver: MlsSessionCrypto,
    member: MlsSessionCrypto,
    member_peer: String,
    paths: Vec<PathBuf>,
}

/// Give `a` a fixed Moss identity, so admin order is the same on every run.
fn pin_identity(store: &Persistence) -> String {
    let transport = SigningKey::from_bytes(&[17; 32]);
    let mut blob = vec![1];
    blob.extend_from_slice(&transport.to_bytes());
    blob.extend_from_slice(transport.verifying_key().as_bytes());
    // Valid X25519 pair for the fixed test secret; Moss rejects zero Noise keys.
    blob.extend_from_slice(&[17; 32]);
    blob.extend_from_slice(
        &hex::decode("7b4e909bbe7ffe44c465a220037d608ee35897d31ef972f07f74892cb0f73f13").unwrap(),
    );
    store.put_moss_identity(&blob).unwrap();
    org_signing::peer_id_hex(&transport)
}

/// A signing key whose peer-id sorts below (or above) `other`.
fn admin_key(other: &str, below: bool) -> SigningKey {
    (1..=u8::MAX)
        .map(|seed| SigningKey::from_bytes(&[seed; 32]))
        .find(|key| (org_signing::peer_id_hex(key).as_str() < other) == below)
        .expect("some seed sorts on each side")
}

/// Both admins, the leaver and optionally `member`, in both admins' stores.
fn put_roster(
    stores: &[Arc<Persistence>; 2],
    version: u64,
    admins: &[String; 2],
    leaver: &SigningKey,
    member: Option<&str>,
) {
    let mut members: Vec<_> = admins
        .iter()
        .map(|peer| serde_json::json!({"moss_peer_id": peer, "name": "a", "role": "admin"}))
        .collect();
    let plain = std::iter::once(org_signing::peer_id_hex(leaver)).chain(member.map(str::to_string));
    members.extend(
        plain.map(|peer| serde_json::json!({"moss_peer_id": peer, "name": "m", "role": "member"})),
    );
    let mut doc = serde_json::json!({
        "org_pubkey": org_key_hex(), "org_name": "acme",
        "version": version, "members": members,
    });
    let bytes = org_roster::sign_roster(&mut doc, &org_key()).unwrap();
    for store in stores {
        store.put_org_roster(&org_key_hex(), &bytes).unwrap();
    }
}

impl TwoAdmins {
    /// `b_designated` picks whose peer-id sorts first among the admins.
    fn open(name: &str, b_designated: bool) -> Self {
        drain_received_messages();
        let paths: Vec<PathBuf> = ["a", "b"]
            .iter()
            .map(|side| {
                let path = std::env::temp_dir().join(format!(
                    "mosh-org-commits-{name}-{side}-{}.redb",
                    std::process::id()
                ));
                let _ = std::fs::remove_file(&path);
                path
            })
            .collect();
        let stores = [0u8, 1].map(|i| {
            Arc::new(Persistence::open_with_dek(&paths[usize::from(i)], [40 + i; 32]).unwrap())
        });
        let _identity = crate::moss_ffi::replace_test_keystore(Some(stores[0].clone()));
        let peer_a = pin_identity(&stores[0]);
        let moss = Arc::new(MossFfiRuntime::load_default().expect("moss should load"));
        let b_key = admin_key(&peer_a, b_designated);
        let peers = [peer_a, org_signing::peer_id_hex(&b_key)];
        let leaver_key = SigningKey::from_bytes(&[201; 32]);
        let member_key = SigningKey::from_bytes(&[202; 32]);
        let mut leaver = MlsSessionCrypto::new(&org_signing::peer_id_hex(&leaver_key)).unwrap();
        let mut member = MlsSessionCrypto::new(&org_signing::peer_id_hex(&member_key)).unwrap();
        let member_peer = org_signing::peer_id_hex(&member_key);
        put_roster(&stores, 1, &peers, &leaver_key, Some(&member_peer));
        let mut runtime =
            PrivateGroupRuntime::from_shared(moss, temp_store(), Some(stores[0].clone()));
        let group_id = runtime
            .create_group(CreateGroupRequest {
                label: None,
                display_name: "Alice".to_string(),
                listen_port: 0,
                static_peer: None,
                org_pubkey: Some(org_key_hex()),
            })
            .unwrap()
            .group_id;
        // `a` adds `b`, the leaver and the member in one commit; `b` becomes
        // a second real session over the same group.
        let a = runtime.groups.get_mut(&group_id).unwrap();
        let mut b_crypto = MlsSessionCrypto::new(&peers[1]).unwrap();
        let packages = [
            b_crypto.key_package_bytes().unwrap(),
            leaver.key_package_bytes().unwrap(),
            member.key_package_bytes().unwrap(),
        ];
        let refs: Vec<&[u8]> = packages.iter().map(Vec::as_slice).collect();
        let added = a.crypto.add_members(&refs).unwrap();
        for crypto in [&mut b_crypto, &mut leaver, &mut member] {
            crypto
                .join_welcome(&added.welcome_bytes, &added.tree_bytes)
                .unwrap();
        }
        let mut record = a.to_persisted_record();
        record.device_fingerprint = peers[1].clone();
        record.participant_id = "participant-b".to_string();
        record.is_admin = false;
        let b = GroupSession::new(
            record,
            a.node.clone(),
            b_crypto,
            Some(stores[1].clone()),
            temp_store(),
            Some(b_key.clone()),
        );
        let a_key = a.org_signer.clone().unwrap();
        Self {
            runtime,
            b,
            keys: [a_key, b_key],
            peers,
            stores,
            group_id,
            leaver_key,
            leaver,
            member,
            member_peer,
            paths,
        }
    }

    /// Next roster version; `with_member: false` revokes `member`.
    fn put_roster(&self, version: u64, with_member: bool) {
        let member = with_member.then_some(self.member_peer.as_str());
        put_roster(&self.stores, version, &self.peers, &self.leaver_key, member);
    }

    fn admin(&mut self, i: usize) -> &mut GroupSession {
        match i {
            0 => self.runtime.groups.get_mut(&self.group_id).unwrap(),
            _ => &mut self.b,
        }
    }

    fn signed(&mut self, key: &SigningKey, envelope: &ControlEnvelope) -> MossReceivedMessage {
        let session = self.admin(0);
        let (channel, mesh) = (session.control_channel.clone(), session.mesh_id.clone());
        MossReceivedMessage {
            payload: org_signed_control(key, &channel, &mesh, envelope),
            channel,
        }
    }

    fn departure(&mut self) -> MossReceivedMessage {
        let envelope = ControlEnvelope::SelfRemove {
            group_id: self.group_id.clone(),
            from_fingerprint: self.leaver.fingerprint(),
            proposal_b64: encode(&self.leaver.leave_proposal_bytes().unwrap()),
            name_state_proof_b64: None,
        };
        let key = self.leaver_key.clone();
        self.signed(&key, &envelope)
    }

    fn deliver(&mut self, i: usize, frame: MossReceivedMessage) {
        // A losing branch's commit fails to merge; that is the state under test.
        let _ = self.admin(i).handle_moss_message(frame);
    }

    fn pump(&mut self, i: usize, now: u64) {
        self.admin(i).sync_roster_state(now);
    }

    fn epoch(&mut self, i: usize) -> u64 {
        self.admin(i).crypto.epoch().unwrap()
    }

    /// The commit admin `i` merged (or authored) at `epoch`, from its log.
    fn commit_at(&self, i: usize, epoch: u64) -> Option<Vec<u8>> {
        self.stores[i]
            .list_group_commits_from(&self.group_id, epoch)
            .unwrap()
            .into_iter()
            .find(|(logged, _)| *logged == epoch)
            .map(|(_, bytes)| bytes)
    }

    /// Gossip each admin's commit at `epoch` to the other admin and to the
    /// member, the member merging whichever arrives first.
    fn relay(&mut self, epoch: u64) {
        for from in 0..2 {
            let Some(bytes) = self.commit_at(from, epoch) else {
                continue;
            };
            let envelope = ControlEnvelope::Commit {
                admission_binding: None,
                group_id: self.group_id.clone(),
                from_fingerprint: org_signing::peer_id_hex(&self.keys[from]),
                commit_b64: encode(&bytes),
                roster_version: self.admin(from).own_roster_version(),
            };
            let key = self.keys[from].clone();
            let frame = self.signed(&key, &envelope);
            self.deliver(1 - from, frame);
            if self.member.epoch() == Some(epoch) {
                let _ = self.member.process_commit(&bytes);
            }
        }
    }

    fn needs_rejoin(&mut self, i: usize) -> bool {
        self.admin(i).snapshot().needs_rejoin
    }
}

impl Drop for TwoAdmins {
    fn drop(&mut self) {
        for path in &self.paths {
            let _ = std::fs::remove_file(path);
        }
    }
}

/// Every party ends on one epoch past `start` with one membership, holding
/// the same commit at `start` and none of `gone`.
fn assert_converged(org: &mut TwoAdmins, start: u64, gone: &str) {
    let landed = org.commit_at(0, start).expect("a removal commit landed");
    assert_eq!(org.commit_at(1, start), Some(landed), "one commit, not two");
    let identities = org.admin(0).crypto.member_identities();
    assert_eq!(identities, org.admin(1).crypto.member_identities());
    assert_eq!(identities, org.member.member_identities());
    assert!(!identities.iter().any(|id| id == gone));
    for i in 0..2 {
        assert_eq!(org.epoch(i), start + 1);
        assert!(!org.needs_rejoin(i));
    }
    assert_eq!(org.member.epoch(), Some(start + 1));
}

fn locked() -> std::sync::MutexGuard<'static, ()> {
    MOSS_TEST_LOCK
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
}

#[test]
fn two_online_admins_commit_a_departure_once() {
    let _guard = locked();
    for b_designated in [false, true] {
        let mut org = TwoAdmins::open("once", b_designated);
        let start = org.epoch(0);
        let leaver = org_signing::peer_id_hex(&org.leaver_key);
        let departure = org.departure();
        org.deliver(0, departure.clone());
        org.deliver(1, departure);
        org.pump(0, 0);
        org.pump(1, 0);
        org.relay(start);
        // Long past every fallback: the second admin saw the removal land.
        org.pump(0, 10 * DELAY);
        org.pump(1, 10 * DELAY);
        org.relay(start);
        assert_converged(&mut org, start, &leaver);
    }
}

#[test]
fn a_revocation_is_kicked_once_by_the_designated_admin() {
    let _guard = locked();
    for b_designated in [false, true] {
        let mut org = TwoAdmins::open("kick", b_designated);
        let start = org.epoch(0);
        let revoked = org.member_peer.clone();
        org.put_roster(2, false);
        org.pump(0, 0);
        org.pump(1, 0);
        org.relay(start);
        org.pump(0, 10 * DELAY);
        org.pump(1, 10 * DELAY);
        org.relay(start);
        let landed = org.commit_at(0, start).expect("the kick landed");
        assert_eq!(org.commit_at(1, start), Some(landed), "one kick, not two");
        for i in 0..2 {
            assert_eq!(org.epoch(i), start + 1);
            assert!(!org.admin(i).crypto.member_identities().contains(&revoked));
        }
    }
}

#[test]
fn the_next_admin_commits_a_departure_only_after_its_delay() {
    let _guard = locked();
    // `b` is designated and never hears the departure.
    let mut org = TwoAdmins::open("fallback", true);
    let start = org.epoch(0);
    let leaver = org_signing::peer_id_hex(&org.leaver_key);
    let departure = org.departure();
    org.deliver(0, departure);
    org.pump(0, 1_000);
    assert_eq!(org.epoch(0), start, "the fallback admin waits");
    org.pump(0, 1_000 + DELAY - 1);
    assert_eq!(org.epoch(0), start, "and not a millisecond less");
    org.pump(0, 1_000 + DELAY);
    assert_eq!(org.epoch(0), start + 1, "then commits the departure");
    assert!(!org.admin(0).crypto.member_identities().contains(&leaver));
}

#[test]
fn the_fallback_still_removes_the_leaver_after_an_unrelated_commit() {
    let _guard = locked();
    let mut org = TwoAdmins::open("stale", true);
    let start = org.epoch(0);
    let leaver = org_signing::peer_id_hex(&org.leaver_key);
    let departure = org.departure();
    org.deliver(0, departure);
    org.pump(0, 0);
    // `b` missed the departure but commits something else meanwhile, so the
    // leaver's proposal no longer matches the epoch.
    let mut extra = MlsSessionCrypto::new("extra").unwrap();
    let package = extra.key_package_bytes().unwrap();
    let add = org.b.crypto.add_members(&[package.as_slice()]).unwrap();
    org.b.log_commit(start, &add.commit_bytes);
    org.relay(start);
    assert_eq!(org.epoch(0), start + 1);
    org.pump(0, DELAY);
    assert_eq!(org.epoch(0), start + 2);
    assert!(!org.admin(0).crypto.member_identities().contains(&leaver));
}
