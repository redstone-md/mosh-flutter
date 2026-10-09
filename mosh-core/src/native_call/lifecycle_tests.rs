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
fn ending_a_call_before_a_device_ack_rejects_the_pending_choices() {
    let state = Arc::new(Mutex::new(State {
        context: Some(pending("call")),
        prepared: true,
        ..Default::default()
    }));
    let hub = Arc::new(Hub {
        state: state.clone(),
    });
    let client = hub.clone();
    let applying = std::thread::spawn(move || client.choices("dm", "call", Choices::default()));
    let deadline = Instant::now() + Duration::from_secs(2);
    while state.lock().unwrap().revision == 0 {
        assert!(Instant::now() < deadline, "device request was not admitted");
        std::thread::sleep(Duration::from_millis(1));
    }
    let mut locked = state.lock().unwrap();
    // Publish the ended call and obsolete ACK together, without an intermediate state.
    locked.context = None;
    locked.applied = locked.revision;
    drop(locked);
    assert_eq!(
        applying.join().unwrap().unwrap_err(),
        "call ended while applying devices"
    );
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

#[test]
fn rejected_worker_preparation_and_choices_return_an_error() {
    let state = Arc::new(Mutex::new(State::default()));
    let hub = Hub {
        state: state.clone(),
    };
    let transport = MemoryNet::new().endpoint("local");
    let worker = std::thread::spawn(move || worker::run(state, transport));
    let mut context = pending("call");
    context.active = true;
    // The owner cannot negotiate an active caller without its selected receiver.
    assert!(hub.prepare(context, Choices::default()).is_err());
    assert!(hub.snapshot("dm", "call").unwrap().failed);
    assert!(hub.choices("dm", "call", Choices::default()).is_err());
    drop(hub);
    worker.join().unwrap();
}
