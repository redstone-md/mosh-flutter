use super::*;
use crate::private_dm_runtime::devices::recovery::{RecoveryOffer, RecoveryProbe};
use crate::private_dm_runtime::devices::DEVICE_CHANNEL;
use crate::private_dm_runtime::transport::memory::{MemoryNet, MemoryTransport};
use crate::private_dm_runtime::transport::{DmTransport, PeerTransport};

#[test]
fn recovery_asks_for_the_next_batch_as_soon_as_an_answer_is_saved() {
    let status = std::process::Command::new(std::env::current_exe().unwrap())
        .args([
            "--exact",
            "private_dm_runtime::devices::history::packet_tests::recovery::pipeline::pipelined_pull_process",
            "--ignored",
            "--nocapture",
        ])
        .status()
        .unwrap();
    assert!(status.success());
}

/// Offsets of the recovery pulls the contact received since the last call.
fn pulls(contact: &MemoryTransport, peer: &str) -> Vec<usize> {
    contact
        .drain()
        .into_iter()
        .filter(|frame| frame.channel == DEVICE_CHANNEL)
        .filter_map(
            |frame| match DevicePacket::open(&frame.payload, peer).ok()?.message {
                DeviceMessage::RecoveryPull(pull) => Some(pull.request.offset),
                _ => None,
            },
        )
        .collect()
}

// No tick runs here: every pull comes from handling the previous answer.
#[test]
#[ignore = "isolated Moss keystore worker invoked by pipelined recovery test"]
fn pipelined_pull_process() {
    let mut f = Fixture::new();
    let net = MemoryNet::new();
    let own = f.receiver.device().moss_peer_id.clone();
    let peer = f.contact.device().moss_peer_id.clone();
    net.link_both(&own, &peer, PeerTransport::Direct);
    f.runtime.transport = net.endpoint(&own);
    let contact = net.endpoint(&peer);
    let source = f.contact.device().clone();
    begin(&mut f, &source, 2);
    let session = f.runtime.session_mut(&f.session).unwrap();
    session
        .membership
        .as_mut()
        .unwrap()
        .recovery
        .as_mut()
        .unwrap()
        .source = None;
    let offer = DeviceMessage::RecoveryOffer(RecoveryOffer {
        probe: RecoveryProbe {
            session_id: f.session.clone(),
            request_id: "recovery-packets".into(),
            round: 7,
        },
        epoch: 2,
        manifest: "ab".repeat(32),
    });
    f.receive(&f.packet(&f.contact, offer)).unwrap();
    assert_eq!(
        pulls(&contact, &peer),
        [0],
        "a selected source is pulled at once"
    );
    let first = batch(&f, 0, 2, vec![record("first-pipelined", "First")]);
    f.receive(&f.packet(&f.contact, DeviceMessage::RecoveryBatch(first)))
        .unwrap();
    assert_eq!(
        pulls(&contact, &peer),
        [1],
        "the next batch is pulled at once"
    );
    let last = batch(&f, 1, 2, vec![record("last-pipelined", "Last")]);
    f.receive(&f.packet(&f.contact, DeviceMessage::RecoveryBatch(last)))
        .unwrap();
    assert!(
        pulls(&contact, &peer).is_empty(),
        "a finished manifest stops"
    );
    assert_eq!(text(&f, "last-pipelined")[0].body, "Last");
}
