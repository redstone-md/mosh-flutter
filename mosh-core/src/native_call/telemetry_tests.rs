use super::*;
use crate::native_call::types::Binding;
use crate::private_dm_runtime::transport::memory::MemoryNet;

#[test]
#[ignore = "Requires the real native engine through MOSH_MEDIA_ENGINE"]
fn relay_budget_and_route_changes_apply_while_statistics_are_throttled() {
    let binding = Binding {
        session_id: "dm".into(),
        call_id: "call".into(),
        caller: "a".into(),
        callee: "b".into(),
        media_session: vec![9; 16],
    };
    let mut engine = Engine::new(&binding, true).unwrap();
    let net = MemoryNet::new();
    let transport = net.endpoint("a");
    net.endpoint("b");
    net.link("a", "b", PeerTransport::Relayed);
    let sender = Sender::new(transport.clone());
    let mut reporter = Reporter::new();
    // Freeze the statistics gate closed, independent of native startup time.
    reporter.statistics = Instant::now() + Duration::from_secs(60);
    let mut state = State::default();
    for route in [
        PeerTransport::Relayed,
        PeerTransport::Direct,
        PeerTransport::None,
    ] {
        net.link("a", "b", route);
        reporter
            .update(&mut engine, "b", true, &*transport, &sender, &mut state)
            .unwrap();
        assert_eq!(
            reporter.budget,
            capacity(route != PeerTransport::Direct).encoder_bits_per_second,
            "route limits cannot wait for the statistics timer"
        );
    }
}
