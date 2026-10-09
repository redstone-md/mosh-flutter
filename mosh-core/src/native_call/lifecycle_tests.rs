use super::*;
use crate::private_dm_runtime::transport::memory::MemoryNet;

fn pending(id: &str) -> Context {
    Context {
        session_id: "dm".into(),
        call_id: id.into(),
        superseded: None,
        active: false,
        caller: true,
        caller_signer: "caller".into(),
        callee_signer: None,
        peer: String::new(),
    }
}

#[test]
fn prepare_waits_for_initial_preferences_and_repeated_bind_preserves_choices() {
    let state = Arc::new(Mutex::new(State::default()));
    let hub = Hub {
        state: state.clone(),
    };
    let transport = MemoryNet::new().endpoint("local");
    let worker = std::thread::spawn(move || {
        std::thread::sleep(Duration::from_millis(30));
        worker::run(state, transport);
    });
    let choices = Choices {
        microphone: true,
        input: Some("saved-mic".into()),
        output: Some("saved-speaker".into()),
        ..Default::default()
    };
    hub.prepare(pending("call"), choices).unwrap();
    let snapshot = hub.snapshot("dm", "call").unwrap();
    assert_eq!(snapshot.call_id, "call");
    assert_eq!(snapshot.input.as_deref(), Some("saved-mic"));
    assert_eq!(snapshot.output.as_deref(), Some("saved-speaker"));
    hub.prepare(pending("call"), Choices::default()).unwrap();
    assert!(hub.snapshot("dm", "call").unwrap().microphone_requested);
    drop(hub);
    worker.join().unwrap();
}

#[test]
fn new_call_cannot_inherit_capture_consent_or_accept_stale_commands() {
    let hub = Hub {
        state: Arc::new(Mutex::new(State {
            context: Some(pending("old")),
            prepared: true,
            choices: Choices {
                camera: true,
                microphone: true,
                microphone_allowed: true,
                ..Default::default()
            },
            ..Default::default()
        })),
    };
    hub.sync(Some(pending("new")), Vec::new());
    let state = hub.state.lock().unwrap();
    assert!(!state.prepared);
    assert!(!state.choices.camera && !state.choices.microphone_allowed);
    drop(state);
    assert!(hub.choices("dm", "old", Choices::default()).is_err());
    assert!(hub.choices("dm", "new", Choices::default()).is_err());
}
