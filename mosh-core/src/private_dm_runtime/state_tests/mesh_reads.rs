use super::*;

#[test]
fn idle_service_reads_one_mesh_report_for_all_saved_chats() {
    let net = MemoryNet::new();
    let mut alice = runtime_on(&net, ALICE_ID);
    alice.service();
    assert!(alice.list_sessions().unwrap().sessions.is_empty());
    assert_eq!(net.mesh_reports(ALICE_ID), 0);
    for _ in 0..4 {
        invite(&mut alice);
    }
    let before = net.mesh_reports(ALICE_ID);
    alice.service();
    assert_eq!(
        net.mesh_reports(ALICE_ID) - before,
        1,
        "idle maintenance must share one current network observation across chats"
    );
}

#[test]
fn conversation_list_shares_a_fresh_mesh_report_across_all_rows() {
    let (net, mut alice, mut bob) = memory_pair();
    for _ in 0..4 {
        let invitation = invite(&mut alice);
        accept(&mut bob, &invitation);
        connect(&mut alice, &mut bob, &invitation.session_id);
    }
    for reach in [
        PeerTransport::Direct,
        PeerTransport::Relayed,
        PeerTransport::None,
    ] {
        net.link(ALICE_ID, BOB_ID, reach);
        let before = net.mesh_reports(ALICE_ID);
        let rows = alice.list_sessions().unwrap().sessions;
        assert_eq!(net.mesh_reports(ALICE_ID) - before, 2);
        assert_eq!(rows.len(), 4);
        for row in rows {
            assert_eq!(row.transport, reach);
            let info = row.mesh.unwrap();
            assert_eq!(info.peer_count, i32::from(reach != PeerTransport::None));
            if reach != PeerTransport::None {
                assert_eq!(
                    info.peer_details[0].relayed,
                    reach == PeerTransport::Relayed
                );
            }
        }
    }
    net.fail_mesh_reports(ALICE_ID, true);
    let before = net.mesh_reports(ALICE_ID);
    let rows = alice.list_sessions().unwrap().sessions;
    assert_eq!(net.mesh_reports(ALICE_ID) - before, 2);
    assert!(rows
        .iter()
        .all(|row| row.mesh.is_none() && row.transport == PeerTransport::None));
}
