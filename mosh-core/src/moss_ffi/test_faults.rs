//! Fault injection hooks used by runtime behavior tests.
use super::*;

static TEST_PUBLISH_FAILURE: Mutex<Option<(Option<String>, TestPublishOutcome)>> = Mutex::new(None);

enum TestPublishOutcome {
    Injected(String),
    Code(i32),
    Accepted(Box<dyn FnOnce() + Send>),
}

pub struct TestPublishFailureGuard;

fn arm_test_publish(channel: Option<&str>, outcome: TestPublishOutcome) -> TestPublishFailureGuard {
    *TEST_PUBLISH_FAILURE
        .lock()
        .expect("test publish failure lock poisoned") = Some((channel.map(str::to_owned), outcome));
    TestPublishFailureGuard
}

pub fn fail_next_test_publish(message: &str) -> TestPublishFailureGuard {
    arm_test_publish(None, TestPublishOutcome::Injected(message.to_string()))
}

/// Refuse one application channel while allowing unrelated protocol traffic.
pub fn fail_next_test_publish_on(channel: &str, message: &str) -> TestPublishFailureGuard {
    arm_test_publish(
        Some(channel),
        TestPublishOutcome::Injected(message.to_string()),
    )
}

pub fn no_peers_next_test_publish() -> TestPublishFailureGuard {
    arm_test_publish(None, TestPublishOutcome::Code(MOSS_ERR_NO_PEERS))
}

pub(crate) fn after_next_test_publish(
    accepted: impl FnOnce() + Send + 'static,
) -> TestPublishFailureGuard {
    arm_test_publish(None, TestPublishOutcome::Accepted(Box::new(accepted)))
}

pub(super) fn tolerate_unmeshed_test_node(
    result: Result<(), MossFfiError>,
) -> Result<(), MossFfiError> {
    match result {
        Err(error) if error.is_no_peers() => Ok(()),
        other => other,
    }
}

/// The armed outcome for one publish, already turned into what the publish
/// should return. `None` means nothing was armed and the call goes to Moss.
pub(super) fn take_test_publish_outcome(channel: &str) -> Option<Result<(), MossFfiError>> {
    let mut fault = TEST_PUBLISH_FAILURE
        .lock()
        .expect("test publish failure lock poisoned");
    if fault
        .as_ref()
        .is_some_and(|(target, _)| target.as_deref().is_some_and(|target| target != channel))
    {
        return None;
    }
    fault.take().map(|(_, outcome)| match outcome {
        TestPublishOutcome::Injected(message) => Err(MossFfiError::InjectedPublishFailure(message)),
        TestPublishOutcome::Code(code) => check_publish_code(code),
        TestPublishOutcome::Accepted(accepted) => {
            accepted();
            Ok(())
        }
    })
}

impl Drop for TestPublishFailureGuard {
    fn drop(&mut self) {
        *TEST_PUBLISH_FAILURE
            .lock()
            .expect("test publish failure lock poisoned") = None;
    }
}

// A keyless-node fault affects only the requesting test thread; background
// device services cannot consume it.
thread_local! {
    static TEST_PUBLIC_KEY_UNAVAILABLE: std::cell::Cell<bool> = const { std::cell::Cell::new(false) };
}

pub struct TestPublicKeyUnavailableGuard(std::marker::PhantomData<std::rc::Rc<()>>);

/// Make this thread's next `public_key_hex` call return `None`.
pub fn public_key_unavailable_next_node() -> TestPublicKeyUnavailableGuard {
    TEST_PUBLIC_KEY_UNAVAILABLE.set(true);
    TestPublicKeyUnavailableGuard(std::marker::PhantomData)
}

pub(super) fn take_test_public_key_unavailable() -> bool {
    TEST_PUBLIC_KEY_UNAVAILABLE.replace(false)
}

impl Drop for TestPublicKeyUnavailableGuard {
    fn drop(&mut self) {
        TEST_PUBLIC_KEY_UNAVAILABLE.set(false);
    }
}
