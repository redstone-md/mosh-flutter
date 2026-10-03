use crate::*;

pub(super) fn load_runtime(
    moss_lib: Option<std::path::PathBuf>,
) -> Result<Arc<MossFfiRuntime>, Box<dyn std::error::Error>> {
    let runtime = match moss_lib {
        Some(path) => MossFfiRuntime::load_from_path(&path)?,
        None => MossFfiRuntime::load_default()?,
    };
    Ok(Arc::new(runtime))
}

/// The attachment store is required by the DM runtime but irrelevant to a
/// reachability probe, so it lives in a temp dir nobody has to clean up.
pub(super) fn scratch_store() -> Result<Arc<AttachmentStore>, Box<dyn std::error::Error>> {
    let mut path = std::env::temp_dir();
    path.push(format!("mosh-probe-attachments-{}", std::process::id()));
    Ok(Arc::new(AttachmentStore::new(&path)?))
}

/// The tick loop every kind runs on. `step` polls its own runtime, emits its
/// own snapshot line, and answers whether the goal is reached; nothing here
/// knows what a conversation is.
pub(super) fn pump_until(
    timeout: Duration,
    mut step: impl FnMut() -> Result<bool, Box<dyn std::error::Error>>,
) -> Result<bool, Box<dyn std::error::Error>> {
    let deadline = std::time::Instant::now() + timeout;
    while std::time::Instant::now() < deadline {
        if step()? {
            return Ok(true);
        }
        std::thread::sleep(TICK);
    }
    Ok(false)
}

/// Drives the runtime until `done` is satisfied or the budget runs out,
/// emitting one snapshot line per tick. Returns whether `done` was reached.
pub(super) fn pump(
    role: &str,
    dm: &mut PrivateDmRuntime,
    session_id: &str,
    timeout: Duration,
    mut done: impl FnMut(&SessionSnapshot) -> bool,
) -> Result<bool, Box<dyn std::error::Error>> {
    pump_until(timeout, || {
        let snap = dm.poll_session(session_id)?;
        snapshot_line(role, &snap);
        Ok(done(&snap))
    })
}

/// `pump` across several sessions at once: one snapshot line per session per
/// tick, finishing only when EVERY session satisfies `done`. Concurrency is the
/// point — checking them one after another would let an earlier session finish
/// and go quiet while a later one is still starting.
pub(super) fn pump_all(
    role: &str,
    dm: &mut PrivateDmRuntime,
    session_ids: &[String],
    timeout: Duration,
    mut done: impl FnMut(&SessionSnapshot) -> bool,
) -> Result<bool, Box<dyn std::error::Error>> {
    pump_until(timeout, || {
        let mut all = true;
        for session_id in session_ids {
            let snap = dm.poll_session(session_id)?;
            snapshot_line(role, &snap);
            if !done(&snap) {
                all = false;
            }
        }
        Ok(all)
    })
}

/// Acquire the transport and attachment store once for each probe command.
pub(super) fn resources(
    role: &str,
    moss_lib: Option<std::path::PathBuf>,
) -> Result<(Arc<MossFfiRuntime>, Arc<AttachmentStore>), Box<dyn std::error::Error>> {
    report_interfaces(role);
    Ok((load_runtime(moss_lib)?, scratch_store()?))
}

pub(super) fn finish(ok: bool) -> Result<(), Box<dyn std::error::Error>> {
    if !ok {
        std::process::exit(1);
    }
    Ok(())
}
