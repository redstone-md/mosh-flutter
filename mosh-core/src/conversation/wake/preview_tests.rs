//! The sealed forms the iPhone's notification extension opens
//! (ios/NotificationService/Previews.swift), and the keys and texts behind
//! them.

use super::*;
use ed25519_dalek::{Signer, SigningKey};

fn open_with(key: &str, preview: &str) -> Option<serde_json::Value> {
    let sealed = URL_SAFE_NO_PAD.decode(preview).ok()?;
    let (nonce, body) = sealed.split_at(NONCE_LEN);
    let plain = Aes256Gcm::new_from_slice(&valid_key(key)?)
        .ok()?
        .decrypt(Nonce::from_slice(nonce), body)
        .ok()?;
    serde_json::from_slice(&plain).ok()
}

fn text_of(key: &str, preview: &str) -> Option<String> {
    Some(open_with(key, preview)?["text"].as_str()?.to_string())
}

fn key() -> String {
    STANDARD.encode([7u8; 32])
}

fn member() -> SigningKey {
    SigningKey::from_bytes(&[5u8; 32])
}

fn sign(bytes: &[u8]) -> Option<Vec<u8>> {
    Some(member().sign(bytes).to_bytes().to_vec())
}

fn author() -> PreviewAuthor<'static> {
    PreviewAuthor {
        chat: "group-1",
        key: member().verifying_key().to_bytes().to_vec(),
        sign: &sign,
    }
}

/// The text of a group preview whose signature holds for `chat`.
fn signed_text(preview: &str, chat: &str) -> Option<String> {
    Some(open_signed(&key(), preview, chat)?.0)
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
    for author in [None, Some(author())] {
        let preview = seal(&key(), &["ж\"".repeat(3_000)], author.as_ref()).expect("sealed");

        assert!(preview.len() <= PREVIEW_MAX_LEN, "{} chars", preview.len());
        let text = text_of(&key(), &preview).expect("opens");
        assert!(text.starts_with("ж\"ж\""), "{text}");
        assert!(text.ends_with('…'), "{text}");
    }
}

#[test]
fn texts_with_nothing_to_show_seal_nothing() {
    assert_eq!(seal(&key(), &[" ".to_string(), String::new()], None), None);
    assert_eq!(seal("not a key", &["hi".to_string()], None), None);
}

// The signature is the cut text's, and only for the chat it was made in.
#[test]
fn a_group_preview_is_signed_by_its_author_for_its_group() {
    let preview = seal(&key(), &["x".repeat(4_000)], Some(&author())).expect("sealed");

    let shown = signed_text(&preview, "group-1").expect("the signature holds");
    assert!(shown.starts_with("xxx") && shown.ends_with('…'), "{shown}");
    assert_eq!(signed_text(&preview, "group-2"), None);
}

// Pinned: ios/NotificationServiceTests/main.swift opens these same
// previews, so a change on either side fails here or there.
#[test]
fn the_sealed_forms_are_what_the_notification_extension_opens() {
    let texts = ["Привет".to_string(), "how are you?".to_string()];

    let direct = seal_with(&key(), &texts, None, [9u8; NONCE_LEN]).expect("sealed");
    let group = seal_with(&key(), &texts, Some(&author()), [9u8; NONCE_LEN]).expect("sealed");

    assert_eq!(
        direct,
        "CQkJCQkJCQkJCQkJXKfw8caE41uCslTpZjobD2Zg1iK2spmoANlmx6cRIQO8kNjhn4iTe0muP9iBv9ClUiO7XJs"
    );
    assert_eq!(
        group,
        "CQkJCQkJCQkJCQkJXKfi5tGd41uCAKVXhdnwsqPEV9xmoYGUKfkfiaNNTkKiiZ-ZlwJhcgaG9WB8TrqWLQOx0S-2gm\
         wWBma1bDQ_uhQYwzu7ZJbO76GLJPCRvLpJ3YFiyXSexA_sD9wd5m4YSEmi1J9y5zp7jN4xHIwPJs9fXD7S4Im7G_m8\
         mnsxD5H6_08hHsknjiw3iZUdkHHgVbsiKs9u9mB7UcjnyJ41s8v2ON60Oao-ZaIVx0b_HXvM2cCzRLo7f_nExFKwBi\
         2FohBd6f5T9nelWQC4"
    );
    assert_eq!(
        text_of(&key(), &direct).as_deref(),
        Some("Привет\nhow are you?")
    );
    assert_eq!(
        signed_text(&group, "group-1").as_deref(),
        Some("Привет\nhow are you?")
    );
}
