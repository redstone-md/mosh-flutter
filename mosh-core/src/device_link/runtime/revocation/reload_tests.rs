use super::*;
use crate::device_link::wire::{self, LinkMessage};
use crate::moss_ffi::{set_moss_keystore, MossFfiRuntime};
use ed25519_dalek::SigningKey;

#[test]
fn another_identity_owner_can_remove_an_authorizer_during_linking() {
    for phase in ["ShowingQr", "AwaitingApproval", "Delivering"] {
        let result = std::process::Command::new(std::env::current_exe().unwrap())
            .args([
                "--exact",
                "device_link::runtime::revocation::reload_tests::removed_authorizer_process",
                "--ignored",
                "--nocapture",
            ])
            .env("MOSH_REMOVED_AUTHORIZER_PHASE", phase)
            .status()
            .unwrap();
        assert!(
            result.success(),
            "removal must end authorization in {phase}"
        );
    }
}

#[test]
#[ignore = "Real Moss worker for deterministic shared-store removal ordering."]
fn removed_authorizer_process() {
    let dir = std::env::temp_dir().join(format!("mosh-link-removal-{}", rand::random::<u64>()));
    std::fs::create_dir_all(&dir).unwrap();
    let store =
        Arc::new(Persistence::open_with_dek(&dir.join("local.redb"), rand::random()).unwrap());
    set_moss_keystore(store.clone());
    let moss = Arc::new(MossFfiRuntime::load_default().unwrap());
    moss.install_keystore().unwrap();
    let shared = SharedMossNode::new(moss);
    let mut runtime = DeviceLinkRuntime::open(shared, store.clone()).unwrap();
    let own = runtime.identity.device().clone();
    let root_key = SigningKey::generate(&mut rand::rngs::OsRng);
    // The fixture represents a delegated installation already linked to the root.
    let base = DeviceRoster::genesis(descriptor(&root_key), &root_key)
        .unwrap()
        .extend(own.clone(), &root_key)
        .unwrap();
    let mut record = runtime.identity.record.clone();
    record.roster = base;
    runtime.identity.update(record).unwrap();
    advance_authorization(&mut runtime);
    // A separate identity owner uses the same public CAS boundary as DM adoption.
    let mut other_owner = DeviceIdentity::open(store, &own.moss_peer_id).unwrap();
    let removed = other_owner
        .roster()
        .revoke(&own.device_id, &root_key)
        .unwrap();
    other_owner.adopt_roster(removed).unwrap();
    let snapshot = runtime.snapshot().unwrap();
    assert!(snapshot.revoked);
    assert_eq!(snapshot.phase, DeviceLinkPhase::Idle);
    assert_eq!(snapshot.role, None);
    assert!(snapshot.qr_uri.is_none());
    assert!(snapshot.can_join);
    assert!(snapshot.confirmation_code.is_none());
    drop(runtime);
    std::fs::remove_dir_all(dir).unwrap();
}

fn advance_authorization(runtime: &mut DeviceLinkRuntime) {
    let expected = std::env::var("MOSH_REMOVED_AUTHORIZER_PHASE").unwrap();
    let snapshot = runtime.begin_link().unwrap();
    if expected == "ShowingQr" {
        return;
    }
    let qr = PairingQr::parse(&snapshot.qr_uri.unwrap(), now()).unwrap();
    let joining_key = SigningKey::generate(&mut rand::rngs::OsRng);
    let joining = descriptor(&joining_key);
    let packet = wire::seal(
        &qr,
        &joining_key,
        LinkMessage::Join {
            device: joining.clone(),
        },
    )
    .unwrap();
    runtime.receive(&packet).unwrap();
    let hash = runtime.identity.roster().digest().unwrap();
    let ready = wire::seal(
        &qr,
        &joining_key,
        LinkMessage::Ready {
            offer_hash: hash.clone(),
        },
    )
    .unwrap();
    runtime.receive(&ready).unwrap();
    assert_eq!(runtime.phase, DeviceLinkPhase::AwaitingApproval);
    if expected == "AwaitingApproval" {
        return;
    }
    let code = qr.code(&hash, runtime.identity.device(), &joining).unwrap();
    assert_eq!(
        runtime.approve(code).unwrap().phase,
        DeviceLinkPhase::Delivering
    );
}

fn descriptor(key: &SigningKey) -> DeviceDescriptor {
    let transport = SigningKey::generate(&mut rand::rngs::OsRng);
    DeviceDescriptor::new(key, &hex::encode(transport.verifying_key().as_bytes()))
}
