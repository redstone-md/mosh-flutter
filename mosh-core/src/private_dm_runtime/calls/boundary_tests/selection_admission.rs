use super::*;

const NATIVE: bool = cfg!(any(
    target_os = "windows",
    target_os = "macos",
    target_os = "linux"
));

fn offer(f: &mut Fixture, id: &str, native: bool) {
    let device = f.contact.device().device_id.clone();
    let peer = f.contact.device().moss_peer_id.clone();
    let control = remote_control(
        f,
        &device,
        &peer,
        id,
        1,
        json!({"Offer": {"key_b64": crate::private_dm_runtime::random_b64(32),
            "nonce_prefix_b64": crate::private_dm_runtime::random_b64(4), "native": native}}),
    );
    apply(f, control);
}

fn select(f: &mut Fixture, id: &str, device: &str, receiver: &str, sequence: u64) {
    let peer = if device == f.contact.device().device_id {
        f.contact.device().moss_peer_id.clone()
    } else {
        f.outsider.device().moss_peer_id.clone()
    };
    let control = remote_control(
        f,
        device,
        &peer,
        id,
        sequence,
        json!({"Selected": {"receiver": receiver}}),
    );
    apply(f, control);
}

fn sibling(f: &Fixture) -> String {
    hex::encode(f.peers[&f.source.device().device_id].signer_public())
}

fn unsolicited_selection_cannot_reserve_a_device(f: &mut Fixture) {
    let device = f.contact.device().device_id.clone();
    let own = hex::encode(
        f.runtime
            .session_ref(&f.session)
            .unwrap()
            .crypto
            .signer_public(),
    );
    for (sequence, receiver) in [(1, own), (2, sibling(f))] {
        select(f, "invented-call", &device, &receiver, sequence);
        let view = f.snapshot();
        assert!(view.pending_call.is_none() && view.active_call.is_none());
        assert_eq!(
            view.call_availability, None,
            "unsolicited selection reserved the user"
        );
        assert!(f
            .runtime
            .occupied_calls(crate::private_dm_runtime::now_ms())
            .is_empty());
    }
}

fn dismissed_offer_remembers_only_its_original_caller(f: &mut Fixture) {
    admit_second_contact(f);
    offer(f, "known-call", NATIVE);
    f.runtime
        .session_mut(&f.session)
        .unwrap()
        .finish_call("missed", 0);
    let receiver = sibling(f);
    let wrong = f.outsider.device().device_id.clone();
    select(f, "known-call", &wrong, &receiver, 1);
    assert_eq!(
        f.snapshot().call_availability,
        None,
        "another leaf claimed the offer"
    );
    let caller = f.contact.device().device_id.clone();
    select(f, "another-call", &caller, &receiver, 2);
    assert_eq!(
        f.snapshot().call_availability,
        None,
        "caller invented a different call"
    );
    select(f, "known-call", &caller, &receiver, 3);
    assert_eq!(f.snapshot().call_availability, Some(CallAvailability::Busy));
}

fn selected_sibling_heartbeats_keep_the_admitted_call_busy(f: &mut Fixture) {
    offer(f, "known-call", NATIVE);
    let caller = f.contact.device().device_id.clone();
    let receiver = sibling(f);
    select(f, "known-call", &caller, &receiver, 2);
    assert!(f.snapshot().pending_call.is_none());
    assert_eq!(f.snapshot().call_availability, Some(CallAvailability::Busy));
    f.runtime
        .session_mut(&f.session)
        .unwrap()
        .call_occupancy
        .expire(crate::private_dm_runtime::now_ms() + 15_001);
    assert_eq!(f.snapshot().call_availability, None);
    select(f, "known-call", &caller, &receiver, 3);
    assert_eq!(f.snapshot().call_availability, Some(CallAvailability::Busy));
    let peer = f.contact.device().moss_peer_id.clone();
    let end = remote_control(
        f,
        &caller,
        &peer,
        "known-call",
        4,
        json!({"End": {"reason": "hangup"}}),
    );
    apply(f, end);
    assert_eq!(f.snapshot().call_availability, None);
}

fn unsupported_offer_cannot_establish_selection_authority(f: &mut Fixture) {
    offer(f, "unsupported-call", !NATIVE);
    let caller = f.contact.device().device_id.clone();
    select(f, "unsupported-call", &caller, &sibling(f), 2);
    assert_eq!(f.snapshot().call_availability, None);
}

fn restart_restores_busy_only_from_a_trusted_sibling(f: &mut Fixture) {
    offer(f, "known-call", NATIVE);
    let caller_device = f.contact.device().device_id.clone();
    let receiver = sibling(f);
    select(f, "known-call", &caller_device, &receiver, 2);
    assert_eq!(f.snapshot().call_availability, Some(CallAvailability::Busy));
    f.runtime.rehydrate();
    select(f, "known-call", &caller_device, &receiver, 3);
    assert_eq!(f.snapshot().call_availability, None);
    let caller = hex::encode(f.peers[&caller_device].signer_public());
    let sibling_device = f.source.device().device_id.clone();
    let peer = f.source.device().moss_peer_id.clone();
    let occupied = remote_control(
        f,
        &sibling_device,
        &peer,
        "known-call",
        1,
        json!({"Occupied": {"caller": caller, "receiver": receiver}}),
    );
    apply(f, occupied);
    assert_eq!(f.snapshot().call_availability, Some(CallAvailability::Busy));
}

#[test]
fn signed_selections_require_an_admitted_offer_from_the_original_caller() {
    let status = std::process::Command::new(std::env::current_exe().unwrap())
        .args(["--exact",
            "private_dm_runtime::devices::history::packet_tests::calls::selection_admission::selection_admission_process",
            "--ignored", "--nocapture"])
        .status().unwrap();
    assert!(status.success());
}

#[test]
#[ignore = "Isolated real MLS/Moss selection admission fixture"]
fn selection_admission_process() {
    unsolicited_selection_cannot_reserve_a_device(&mut Fixture::new());
    dismissed_offer_remembers_only_its_original_caller(&mut Fixture::new());
    selected_sibling_heartbeats_keep_the_admitted_call_busy(&mut Fixture::new());
    unsupported_offer_cannot_establish_selection_authority(&mut Fixture::new());
    restart_restores_busy_only_from_a_trusted_sibling(&mut Fixture::new());
}
