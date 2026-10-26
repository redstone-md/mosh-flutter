//! One serialized execution authority. Lock order: authority, one runtime, node.
use super::{changes, BackgroundMode as Mode, BackgroundReachability as Reach, BackgroundStatus};
use crate::{
    api::shared_runtime,
    moss_ffi::{ActivityMode, MossNode},
    persistence::Persistence,
};
use std::sync::{
    atomic::{AtomicBool, Ordering},
    Arc, Mutex, OnceLock, RwLock, RwLockReadGuard,
};

static OWNER: OnceLock<Owner> = OnceLock::new();
static AUTHORITY: RwLock<()> = RwLock::new(());
static DRIVE: Mutex<()> = Mutex::new(());
static ALLOW_HISTORY: AtomicBool = AtomicBool::new(true);

struct Owner {
    state: Mutex<State>,
    node: Arc<MossNode>,
    store: Arc<Persistence>,
}

struct State {
    interactive: bool,
    waiting_enabled: bool,
    intent_saved: bool,
    applied_mode: Option<Mode>,
    limitation: Option<String>,
    calls: u32,
    transfers: u32,
}

pub(super) fn store() -> Result<Arc<Persistence>, String> {
    shared_runtime::ensure_shared_resources()?
        .persistence
        .ok_or_else(|| "background storage unavailable".into())
}

fn owner() -> Result<&'static Owner, String> {
    if let Some(owner) = OWNER.get() {
        return Ok(owner);
    }
    let resources = shared_runtime::ensure_shared_resources()?;
    let store = store()?;
    let waiting_enabled = store
        .saved_background_intent()
        .map_err(|e| e.to_string())?
        .unwrap_or(true);
    resources
        .shared_node
        .start_suspended_if_idle(!waiting_enabled);
    // Existing DM service supplies incoming delivery without any UI poller.
    // Saved off starts with a dormant native identity, never a transient mesh.
    drop(crate::api::private_dm::ensure_runtime().map_err(|e| e.to_string())?);
    let node = resources
        .shared_node
        .acquire(0, None)
        .map_err(|e| e.to_string())?;
    let candidate = Owner {
        node,
        store,
        state: Mutex::new(State {
            interactive: false,
            waiting_enabled,
            intent_saved: false,
            applied_mode: None,
            limitation: None,
            calls: 0,
            transfers: 0,
        }),
    };
    if OWNER.set(candidate).is_err() {
        resources.shared_node.release();
    }
    Ok(OWNER.get().expect("initialized execution owner"))
}

pub(super) fn set(interactive: bool, waiting_enabled: bool) -> Result<BackgroundStatus, String> {
    let owner = owner()?;
    {
        let _authority = AUTHORITY
            .write()
            .map_err(|_| "background execution unavailable")?;
        let mut state = owner
            .state
            .lock()
            .map_err(|_| "background execution unavailable")?;
        if !state.intent_saved
            || state.interactive != interactive
            || state.waiting_enabled != waiting_enabled
        {
            owner
                .store
                .save_background_intent(interactive, waiting_enabled)
                .map_err(|e| e.to_string())?;
            state.intent_saved = true;
        }
        state.interactive = interactive;
        state.waiting_enabled = waiting_enabled;
        ALLOW_HISTORY.store(interactive || waiting_enabled, Ordering::Release);
        if !interactive && !waiting_enabled {
            crate::conversation::recovery::transport::cancel_pending();
        }
    }
    reconcile();
    changes::changed();
    status()
}

pub(crate) fn admit_user_work() -> Result<RwLockReadGuard<'static, ()>, String> {
    let lease = execution_lease()?;
    if let Some(owner) = OWNER.get() {
        let mut state = owner
            .state
            .lock()
            .map_err(|_| "background execution unavailable")?;
        apply(owner, &mut state, Mode::Active)?;
    }
    Ok(lease)
}

pub(crate) fn execution_lease() -> Result<RwLockReadGuard<'static, ()>, String> {
    AUTHORITY
        .read()
        .map_err(|_| "background execution unavailable".into())
}

pub(crate) fn automatic_downloads_allowed() -> bool {
    OWNER.get().is_none_or(|owner| {
        owner
            .state
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .interactive
    })
}

pub(crate) fn network_permitted() -> bool {
    OWNER
        .get()
        .is_none_or(|owner| owner.node.transport_running())
}

/// Called after the DM mutex is released, never from a conversation callback.
pub(crate) fn reconcile() {
    let Some(owner) = OWNER.get() else {
        return;
    };
    let Ok(_drive) = DRIVE.try_lock() else {
        return;
    };
    let Ok(_authority) = AUTHORITY.write() else {
        return;
    };
    let facts = work_facts();
    let mut state = owner.state.lock().unwrap_or_else(|e| e.into_inner());
    let before = (
        state.applied_mode,
        state.calls,
        state.transfers,
        state.limitation.clone(),
    );
    let (calls, transfers) = match facts {
        Ok(facts) => facts,
        Err(error) => {
            state.limitation = Some(error);
            return;
        }
    };
    state.calls = calls;
    state.transfers = transfers;
    let mode = desired(&state);
    let result =
        if mode == Mode::Offline && crate::conversation::recovery::transport::active_sends() > 0 {
            Ok(()) // An already-admitted bounded send drains before native Stop.
        } else {
            apply(owner, &mut state, mode)
        };
    state.limitation = result.err();
    let changed = before
        != (
            state.applied_mode,
            state.calls,
            state.transfers,
            state.limitation.clone(),
        );
    drop(state);
    if changed {
        changes::changed();
    }
}

fn work_facts() -> Result<(u32, u32), String> {
    // No cross-runtime lock nesting: each initialized owner flushes and releases.
    [
        crate::api::private_dm::background_work(),
        crate::api::private_group::background_work(),
        crate::api::channel::background_work(),
    ]
    .into_iter()
    .try_fold((0u32, 0u32), |sum, facts| {
        let (calls, transfers) = facts?;
        Ok((sum.0.saturating_add(calls), sum.1.saturating_add(transfers)))
    })
}

pub(crate) fn history_execution_allowed() -> bool {
    ALLOW_HISTORY.load(Ordering::Acquire)
}

// Android's callback is a hint, never proof of carrier reachability.
#[cfg(target_os = "android")]
pub(crate) fn notify_network_changed() -> i32 {
    let Some(owner) = OWNER.get() else {
        return -3;
    };
    let Ok(_authority) = execution_lease() else {
        return -4;
    };
    match owner.node.notify_network_changed() {
        Ok(()) => 0,
        Err(crate::moss_ffi::MossFfiError::Symbol(_)) => -2,
        Err(crate::moss_ffi::MossFfiError::TransportOffline) => -3,
        Err(_) => -4,
    }
}

fn desired(state: &State) -> Mode {
    if state.interactive || state.calls > 0 || state.transfers > 0 {
        Mode::Active
    } else if state.waiting_enabled {
        Mode::Waiting
    } else {
        Mode::Offline
    }
}

fn apply(owner: &Owner, state: &mut State, mode: Mode) -> Result<(), String> {
    if mode == Mode::Offline || (mode == Mode::Waiting && !owner.node.supports_activity_mode()) {
        owner.node.suspend_transport().map_err(|e| e.to_string())?;
        state.applied_mode = Some(if mode == Mode::Offline {
            mode
        } else {
            Mode::Unsupported
        });
        return Ok(());
    }
    owner.node.resume_transport().map_err(|e| e.to_string())?;
    if state.applied_mode != Some(mode) && owner.node.supports_activity_mode() {
        owner
            .node
            .set_activity_mode(if mode == Mode::Active {
                ActivityMode::Active
            } else {
                ActivityMode::Waiting
            })
            .map_err(|e| e.to_string())?;
    }
    state.applied_mode = Some(mode);
    Ok(())
}

pub(super) fn status() -> Result<BackgroundStatus, String> {
    let owner = owner()?;
    reconcile();
    let state = owner
        .state
        .lock()
        .map_err(|_| "background execution unavailable")?;
    let snapshot = owner.node.activity_snapshot();
    let actual = match (&snapshot, state.applied_mode) {
        (_, Some(Mode::Unsupported)) => Mode::Unsupported,
        (Some(s), _) if s.activity_mode == ActivityMode::Waiting => Mode::Waiting,
        (_, _) if !owner.node.transport_running() => Mode::Offline,
        _ => Mode::Active,
    };
    let reachability = match snapshot
        .as_ref()
        .and_then(|s| s.waiting_reachability.as_deref())
    {
        Some("ready")
            if actual == Mode::Waiting
                && snapshot
                    .as_ref()
                    .is_some_and(|s| s.requested_activity_mode == ActivityMode::Waiting) =>
        {
            Reach::Ready
        }
        Some("attaching") => Reach::Attaching,
        _ => Reach::Unavailable,
    };
    Ok(BackgroundStatus {
        revision: changes::revision(),
        interactive: state.interactive,
        waiting_enabled: state.waiting_enabled,
        requested_mode: desired(&state),
        actual_mode: actual,
        reachability,
        attachment_count: snapshot.map_or(0, |s| s.waiting_attachment_count),
        current_calls: state.calls,
        current_user_transfers: state.transfers,
        limitation: state.limitation.clone(),
    })
}
