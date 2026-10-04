use super::*;
use crate::conversation::mesh::PeerDetail;

fn peer(id: &str, relayed: bool) -> PeerDetail {
    PeerDetail {
        id: id.to_string(),
        addr: "10.0.0.1:4001".to_string(),
        relayed,
    }
}

// The shared node connects to unrelated world peers, so a crowded mesh
// says nothing about one counterpart: only its own row does.
#[test]
fn reach_matches_the_counterpart_row_not_the_crowd() {
    let counterpart = "aa".repeat(32);
    let stranger = "bb".repeat(32);

    let crowd = MeshInfo {
        peer_count: 50,
        direct_peer_count: 40,
        peer_details: vec![peer(&stranger, false)],
        ..Default::default()
    };
    assert_eq!(reach_of(&counterpart, &crowd), PeerTransport::None);

    let relayed = MeshInfo {
        peer_details: vec![peer(&stranger, false), peer(&counterpart, true)],
        ..Default::default()
    };
    assert_eq!(reach_of(&counterpart, &relayed), PeerTransport::Relayed);

    let direct = MeshInfo {
        peer_details: vec![peer(&counterpart, false)],
        ..Default::default()
    };
    assert_eq!(reach_of(&counterpart, &direct), PeerTransport::Direct);
}

#[test]
fn memory_net_delivers_only_over_reachable_links_and_honors_drops() {
    use memory::MemoryNet;
    let net = MemoryNet::new();
    let a = net.endpoint("a");
    let b = net.endpoint("b");

    // No link yet: nobody to publish to.
    assert!(matches!(
        a.publish("room", "chan", b"x"),
        Err(PublishError::NoPeers(_))
    ));
    assert_eq!(a.reach("b"), PeerTransport::None);

    net.link("a", "b", PeerTransport::Relayed);
    assert_eq!(a.reach("b"), PeerTransport::Relayed);
    assert_eq!(b.reach("a"), PeerTransport::None, "links are one-way");
    a.publish("room", "chan", b"one")
        .expect("linked publish is accepted");
    assert_eq!(b.drain().len(), 1);
    assert!(
        a.drain().is_empty(),
        "a frame never comes back to its sender"
    );

    net.drop_frames("a", "b", |_, payload| payload == b"lost");
    a.publish("room", "chan", b"lost")
        .expect("a dropped frame is still accepted");
    a.publish("room", "chan", b"kept").expect("publish");
    let kept = b.drain();
    assert_eq!(kept.len(), 1);
    assert_eq!(kept[0].payload, b"kept");

    a.connect_peer("b").expect("connect is recorded");
    assert_eq!(net.connect_requests("a"), vec!["b".to_string()]);
}
