use super::{
    authority::DeletionAuthority,
    protocol::{DeleteAck, DeleteRequest, DeletionMessage},
    shared::{self, DeletionActor},
    *,
};
use crate::conversation::{message_log::MessageLog, test_message::TestMessage, transfer::Transfer};
use crate::{
    attachment_store::AttachmentStore,
    persistence::{Persistence, GROUP_HISTORY},
    test_temp_directory::TempDirectory,
};
use ed25519_dalek::{Signer, SigningKey};
use std::{collections::HashMap, sync::Arc};

const ROOM: &str = "group:club";
struct Fixture {
    book: DeletionBook,
    log: MessageLog<TestMessage>,
    attempts: HashMap<String, crate::outbound_delivery::OutboundAttemptRecord>,
    transfer: Transfer,
    _directory: TempDirectory,
}
impl Fixture {
    fn new(author: &SigningKey) -> Self {
        let directory = TempDirectory::new("deletion-policy");
        let store = Arc::new(
            Persistence::open_with_dek(&directory.path().join("history"), [41; 32]).unwrap(),
        );
        let book = DeletionBook::new(ROOM.into(), GROUP_HISTORY, Some(store));
        let mut log = MessageLog::default();
        let mut message = TestMessage::new("same display name", "content")
            .with_id("message")
            .at(1);
        message.metadata = Some(MessageMetadata {
            origin: Some(MessageOrigin::sign(ROOM, "message", b"content", author, None).unwrap()),
            ..Default::default()
        });
        log.push(message);
        let transfer = Transfer::new(Arc::new(AttachmentStore::new(directory.path()).unwrap()));
        Self {
            book,
            log,
            attempts: HashMap::new(),
            transfer,
            _directory: directory,
        }
    }
    fn context(&mut self) -> DeletionContext<'_, TestMessage> {
        DeletionContext {
            book: &mut self.book,
            log: &mut self.log,
            attempts: &mut self.attempts,
            transfer: &mut self.transfer,
        }
    }
    fn request(&self, actor: &SigningKey, moderated: bool) -> DeletionRecord {
        let mut request = DeleteRequest {
            operation: crate::message_id::occurrence_id("delete"),
            target: self.log[0]
                .metadata
                .as_ref()
                .unwrap()
                .origin
                .clone()
                .unwrap(),
            actor: key(actor),
            actor_name: "Admin".into(),
            moderated,
            epoch: 0,
            signature: String::new(),
            ownership: Some(super::ownership::test_proof(actor)),
        };
        request.signature = sign(actor, &request.input().unwrap());
        shared::canonical(request, DeletionStatus::Pending, None).unwrap()
    }
}
fn key(key: &SigningKey) -> String {
    hex::encode(key.verifying_key().as_bytes())
}
fn sign(key: &SigningKey, bytes: &[u8]) -> String {
    hex::encode(key.sign(bytes).to_bytes())
}
fn authority(local: &SigningKey, other: &SigningKey) -> DeletionAuthority {
    DeletionAuthority {
        local: DeletionActor {
            key: key(local),
            name: "Admin".into(),
            epoch: 0,
            ownership: Some(super::ownership::test_proof(local)),
        },
        members: [key(local), key(other)].into(),
        admins: [key(local)].into(),
        accepted: Default::default(),
        accounts: Default::default(),
        own: Default::default(),
        public_channel: false,
    }
}

#[test]
fn forged_or_wrong_conversation_requests_never_change_history() {
    let (author, receiver) = (
        SigningKey::from_bytes(&[31; 32]),
        SigningKey::from_bytes(&[32; 32]),
    );
    let mut f = Fixture::new(&author);
    let policy = authority(&receiver, &author);
    for mutate in 0..2 {
        let mut record = f.request(&author, false);
        if mutate == 0 {
            record.request.as_mut().unwrap().signature = "0".repeat(128);
        } else {
            record.context = "group:other".into();
        }
        assert!(f
            .context()
            .receive(
                DeletionMessage::State {
                    records: vec![record],
                    next: None
                },
                &key(&author),
                &policy,
                |b| Ok(sign(&receiver, b))
            )
            .is_err());
        assert_eq!(f.log[0].body, "content");
        assert!(f.book.records.is_empty());
    }
}

#[test]
fn verified_role_loss_rejects_pending_moderation_and_keeps_personal_erasure() {
    let (admin, author) = (
        SigningKey::from_bytes(&[31; 32]),
        SigningKey::from_bytes(&[32; 32]),
    );
    let mut f = Fixture::new(&author);
    let mut policy = authority(&admin, &author);
    shared::admit(
        &mut f.context(),
        &["message".into()],
        &policy.local,
        |_| Some(true),
        |b| Ok(sign(&admin, b)),
    )
    .unwrap();
    policy.admins.clear();
    f.context().reconcile(&policy, false).unwrap();
    assert!(f.log.visible().is_empty());
    assert_eq!(f.book.summary().unwrap().rejected_count, 1);
    assert_eq!(f.book.summary().unwrap().pending_count, 0);
    f.book.reload().unwrap();
    assert!(
        matches!(shared::page(&f.book, None, &policy), DeletionMessage::State { records, .. } if records.is_empty())
    );
}

#[test]
fn a_refused_history_save_neither_erases_nor_acknowledges_a_request() {
    let (author, reader) = (
        SigningKey::from_bytes(&[31; 32]),
        SigningKey::from_bytes(&[32; 32]),
    );
    let mut f = Fixture::new(&author);
    let fault = f
        .book
        .store
        .as_ref()
        .unwrap()
        .refuse_message_writes(GROUP_HISTORY);
    let record = f.request(&author, false);
    let policy = authority(&reader, &author);
    assert!(f
        .context()
        .receive(
            DeletionMessage::State {
                records: vec![record.clone()],
                next: None
            },
            &key(&author),
            &policy,
            |b| Ok(sign(&reader, b))
        )
        .is_err());
    assert_eq!(f.log[0].body, "content");
    assert!(f.book.records.is_empty());
    drop(fault);
    let replies = f
        .context()
        .receive(
            DeletionMessage::State {
                records: vec![record],
                next: None,
            },
            &key(&author),
            &policy,
            |b| Ok(sign(&reader, b)),
        )
        .unwrap();
    assert!(matches!(&replies[..], [DeletionMessage::Ack { .. }]));
    assert_eq!(f.log[0].body, "");
}

#[test]
fn confirmed_moderation_survives_admin_handoff_and_stale_pending_replay() {
    let (old, current) = (
        SigningKey::from_bytes(&[31; 32]),
        SigningKey::from_bytes(&[32; 32]),
    );
    let mut f = Fixture::new(&current);
    let pending = f.request(&old, true);
    let request = pending.request.as_ref().unwrap();
    let mut ack = DeleteAck {
        request_digest: request.digest().unwrap(),
        actor: key(&current),
        signature: String::new(),
        ownership: Some(super::ownership::test_proof(&current)),
    };
    ack.signature = sign(&current, &ack.input().unwrap());
    let confirmed =
        shared::canonical(request.clone(), DeletionStatus::Confirmed, Some(ack)).unwrap();
    let mut policy = authority(&current, &old);
    policy.members.remove(&key(&old));
    f.context()
        .receive(
            DeletionMessage::State {
                records: vec![confirmed.clone()],
                next: None,
            },
            &key(&current),
            &policy,
            |b| Ok(sign(&current, b)),
        )
        .unwrap();
    assert_eq!(
        f.log[0]
            .metadata
            .as_ref()
            .unwrap()
            .deletion
            .as_ref()
            .unwrap()
            .status,
        DeletionStatus::Confirmed
    );
    assert_eq!(confirmed.merged(&pending), confirmed);
}

fn confirmed(record: &DeletionRecord, signer: &SigningKey) -> DeletionRecord {
    let request = record.request.as_ref().unwrap();
    let mut ack = DeleteAck {
        request_digest: request.digest().unwrap(),
        actor: key(signer),
        signature: String::new(),
        ownership: Some(super::ownership::test_proof(signer)),
    };
    ack.signature = sign(signer, &ack.input().unwrap());
    shared::canonical(request.clone(), DeletionStatus::Confirmed, Some(ack)).unwrap()
}

#[test]
fn a_former_admin_and_a_colluding_member_cannot_create_a_confirmed_moderation() {
    let old = SigningKey::from_bytes(&[31; 32]);
    let reader = SigningKey::from_bytes(&[32; 32]);
    let member = SigningKey::from_bytes(&[33; 32]);
    let mut f = Fixture::new(&reader);
    let record = confirmed(&f.request(&old, true), &member);
    let mut policy = authority(&reader, &old);
    policy.admins.clear();
    policy.members.insert(key(&member));
    assert!(f
        .context()
        .receive(
            DeletionMessage::State {
                records: vec![record],
                next: None
            },
            &key(&member),
            &policy,
            |b| Ok(sign(&reader, b))
        )
        .is_err());
    assert_eq!(f.log[0].body, "content");
    assert!(f.book.records.is_empty());
}

#[test]
fn saved_acceptance_survives_receipt_signer_departure_and_restart() {
    let author = SigningKey::from_bytes(&[31; 32]);
    let reader = SigningKey::from_bytes(&[32; 32]);
    let receipt = SigningKey::from_bytes(&[33; 32]);
    let mut f = Fixture::new(&author);
    let record = confirmed(&f.request(&author, false), &receipt);
    let mut policy = authority(&reader, &author);
    policy.admins.clear();
    policy.members.insert(key(&receipt));
    f.context()
        .receive(
            DeletionMessage::State {
                records: vec![record.clone()],
                next: None,
            },
            &key(&author),
            &policy,
            |b| Ok(sign(&reader, b)),
        )
        .unwrap();
    f.book = DeletionBook::new(ROOM.into(), GROUP_HISTORY, f.book.store.clone());
    f.book.reload().unwrap();
    policy.accepted = f.book.accepted.clone();
    policy.members.remove(&key(&receipt));
    policy.members.remove(&key(&author));
    assert!(policy.validate(&record, &key(&reader)).is_ok());
    assert!(
        matches!(shared::page(&f.book, None, &policy), DeletionMessage::State { records, .. } if records == vec![record])
    );
    assert_eq!(f.log[0].body, "");
}

#[test]
fn a_fresh_ack_cannot_confirm_an_unaccepted_request_after_admin_demotion() {
    let old = SigningKey::from_bytes(&[31; 32]);
    let reader = SigningKey::from_bytes(&[32; 32]);
    let mut f = Fixture::new(&reader);
    let mut policy = authority(&old, &reader);
    shared::admit(
        &mut f.context(),
        &["message".into()],
        &policy.local,
        |_| Some(true),
        |b| Ok(sign(&old, b)),
    )
    .unwrap();
    let record = f.book.records.values().next().unwrap().clone();
    let accepted = confirmed(&record, &reader);
    policy.admins.clear();
    assert!(f
        .context()
        .receive(
            DeletionMessage::Ack {
                key: record.key,
                acknowledgement: accepted.acknowledgement.unwrap()
            },
            &key(&reader),
            &policy,
            |b| Ok(sign(&old, b))
        )
        .is_err());
    assert!(f.book.accepted.is_empty());
    f.context().reconcile(&policy, false).unwrap();
    assert_eq!(f.book.summary().unwrap().rejected_count, 1);
}

#[path = "policy_tests/recovery.rs"]
mod recovery;

#[path = "policy_tests/readiness.rs"]
mod readiness;

#[path = "policy_tests/revocation.rs"]
mod revocation;
