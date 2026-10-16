//! Lock order: conversation owner -> PLUS. PLUS never locks a conversation.
use super::{PlusFrame, PlusRuntime, PlusSnapshot};
use crate::{conversation::now_ms, persistence::Persistence};
use std::sync::{Arc, Mutex};

static OWNER: Mutex<Option<(String, PlusRuntime)>> = Mutex::new(None);

pub(crate) fn configure(
    store: Arc<Persistence>,
    account: String,
    key: &str,
) -> Result<PlusSnapshot, String> {
    let mut guard = OWNER.lock().map_err(|_| "PLUS owner unavailable")?;
    if let Some((existing, owner)) = guard.as_ref() {
        if existing != key {
            return Err("PLUS issuer is already configured".into());
        }
        if owner.state.account_id == account {
            return Ok(owner.snapshot(now_ms()));
        }
    }
    let owner = PlusRuntime::open(store, account, key)?;
    let snapshot = owner.snapshot(now_ms());
    *guard = Some((key.into(), owner));
    Ok(snapshot)
}

pub(crate) fn with_owner<T>(
    account: &str,
    action: impl FnOnce(&mut PlusRuntime) -> Result<T, String>,
) -> Result<T, String> {
    let mut guard = OWNER.lock().map_err(|_| "PLUS owner unavailable")?;
    let (key, owner) = guard.as_mut().ok_or("PLUS issuer not configured")?;
    if owner.state.account_id != account {
        *owner = PlusRuntime::open(owner.store.clone(), account.into(), key)?;
    }
    action(owner)
}

pub(crate) fn frame(
    context: &str,
    peer: &str,
    author: &str,
    sign: impl FnOnce(&[u8]) -> Result<Vec<u8>, String>,
    now: u64,
) -> Result<Option<PlusFrame>, String> {
    let mut guard = OWNER.lock().map_err(|_| "PLUS owner unavailable")?;
    let Some((_, owner)) = guard.as_mut() else {
        return Ok(None);
    };
    owner.frame(context, peer, author, sign, now)
}

pub(crate) fn accept(
    frame: &PlusFrame,
    context: &str,
    author: &str,
    aliases: &[String],
    now: u64,
) -> Result<(), String> {
    let mut guard = OWNER.lock().map_err(|_| "PLUS owner unavailable")?;
    let Some((_, owner)) = guard.as_mut() else {
        return Ok(());
    };
    owner.accept_peer(frame, context, author, aliases, now)
}
