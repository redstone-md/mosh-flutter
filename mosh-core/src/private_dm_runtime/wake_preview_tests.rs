//! Previews of texts for a woken iPhone, through both runtimes on the
//! in-memory transport. The sealed forms themselves are pinned in
//! conversation/wake/preview_tests.rs.

use super::super::state_tests::{state_of, ALICE_ID, BOB_ID};
use super::super::wake::tests::{
    after_silence, announced_pair, announcement, exchange, HANDLE, SERVICE,
};
use super::*;
use crate::conversation::wake::preview::{valid_key, PreviewKeys, MESSAGE_WAKE_GAP_MS, NONCE_LEN};
use aes_gcm::aead::{Aead, KeyInit};
use aes_gcm::{Aes256Gcm, Nonce};
use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use base64::Engine;

/// What Alice's notification extension shows for `preview`: the chat whose
/// key opens it and the text.
fn open(alice: &PrivateDmRuntime, preview: &str) -> (String, String) {
    alice
        .preview_chats()
        .into_iter()
        .find_map(|chat| {
            let text = chat.keys.iter().find_map(|key| open_with(key, preview))?;
            Some((chat.chat_id, text))
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

// The service took no wake: the texts it carried are not lost.
#[test]
fn a_refused_wake_gives_its_texts_back_for_the_next() {
    let (net, alice, mut bob, session_id) = announced_pair();
    net.link_both(ALICE_ID, BOB_ID, PeerTransport::None);
    send(&mut bob, &session_id, "first");
    let later = after_silence();
    bob.drain_inbound_at(later);
    one_preview(&mut bob);

    bob.wake_refused(&session_id, HANDLE);
    send(&mut bob, &session_id, "second");
    bob.drain_inbound_at(later + MESSAGE_WAKE_GAP_MS);

    let preview = one_preview(&mut bob);
    assert_eq!(open(&alice, &preview).1, "first\nsecond");
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
        .own
        .keys = PreviewKeys::default();
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
