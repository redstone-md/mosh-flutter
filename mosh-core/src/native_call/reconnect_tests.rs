//! Two owners with real engines over a memory network: a call whose path is
//! cut past ICE's failure timeout comes back by itself once the path returns.
use super::*;
use crate::private_dm_runtime::transport::{memory::MemoryNet, PeerTransport};

struct Side {
    owner: Owner,
    state: State,
    transport: Arc<dyn DmTransport>,
}

impl Side {
    fn new(net: &Arc<MemoryNet>, me: &str, peer: &str, caller: bool) -> Self {
        let transport: Arc<dyn DmTransport> = net.endpoint(me);
        let context = Context {
            session_id: "dm".into(),
            call_id: "call".into(),
            superseded: None,
            active: true,
            caller,
            caller_signer: "caller".into(),
            callee_signer: Some("callee".into()),
            peer: peer.into(),
        };
        let state = State {
            context: Some(context),
            prepared: true,
            ..Default::default()
        };
        Self {
            owner: Owner::new(transport.clone()),
            state,
            transport,
        }
    }

    fn ice(&mut self) -> String {
        let connection = self.owner.connection.as_mut().expect("no connection");
        let snapshot = connection.engine.ask(json!({"action":"snapshot"})).unwrap();
        snapshot["connection"]
            .as_str()
            .unwrap_or_default()
            .to_owned()
    }

    fn ready(&self) -> bool {
        self.state.snapshot.ready
    }
}

/// Steps both owners until `done` holds or `limit` passes, carrying their
/// call signals unless the path is `cut`; true if it held.
fn run(
    sides: &mut [Side; 2],
    cut: bool,
    limit: Duration,
    mut done: impl FnMut(&mut [Side; 2]) -> bool,
) -> bool {
    let until = Instant::now() + limit;
    while Instant::now() < until {
        for side in sides.iter_mut() {
            side.owner
                .step(&mut side.state, &*side.transport, None)
                .unwrap();
        }
        let [a, b] = sides;
        carry(a, b, cut);
        carry(b, a, cut);
        assert!(
            sides.iter().all(|side| !side.state.snapshot.failed),
            "the call ended"
        );
        if done(sides) {
            return true;
        }
        // test-policy: wait MOSH-88 -- libwebrtc times ICE consent and failure on its own clock
        std::thread::sleep(Duration::from_millis(10));
    }
    false
}

/// Hands `from`'s call signals to `to`, the way the DM session does, or
/// loses them on a cut path.
fn carry(from: &mut Side, to: &mut Side, cut: bool) {
    for (_, _, signal) in from.state.outbound.drain(..) {
        if !cut {
            to.state.inbound.push_back(signal);
        }
    }
}

fn cut(net: &MemoryNet, cut: bool) {
    for (from, to) in [("a", "b"), ("b", "a")] {
        net.drop_frames(from, to, move |_, _| cut);
    }
}

#[test]
// test-policy: skip MOSH-88 -- needs the built engine through MOSH_MEDIA_ENGINE; CI runs it with --include-ignored
#[ignore = "Requires the real native engine through MOSH_MEDIA_ENGINE"]
fn a_call_reconnects_after_its_path_fails_and_returns() {
    let net = MemoryNet::new();
    net.link_both("a", "b", PeerTransport::Direct);
    let mut sides = [
        Side::new(&net, "a", "b", true),
        Side::new(&net, "b", "a", false),
    ];
    let both_ready = |sides: &mut [Side; 2]| sides.iter().all(Side::ready);
    assert!(
        run(&mut sides, false, Duration::from_secs(10), both_ready),
        "the call never connected"
    );

    cut(&net, true);
    let failed = |sides: &mut [Side; 2]| sides.iter_mut().all(|side| side.ice() == "Failed");
    assert!(
        run(&mut sides, true, Duration::from_secs(30), failed),
        "ICE never failed"
    );
    assert!(sides.iter().all(|side| side.state.snapshot.reconnecting));

    cut(&net, false);
    assert!(
        run(&mut sides, false, Duration::from_secs(10), both_ready),
        "the call did not reconnect; ICE is {} and {}",
        sides[0].ice(),
        sides[1].ice()
    );
}
