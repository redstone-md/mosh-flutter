//! Previews of texts for a woken iPhone, through both runtimes on the
//! in-memory transport, and the sealed form its notification extension
//! opens (ios/NotificationService/Previews.swift).

use super::super::state_tests::{state_of, ALICE_ID, BOB_ID};
use super::super::wake::tests::{
    after_silence, announced_pair, announcement, exchange, HANDLE, SERVICE,
};
use super::super::wake::MESSAGE_WAKE_GAP_MS;
use super::*;

/// What Alice's notification extension shows for `preview`: the chat whose
/// key opens it and the text.
fn open(alice: &PrivateDmRuntime, preview: &str) -> (String, String) {
    alice
        .preview_chats()
        .into_iter()
        .find_map(|chat| {
            let text = chat.keys.iter().find_map(|key| open_with(key, preview))?;
            Some((chat.session_id, text))
        })
        .expect("a key of Alice's opens the preview")
}

fn open_with(key: &str, preview: &str) -> Option<String> {
    let sealed = URL_SAFE_NO_PAD.decode(preview).ok()?;
    let (nonce, body) = sealed.split_at(NONCE_LEN);
    let plain = Aes256Gcm::new_from_slice(&valid_key(key)?)
        .ok()?
        .decrypt(Nonce::from_slice(nonce), body)
        .ok()?;
    let body: serde_json::Value = serde_json::from_slice(&plain).ok()?;
    Some(body["text"].as_str()?.to_string())
}

fn send(bob: &mut PrivateDmRuntime, session_id: &str, text: &str) {
    bob.send_message(session_id, text.to_string())
        .expect("a text for an absent peer queues");
}

fn previews(bob: &mut PrivateDmRuntime) -> Vec<Option<String>> {
    bob.take_wake_requests()
        .into_iter()
        .map(|request| request.preview)
        .collect()
}

fn one_preview(bob: &mut PrivateDmRuntime) -> String {
    match previews(bob).as_slice() {
        [Some(preview)] => preview.clone(),
        other => panic!("one wake with a preview, got {other:?}"),
    }
}

#[test]
fn a_woken_iphone_gets_the_new_texts_sealed_for_their_chat() {
    let (net, alice, mut bob, session_id) = announced_pair();
    net.link_both(ALICE_ID, BOB_ID, PeerTransport::None);
    send(&mut bob, &session_id, "first");
    send(&mut bob, &session_id, "second");
    let later = after_silence();
    bob.drain_inbound_at(later);

    let preview = one_preview(&mut bob);
    assert_eq!(
        open(&alice, &preview),
        (session_id.clone(), "first\nsecond".to_string())
    );

    send(&mut bob, &session_id, "third");
    bob.drain_inbound_at(later + MESSAGE_WAKE_GAP_MS);
    let preview = one_preview(&mut bob);
    assert_eq!(
        open(&alice, &preview).1,
        "third",
        "shown texts are not repeated"
    );
}

// A phone on a build before previews announces no key; it is woken as
// before, with the generic alert.
#[test]
fn a_device_without_a_preview_key_is_woken_without_a_preview() {
    let (net, mut alice, mut bob, session_id) = announced_pair();
    let old_build = alice
        .sessions
        .get_mut(&session_id)
        .expect("Alice's chat")
        .crypto
        .encrypt_json(&announcement(HANDLE, SERVICE, now_ms() + 1))
        .expect("sealed");
    bob.sessions
        .get_mut(&session_id)
        .expect("Bob's chat")
        .accept_wake_address(&old_build)
        .expect("accepted");
    net.link_both(ALICE_ID, BOB_ID, PeerTransport::None);
    send(&mut bob, &session_id, "hi");

    bob.drain_inbound_at(after_silence());

    assert_eq!(previews(&mut bob), vec![None]);
}

// The key a chat's previews are sealed with reaches the contact again
// whenever it changes.
#[test]
fn a_new_key_is_announced_to_the_contact() {
    let (net, mut alice, mut bob, session_id) = announced_pair();
    let first = alice.preview_chats()[0].keys[0].clone();
    alice
        .sessions
        .get_mut(&session_id)
        .expect("Alice's chat")
        .wake
        .own_keys = PreviewKeys::default();
    state_of(&mut alice, &session_id);
    exchange(&mut alice, &mut bob, &session_id);
    let second = alice.preview_chats()[0].keys[0].clone();
    assert_ne!(first, second);
    net.link_both(ALICE_ID, BOB_ID, PeerTransport::None);
    send(&mut bob, &session_id, "hi");

    bob.drain_inbound_at(after_silence());

    let preview = one_preview(&mut bob);
    assert_eq!(open_with(&second, &preview).as_deref(), Some("hi"));
}

#[test]
fn a_key_is_replaced_daily_and_the_one_before_still_opens() {
    let mut keys = PreviewKeys::default();
    assert!(keys.rotate(1));
    let first = keys.current().expect("a key").to_string();
    assert!(!keys.rotate(KEY_LIFETIME_MS));

    assert!(keys.rotate(1 + KEY_LIFETIME_MS));

    let second = keys.current().expect("a key").to_string();
    assert_ne!(first, second);
    assert_eq!(keys.opening(), vec![second, first]);
}

#[test]
fn a_long_text_is_cut_to_fit_one_push() {
    let key = STANDARD.encode([7u8; 32]);
    let preview = seal(&key, &["ж\"".repeat(3_000)]).expect("sealed");

    assert!(preview.len() <= PREVIEW_MAX_LEN, "{} chars", preview.len());
    let text = open_with(&key, &preview).expect("opens");
    assert!(text.starts_with("ж\"ж\""), "{text}");
    assert!(text.ends_with('…'), "{text}");
}

#[test]
fn texts_with_nothing_to_show_seal_nothing() {
    let key = STANDARD.encode([7u8; 32]);
    assert_eq!(seal(&key, &[" ".to_string(), String::new()]), None);
    assert_eq!(seal("not a key", &["hi".to_string()]), None);
}

// Pinned: ios/NotificationServiceTests/main.swift opens this same preview,
// so a change on either side fails here or there.
#[test]
fn the_sealed_form_is_what_the_notification_extension_opens() {
    let key = STANDARD.encode([7u8; 32]);
    let texts = ["Привет".to_string(), "how are you?".to_string()];

    let preview = seal_with(&key, &texts, [9u8; NONCE_LEN]).expect("sealed");

    assert_eq!(
        preview,
        "CQkJCQkJCQkJCQkJXKfw8caE41uCslTpZjobD2Zg1iK2spmoANlmx6cRIQO8kNjhn4iTe0muP9iBv9ClUiO7XJs"
    );
    assert_eq!(
        open_with(&key, &preview).as_deref(),
        Some("Привет\nhow are you?")
    );
}
