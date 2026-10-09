use super::*;
use crate::endpoint::Endpoint;

fn binding() -> MediaBinding {
    MediaBinding {
        session_id: "dm".into(),
        call_id: "call".into(),
        caller: "caller-leaf".into(),
        callee: "selected-leaf".into(),
        media_session: vec![8; 16],
    }
}

#[test]
fn selected_pair_installs_public_descriptions_once_without_exporting_secrets() {
    let caller = Endpoint::new("caller", |_| {}).unwrap();
    let callee = Endpoint::new("callee", |_| {}).unwrap();
    let mut left =
        Negotiator::new(binding(), Role::Caller, Arc::new(Mutex::new([false; 128]))).unwrap();
    let mut right =
        Negotiator::new(binding(), Role::Callee, Arc::new(Mutex::new([false; 128]))).unwrap();
    let offer = left.offer(&caller.pc).unwrap();
    assert_eq!(left.offer(&caller.pc).unwrap(), offer);
    assert!(!left.ready());
    let mut invalid = offer.clone();
    invalid.binding.callee = "unselected-sibling".into();
    assert!(right.receive(&callee.pc, invalid).is_err());
    let answer = right.receive(&callee.pc, offer.clone()).unwrap();
    assert_eq!(right.receive(&callee.pc, offer).unwrap(), answer);
    left.receive(&caller.pc, answer.clone()).unwrap();
    assert!(left.ready() && right.ready());
    assert!(left.agreement.is_none() && right.agreement.is_none());
    let json = serde_json::to_value(&answer).unwrap();
    assert_eq!(json.as_object().unwrap().len(), 3);
    assert!(json.get("key").is_none() && json.get("salt").is_none());
    left.receive(&caller.pc, answer.clone()).unwrap();
    let mut changed = answer;
    changed.parameters.clear();
    assert!(left.receive(&caller.pc, changed).is_err());
}
