//! Waking members' iPhones for texts in a group, through one runtime on a
//! lone node and members at the MLS layer, as runtime_tests.rs builds them.

use super::*;
use crate::conversation::wake::preview::{open_signed, PreviewMember, MESSAGE_WAKE_GAP_MS};
use crate::moss_ffi::{drain_received_messages, MossFfiRuntime, MOSS_TEST_LOCK};
use crate::sender_auth::SenderProof;

use crate::conversation::wake::tests::{HANDLE, SERVICE};
/// Cleo's preview key for the group.
const CLEO_KEY: &str = "BwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwc=";

/// Mia's runtime holds the group; Cleo and Dane are members at the MLS
/// layer, Cleo on an iPhone.
struct Group {
    _guard: std::sync::MutexGuard<'static, ()>,
    runtime: PrivateGroupRuntime,
    group_id: String,
    cleo: MlsSessionCrypto,
    dane: MlsSessionCrypto,
}

fn cleo_identity() -> SigningKey {
    SigningKey::from_bytes(&[6; 32])
}

fn cleo_peer() -> String {
    hex::encode(cleo_identity().verifying_key().to_bytes())
}

impl Group {
    fn open(listen_port: u16) -> Self {
        let guard = MOSS_TEST_LOCK
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        drain_received_messages();
        let moss = Arc::new(MossFfiRuntime::load_default().expect("moss should load"));
        let store = AttachmentStore::new(std::env::temp_dir().join(format!(
            "mosh-group-wake-{listen_port}-{}",
            std::process::id()
        )))
        .expect("attachment store");
        let mut runtime = PrivateGroupRuntime::from_shared(moss, Arc::new(store), None);
        let group_id = runtime
            .create_group(CreateGroupRequest {
                label: Some("Hikes".to_string()),
                display_name: "Mia".to_string(),
                listen_port,
                static_peer: None,
                org_pubkey: None,
            })
            .expect("group created")
            .group_id;
        runtime.set_wake(WakeSetup::waking_through(SERVICE));
        let mut cleo = MlsSessionCrypto::new("cleo").unwrap();
        let mut dane = MlsSessionCrypto::new("dane").unwrap();
        let crypto = &mut runtime.groups.get_mut(&group_id).unwrap().crypto;
        let mut add = |member: &mut MlsSessionCrypto| {
            let added = crypto
                .add_members(&[member.key_package_bytes().unwrap().as_slice()])
                .unwrap();
            member
                .join_welcome(&added.welcome_bytes, &added.tree_bytes)
                .unwrap();
            added.commit_bytes
        };
        add(&mut cleo);
        let dane_added = add(&mut dane);
        cleo.process_commit(&dane_added).unwrap();
        Self {
            _guard: guard,
            runtime,
            group_id,
            cleo,
            dane,
        }
    }

    fn session(&mut self) -> &mut GroupSession {
        self.runtime.groups.get_mut(&self.group_id).unwrap()
    }

    /// A control frame from Cleo's iPhone, as her runtime sends one.
    fn cleo_sends(&mut self, envelope: &ControlEnvelope) {
        let frame = self.cleo_frame(envelope);
        self.deliver(frame).expect("Cleo's frame is taken");
    }

    fn deliver(&mut self, frame: Vec<u8>) -> Result<(), PrivateGroupError> {
        self.session().handle_control(frame, None)
    }

    fn cleo_frame(&self, envelope: &ControlEnvelope) -> Vec<u8> {
        let session = self.runtime.groups.get(&self.group_id).unwrap();
        let proof = SenderProof::sign(
            &cleo_identity(),
            &self.cleo,
            &OrgContext {
                org_pubkey: "",
                mesh_id: &session.mesh_id,
                channel_kind: &session.control_channel,
            },
            serde_json::to_vec(envelope).unwrap(),
        )
        .unwrap();
        serde_json::to_vec(&proof).unwrap()
    }

    fn cleo_announces(&mut self, preview_key: Option<&str>) {
        let body = WakeAnnouncement {
            wake_address: WakeAddress {
                service: SERVICE.to_string(),
                handle: HANDLE.to_string(),
            },
            issued_at_ms: now_ms(),
            preview_key: preview_key.map(str::to_string),
        };
        let envelope = ControlEnvelope::WakeAddress {
            group_id: self.group_id.clone(),
            wake_ciphertext_b64: self.cleo.encrypt_json(&body).unwrap(),
        };
        self.cleo_sends(&envelope);
        // The service turn that hears it, a moment before any text; her
        // phone sleeps from then on.
        self.runtime.pump_wake(now_ms() - 1);
    }

    fn cleo_types(&mut self) {
        let typing = self.cleo_typing();
        self.cleo_sends(&typing);
    }

    fn cleo_typing(&mut self) -> ControlEnvelope {
        let body = GroupTypingBody {
            device: "Cleo".to_string(),
            until_ms: now_ms() + 5_000,
        };
        ControlEnvelope::TypingIndicator {
            group_id: self.group_id.clone(),
            from_device: "Cleo".to_string(),
            from_fingerprint: cleo_peer(),
            typing_ciphertext_b64: self.cleo.encrypt_json(&body).unwrap(),
        }
    }

    fn send(&mut self, text: &str) {
        let group_id = self.group_id.clone();
        let sent = self.runtime.send(&group_id, text.to_string()).unwrap();
        assert_eq!(sent.delivery_status, MessageDeliveryStatus::Sent);
    }

    /// What Cleo's notification extension shows for each wake taken.
    fn shown(&mut self) -> Vec<Option<String>> {
        let group_id = self.group_id.clone();
        self.runtime
            .take_wake_requests()
            .into_iter()
            .map(|request| {
                assert_eq!(
                    (request.handle.as_str(), request.chat.as_str()),
                    (HANDLE, group_id.as_str())
                );
                let (shown, from) = open_signed(CLEO_KEY, &request.preview?, &group_id)?;
                assert_eq!(from, self.session().crypto.signer_public(), "Mia signed it");
                Some(shown)
            })
            .collect()
    }
}

/// Once Cleo has been unseen for the whole absence window.
fn away() -> u64 {
    now_ms() + ABSENT_AFTER_MS
}

#[test]
fn an_absent_member_is_woken_with_the_texts_signed_by_their_author() {
    let mut group = Group::open(42611);
    group.cleo_announces(Some(CLEO_KEY));
    group.send("first");
    group.send("second");

    group.runtime.pump_wake(away());

    assert_eq!(group.shown(), vec![Some("first\nsecond".to_string())]);
}

// Cleo's phone is awake, or was when the text arrived.
#[test]
fn a_member_heard_lately_is_not_woken_nor_for_what_they_read() {
    let mut group = Group::open(42612);
    group.cleo_announces(Some(CLEO_KEY));
    group.send("hi");
    group.cleo_types();
    let heard = now_ms();
    group.runtime.pump_wake(heard);

    group.runtime.pump_wake(heard + ABSENT_AFTER_MS / 2);
    assert!(group.shown().is_empty(), "Cleo was just heard");
    group.runtime.pump_wake(heard + ABSENT_AFTER_MS);
    assert!(group.shown().is_empty(), "Cleo got the text while awake");
}

// Anyone on the mesh can resend a frame they saw; it must not keep a
// sleeping phone looking awake.
#[test]
fn a_replayed_frame_does_not_keep_a_member_awake() {
    let mut group = Group::open(42620);
    let typing = group.cleo_typing();
    let frame = group.cleo_frame(&typing);
    group
        .deliver(frame.clone())
        .expect("the first copy is taken");
    group.cleo_announces(Some(CLEO_KEY));
    group.send("hi");

    assert!(group.deliver(frame).is_err(), "MLS opens a frame once");
    group.runtime.pump_wake(away());

    assert_eq!(group.shown(), vec![Some("hi".to_string())]);
}

#[test]
fn texts_close_together_share_a_wake_and_none_is_shown_twice() {
    let mut group = Group::open(42613);
    group.cleo_announces(Some(CLEO_KEY));
    let start = away();
    group.send("first");
    group.runtime.pump_wake(start);
    assert_eq!(group.shown(), vec![Some("first".to_string())]);

    group.send("second");
    group.send("third");
    group.runtime.pump_wake(start + MESSAGE_WAKE_GAP_MS / 2);
    assert!(group.shown().is_empty());
    group.runtime.pump_wake(start + MESSAGE_WAKE_GAP_MS);

    assert_eq!(group.shown(), vec![Some("second\nthird".to_string())]);
}

// The service took no wake: the texts it carried are not lost.
#[test]
fn a_refused_wake_gives_its_texts_back_for_the_next() {
    let mut group = Group::open(42614);
    group.cleo_announces(Some(CLEO_KEY));
    let start = away();
    group.send("first");
    group.runtime.pump_wake(start);
    group.shown();

    let group_id = group.group_id.clone();
    group.runtime.wake_refused(&group_id, HANDLE);
    group.send("second");
    group.runtime.pump_wake(start + MESSAGE_WAKE_GAP_MS);

    assert_eq!(group.shown(), vec![Some("first\nsecond".to_string())]);
}

// A phone on a build before previews announces no key; it is woken with the
// generic alert.
#[test]
fn a_member_without_a_preview_key_is_woken_without_a_preview() {
    let mut group = Group::open(42615);
    group.cleo_announces(None);
    group.send("hi");

    group.runtime.pump_wake(away());

    assert_eq!(group.shown(), vec![None]);
}

#[test]
fn a_forgotten_handle_wakes_nothing() {
    let mut group = Group::open(42617);
    group.cleo_announces(Some(CLEO_KEY));
    group.send("hi");

    group.runtime.forget_wake_handle(HANDLE);
    group.runtime.pump_wake(away());

    assert!(group.shown().is_empty());
}

// A member names its service; only the build's own is asked.
#[test]
fn an_address_on_another_service_wakes_nothing() {
    let mut group = Group::open(42618);
    group
        .runtime
        .set_wake(WakeSetup::waking_through("https://other.example"));
    group.cleo_announces(Some(CLEO_KEY));
    group.send("hi");

    group.runtime.pump_wake(away());

    assert!(group.shown().is_empty());
}

/// Whether one service turn at `at` publishes this phone's announcement.
fn announces(group: &mut Group, at: u64, on_screen: bool) -> bool {
    let published = Arc::new(std::sync::atomic::AtomicBool::new(false));
    let flag = published.clone();
    let _next = crate::moss_ffi::after_next_test_publish(move || {
        flag.store(true, std::sync::atomic::Ordering::SeqCst)
    });
    group.runtime.pump_wake_on(at, on_screen);
    published.load(std::sync::atomic::Ordering::SeqCst)
}

fn announcing(group: &mut Group, handle: &str) {
    group.runtime.set_wake(WakeSetup::announcing(WakeAddress {
        service: SERVICE.to_string(),
        handle: handle.to_string(),
    }));
}

// Groups have no keepalive: the announcement, repeated while Mosh is on
// screen, is how members know the phone is awake.
#[test]
fn a_phone_repeats_its_announcement_while_mosh_is_on_screen() {
    let mut group = Group::open(42619);
    announcing(&mut group, HANDLE);
    let start = now_ms();

    assert!(announces(&mut group, start, true), "announced at once");
    assert!(!announces(&mut group, start + PRESENT_EVERY_MS - 1, true));
    assert!(
        announces(&mut group, start + PRESENT_EVERY_MS, true),
        "repeated"
    );
}

// An Android phone in the background is woken through its push service
// instead of sending a frame per group every few seconds all day.
#[test]
fn a_phone_off_screen_announces_only_what_changed() {
    let mut group = Group::open(42620);
    announcing(&mut group, HANDLE);
    let start = now_ms();

    assert!(announces(&mut group, start, false), "announced at once");
    assert!(
        !announces(&mut group, start + 10 * PRESENT_EVERY_MS, false),
        "not repeated"
    );
    announcing(&mut group, &"b".repeat(HANDLE.len()));
    assert!(
        announces(&mut group, start + 11 * PRESENT_EVERY_MS, false),
        "a new address goes at once"
    );
}

// Every member knows the key; one who left must not read what comes after,
// even when they left while Mosh was closed.
#[test]
fn the_phones_key_names_the_members_and_is_replaced_when_one_leaves() {
    let mut group = Group::open(42616);
    group.runtime.set_wake(WakeSetup::announcing(WakeAddress {
        service: SERVICE.to_string(),
        handle: HANDLE.to_string(),
    }));
    group.runtime.pump_wake(now_ms());
    let chats = group.runtime.preview_chats();
    let [chat] = chats.as_slice() else {
        panic!("one group chat, got {chats:?}");
    };
    let member = |crypto: &MlsSessionCrypto, name: &str| PreviewMember {
        key: STANDARD.encode(crypto.signer_public()),
        name: name.to_string(),
    };
    let mut expected = vec![member(&group.cleo, "cleo"), member(&group.dane, "dane")];
    expected.sort();
    assert_eq!(
        (chat.name.as_str(), chat.members.clone()),
        ("Hikes", Some(expected))
    );
    let first = chat.keys.clone();

    let record = group.session().wake.record();
    group
        .session()
        .crypto
        .remove_members_by_identity("dane")
        .unwrap();
    group.session().wake = GroupWakeBook::restore(record);
    group.runtime.pump_wake(now_ms());

    let chat = group.runtime.preview_chats().remove(0);
    assert_eq!(chat.keys.len(), 2);
    assert_eq!(chat.keys[1..], first[..], "the old key still opens");
    assert_eq!(chat.members, Some(vec![member(&group.cleo, "cleo")]));
}
