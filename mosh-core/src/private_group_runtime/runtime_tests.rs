//! The group runtime tests: state machine, org authority, resync.
use super::*;
use crate::moss_ffi::{
    drain_received_messages, fail_next_test_publish, no_peers_next_test_publish, MossFfiRuntime,
    MOSS_TEST_LOCK,
};
use crate::persistence::Persistence;
use std::path::PathBuf;

fn temp_store() -> Arc<AttachmentStore> {
    let mut path = std::env::temp_dir();
    path.push(format!(
        "mosh-group-attachments-{}-{}",
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos()
    ));
    Arc::new(AttachmentStore::new(&path).expect("attachment store should init"))
}

fn org_key() -> SigningKey {
    SigningKey::from_bytes(&[61u8; 32])
}

fn org_key_hex() -> String {
    hex::encode(org_key().verifying_key().to_bytes())
}

fn identity_blob(seed: [u8; 32]) -> Vec<u8> {
    let key = SigningKey::from_bytes(&seed);
    let mut blob = vec![1u8];
    blob.extend_from_slice(&seed);
    blob.extend_from_slice(&key.verifying_key().to_bytes());
    blob.extend_from_slice(&[0u8; 64]);
    blob
}

fn put_signed_roster(p: &Persistence, members: &[(&str, &str)]) {
    let mut doc = serde_json::json!({
        "org_pubkey": org_key_hex(),
        "org_name": "acme",
        "version": 1,
        "members": members
            .iter()
            .map(|(id, role)| serde_json::json!({
                "moss_peer_id": id, "name": "m", "role": role,
            }))
            .collect::<Vec<_>>(),
    });
    let bytes = org_roster::sign_roster(&mut doc, &org_key()).unwrap();
    p.put_org_roster(&org_key_hex(), &bytes).unwrap();
}

fn org_signed_control(
    sender: &SigningKey,
    session_channel: &str,
    mesh_id: &str,
    envelope: &ControlEnvelope,
) -> Vec<u8> {
    let org = org_key_hex();
    let ctx = OrgContext {
        org_pubkey: &org,
        mesh_id,
        channel_kind: session_channel,
    };
    let env = org_envelope::sign(sender, &ctx, &serde_json::to_vec(envelope).unwrap());
    serde_json::to_vec(&env).unwrap()
}

/// A three-party plain group whose runtime session is an ordinary member.
/// The admin (`dane`) and the third member (`cleo`) live at the crypto
/// layer, so a real admin departure can be replayed against a real
/// session and the member's view inspected.
struct MemberView {
    runtime: PrivateGroupRuntime,
    group_id: String,
    control_channel: String,
    dane: MlsSessionCrypto,
    cleo: MlsSessionCrypto,
}

impl MemberView {
    fn open(listen_port: u16) -> Self {
        let moss = Arc::new(MossFfiRuntime::load_default().expect("moss should load"));
        let mut runtime = PrivateGroupRuntime::from_shared(moss, temp_store(), None);
        let created = runtime
            .create_group(CreateGroupRequest {
                label: None,
                display_name: "Mia".to_string(),
                listen_port,
                static_peer: None,
                org_pubkey: None,
            })
            .expect("group should be created");

        let mut dane = MlsSessionCrypto::new("dane").unwrap();
        let mut cleo = MlsSessionCrypto::new("cleo").unwrap();
        let control_channel = {
            let session = runtime.groups.get_mut(&created.group_id).unwrap();
            let kp_dane = dane.key_package_bytes().unwrap();
            let add_dane = session.crypto.add_members(&[kp_dane.as_slice()]).unwrap();
            dane.join_welcome(&add_dane.welcome_bytes, &add_dane.tree_bytes)
                .unwrap();
            let kp_cleo = cleo.key_package_bytes().unwrap();
            let add_cleo = session.crypto.add_members(&[kp_cleo.as_slice()]).unwrap();
            cleo.join_welcome(&add_cleo.welcome_bytes, &add_cleo.tree_bytes)
                .unwrap();
            dane.process_commit(&add_cleo.commit_bytes).unwrap();
            // The session is a plain member and `dane` is the admin it
            // points at — the state every non-creator member is in.
            session.is_admin = false;
            session.current_admin_fingerprint = dane.fingerprint();
            session.control_channel.clone()
        };
        Self {
            runtime,
            group_id: created.group_id,
            control_channel,
            dane,
            cleo,
        }
    }

    fn deliver(&mut self, envelope: &ControlEnvelope) {
        let payload = serde_json::to_vec(envelope).unwrap();
        let session = self.runtime.groups.get_mut(&self.group_id).unwrap();
        session
            .handle_moss_message(MossReceivedMessage {
                channel: self.control_channel.clone(),
                payload,
            })
            .expect("control frame should be handled");
    }

    fn session(&self) -> &GroupSession {
        self.runtime.groups.get(&self.group_id).unwrap()
    }

    /// A departure frame: a self-removal proposal, the only way MLS lets a
    /// member retire its own leaf.
    fn departure_of(leaver: &mut MlsSessionCrypto, group_id: &str) -> ControlEnvelope {
        ControlEnvelope::SelfRemove {
            group_id: group_id.to_string(),
            from_fingerprint: leaver.fingerprint(),
            proposal_b64: encode(&leaver.leave_proposal_bytes().unwrap()),
        }
    }

    /// `cleo` commits the admin's departure, as the successor would.
    /// Returns the commit that drops the admin's leaf.
    fn cleo_commits_departure(&mut self) -> Vec<u8> {
        let proposal = self.dane.leave_proposal_bytes().unwrap();
        self.cleo.commit_departure(&proposal).unwrap()
    }

    /// Cleo's typing hint, encrypted under cleo's MLS state — exactly
    /// what a member's runtime mints — delivered to us on the control
    /// channel.
    fn deliver_cleo_typing(&mut self) {
        let body = GroupTypingBody {
            device: "cleo".to_string(),
            until_ms: TypingGate::deadline(now_ms()),
        };
        let ciphertext = self
            .cleo
            .encrypt(&serde_json::to_vec(&body).unwrap())
            .unwrap();
        let envelope = ControlEnvelope::TypingIndicator {
            group_id: self.group_id.clone(),
            from_device: "cleo".to_string(),
            from_fingerprint: hex::encode(
                SigningKey::from_bytes(&[6; 32]).verifying_key().to_bytes(),
            ),
            typing_ciphertext_b64: encode(&ciphertext),
        };
        let payload = self.cleo_application(&envelope, &self.control_channel);
        self.runtime
            .groups
            .get_mut(&self.group_id)
            .unwrap()
            .handle_control(payload, None)
            .unwrap();
    }

    fn cleo_application<T: Serialize>(&self, envelope: &T, channel: &str) -> Vec<u8> {
        let proof = crate::sender_auth::SenderProof::sign(
            &SigningKey::from_bytes(&[6; 32]),
            &self.cleo,
            &OrgContext {
                org_pubkey: "",
                mesh_id: &self.session().mesh_id,
                channel_kind: channel,
            },
            serde_json::to_vec(envelope).unwrap(),
        )
        .unwrap();
        serde_json::to_vec(&proof).unwrap()
    }

    fn typing_member_of(&self) -> Option<TypingMember> {
        self.session().typing_members_live().first().cloned()
    }
}

// ---- rehydrate snapshot hygiene ---------------------------------------
//
// A group record whose MLS snapshot is missing can never rebuild. A
// joiner placeholder (not joined, empty MLS group id) is dead data and
// gets deleted at rehydrate; a real record missing its snapshot stays on
// disk (its history rows remain recoverable) and is skipped with a
// distinct warning.

/// A per-test redb path, so rehydrate tests never share one store.
fn rehydrate_db(name: &str) -> PathBuf {
    let mut path = std::env::temp_dir();
    path.push(format!(
        "mosh-group-rehydrate-{name}-{}.redb",
        std::process::id()
    ));
    let _ = std::fs::remove_file(&path);
    path
}

/// The group records off disk, through the kind's own history reader.
fn persisted_group_rows(persistence: &Persistence) -> Vec<PersistedGroupSession> {
    crate::conversation::history::History::new(GROUP_HISTORY).stored_conversations(persistence)
}

#[path = "runtime_tests/sequencing.rs"]
mod sequencing;

#[path = "runtime_tests/roster_authority.rs"]
mod roster_authority;

#[path = "runtime_tests/recovery_authority.rs"]
mod recovery_authority;

#[path = "runtime_tests/lifecycle.rs"]
mod lifecycle;

#[path = "runtime_tests/restore.rs"]
mod restore;

#[path = "runtime_tests/delivery.rs"]
mod delivery;

#[path = "runtime_tests/typing.rs"]
mod typing;

#[path = "runtime_tests/authentication.rs"]
mod authentication;

#[path = "runtime_tests/authentication_org.rs"]
mod authentication_org;
