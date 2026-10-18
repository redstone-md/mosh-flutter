use super::*;
use crate::moss_ffi::MOSS_TEST_LOCK;
use std::sync::mpsc;
use std::time::Duration;

#[test]
fn device_link_service_waits_until_the_plus_account_action_finishes() {
    let _guard = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let vector: serde_json::Value =
        serde_json::from_str(include_str!("../../tests/fixtures/plus-public-vector.json")).unwrap();
    configure_issuer(vector["public_key"].as_str().unwrap().into()).unwrap();
    let (start, started) = mpsc::channel();
    let (finished, completion) = mpsc::channel();
    let service = std::thread::spawn(move || {
        started.recv().unwrap();
        let snapshot = crate::api::device_link::snapshot().unwrap();
        finished.send(snapshot.user_id).unwrap();
    });
    let blocked = with_owner(|_| {
        start.send(()).unwrap();
        Ok(matches!(
            completion.recv_timeout(Duration::from_millis(100)),
            Err(mpsc::RecvTimeoutError::Timeout)
        ))
    })
    .unwrap();
    service.join().unwrap();
    assert!(
        blocked,
        "device-link service must not adopt an account during a PLUS action"
    );
}
