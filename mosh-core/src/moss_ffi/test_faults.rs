//! Fault injection hooks used by runtime behavior tests.
use super::*;

static TEST_PUBLISH_FAILURE: Mutex<Option<TestPublishOutcome>> = Mutex::new(None);

enum TestPublishOutcome {
    Injected(String),
    Code(i32),
}

pub struct TestPublishFailureGuard;

fn arm_test_publish(outcome: TestPublishOutcome) -> TestPublishFailureGuard {
    *TEST_PUBLISH_FAILURE
        .lock()
        .expect("test publish failure lock poisoned") = Some(outcome);
    TestPublishFailureGuard
}

pub fn fail_next_test_publish(message: &str) -> TestPublishFailureGuard {
    arm_test_publish(TestPublishOutcome::Injected(message.to_string()))
}

pub fn no_peers_next_test_publish() -> TestPublishFailureGuard {
    arm_test_publish(TestPublishOutcome::Code(MOSS_ERR_NO_PEERS))
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
pub(super) fn take_test_publish_outcome() -> Option<Result<(), MossFfiError>> {
    TEST_PUBLISH_FAILURE
        .lock()
        .expect("test publish failure lock poisoned")
        .take()
        .map(|outcome| match outcome {
            TestPublishOutcome::Injected(message) => {
                Err(MossFfiError::InjectedPublishFailure(message))
            }
            TestPublishOutcome::Code(code) => check_publish_code(code),
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
