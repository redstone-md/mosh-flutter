//! Shared process-global runtime resources for the `api` facade (ADR 0016).
//
// The four runtimes (`PrivateDmRuntime`, `ChannelRuntime`,
// `PrivateGroupRuntime`, `OrgRuntime`) all share ONE Moss
// node + ONE attachment store + ONE persistence store: a
// single `SharedResources` constructed once
// (via `ensure_shared_resources`) and borrowed by every runtime's
// `construct_runtime`.
//
// The two mobile-inject knobs (`INJECTED_DEK`, `APP_DATA_DIR`) live here
// too -- they affect construction and are read once at construct time, so a
// process-global `OnceLock` matches the "set once, read at construct"
// lifetime. They were previously in `api/private_dm.rs`; moved here so the
// channel/group facades can read them without a private_dm dependency (the
// knobs are platform-channel concerns, not DM-specific).

use std::path::PathBuf;
use std::sync::{Arc, OnceLock};

use crate::attachment_store::AttachmentStore;
use crate::moss_ffi::{set_moss_keystore, MossFfiRuntime};
use crate::persistence::Persistence;
use crate::shared_node::SharedMossNode;

/// The at-rest DEK injected by the mobile platform channel (ADR 0011).
static INJECTED_DEK: OnceLock<[u8; 32]> = OnceLock::new();

/// The app-private data directory bridged from the platform channel (ADR
/// 0010, M-5). Read ONCE at construct time, so a process-global `OnceLock`
/// matches the lifetime.
static APP_DATA_DIR: OnceLock<PathBuf> = OnceLock::new();

/// The shared Moss node + attachment store + persistence, constructed once
/// per process and borrowed by every runtime facade (DM, channel, group,
/// org). Holds `Arc`s so each runtime can clone the references into its own
/// `from_shared_node` call without re-loading Moss or re-opening the DB.
/// `Err` after a failed first construction (cached so later calls report
/// the original error instead of retrying into the same failure).
static SHARED_RESOURCES: OnceLock<Result<SharedResources, String>> = OnceLock::new();

/// The shared Moss node + the two stores a runtime borrows. Cheap to clone
/// (three `Arc` bumps) so each facade can `ensure_shared_resources().clone()`
/// at construct time.
#[flutter_rust_bridge::frb(opaque)]
#[derive(Clone)]
pub struct SharedResources {
    pub(crate) shared_node: Arc<SharedMossNode>,
    pub(crate) attachment_store: Arc<AttachmentStore>,
    pub(crate) persistence: Option<Arc<Persistence>>,
}

/// Inject the at-rest history DEK from the mobile platform channel (ADR 0011).
pub fn set_history_dek(dek: Vec<u8>) -> Result<(), String> {
    if dek.len() != 32 {
        return Err(format!(
            "set_history_dek: DEK must be exactly 32 bytes, got {}",
            dek.len()
        ));
    }
    let mut fixed = [0u8; 32];
    fixed.copy_from_slice(&dek);
    // Idempotent across main() re-runs in a live process. Android can re-run
    // main() on activity recreation / warm start (a fresh Dart isolate in the
    // same process re-enters the inject calls); a new Dart isolate loses its
    // module-level mirror of this cell, so it cannot tell the inject already
    // happened. The Rust `OnceLock` is process-global and DOES persist, so it
    // must be the side that tolerates the no-op re-inject. Accept a re-inject
    // of the SAME 32 bytes as Ok (true no-op); reject only a DIFFERENT DEK,
    // which would be a real divergence (the live runtime opened the DB under
    // the first DEK and re-injecting a new one would orphan it). Slice-3
    // device-pass finding: the prior "already injected" Err propagated as an
    // unhandled exception in main() and blank-screened the warm start.
    match INJECTED_DEK.set(fixed) {
        Ok(()) => Ok(()),
        Err(_) => match INJECTED_DEK.get() {
            Some(existing) if *existing == fixed => Ok(()),
            _ => Err(
                "set_history_dek: DEK already injected with a different value; \
 re-injection is not allowed"
                    .to_string(),
            ),
        },
    }
}

/// Inject the app-private data directory from the platform channel (ADR
/// 0010, M-5). Idempotent-once; returns `Err` for an empty path.
pub fn set_app_data_dir(path: String) -> Result<(), String> {
    if path.trim().is_empty() {
        return Err("set_app_data_dir: path must be a non-empty directory".to_string());
    }
    // The first Rust entry point from Dart on every platform: from here on,
    // any Rust panic anywhere in the process leaves a line in the field log
    // instead of dying silently.
    crate::diagnostics_log::install_panic_hook();
    // Idempotent across main() re-runs in a live process; see `set_history_dek`
    // for the rationale. Accept a re-inject of the SAME path as Ok (true
    // no-op); reject only a DIFFERENT path, which would be a real divergence
    // between Dart's DB-exists check and the path Rust opened the DB under.
    let candidate = PathBuf::from(path);
    // `candidate` is moved into `set`; clone so the original survives for the
    // same-value comparison in the Err branch (PathBuf is not Copy).
    match APP_DATA_DIR.set(candidate.clone()) {
        Ok(()) => Ok(()),
        Err(_) => match APP_DATA_DIR.get() {
            Some(existing) if *existing == candidate => Ok(()),
            _ => Err(
                "set_app_data_dir: app_data_dir already set to a different path; \
 re-setting is not allowed"
                    .to_string(),
            ),
        },
    }
}

/// Lazily construct the shared resources once, then return a clone. Each
/// runtime facade calls this at construct time and hands the clones to its
/// `from_shared_node(shared_node, attachment_store, persistence)` ctor.
pub fn ensure_shared_resources() -> Result<SharedResources, String> {
    let result = SHARED_RESOURCES.get_or_init(construct_resources);
    match result {
        Ok(resources) => Ok(resources.clone()),
        Err(error) => Err(error.clone()),
    }
}

/// Resolve the data dir: `<app_data_dir>/mosh` when injected, else the
/// temp-dir `mosh` dir.
/// The at-rest history database. Single definition so the diagnostics facade
/// reports the same path `construct_resources` opens.
pub(crate) fn database_path() -> PathBuf {
    resolve_data_dir(APP_DATA_DIR.get().map(PathBuf::as_path)).join("history.redb")
}

pub(crate) fn resolve_data_dir(app_data_dir: Option<&std::path::Path>) -> PathBuf {
    match app_data_dir {
        Some(dir) => dir.join("mosh"),
        None => std::env::temp_dir().join("mosh"),
    }
}

/// The resolved data dir with the injected `APP_DATA_DIR` applied. Use
/// for non-runtime state that lives next to the encrypted history store
/// (e.g. VPN-bypass consent). When no platform channel injected a dir,
/// the temp `mosh` dir is used (tests, hosts without path_provider).
pub(crate) fn resolved_data_dir() -> PathBuf {
    resolve_data_dir(APP_DATA_DIR.get().map(PathBuf::as_path))
}

/// Build the shared resources once. Loads Moss, opens the encrypted
/// at-rest store under the resolved data dir, wires the keystore, and
/// builds the attachment store + shared node. Returns `Err` on any failure
/// (cached by the `OnceLock` so later calls report the same cause).
fn construct_resources() -> Result<SharedResources, String> {
    let moss = MossFfiRuntime::load_default().map_err(|error| error.to_string())?;
    let data_dir = resolve_data_dir(APP_DATA_DIR.get().map(PathBuf::as_path));
    std::fs::create_dir_all(&data_dir).map_err(|error| format!("mkdir data dir: {error}"))?;
    let db_path = database_path();
    let persistence = match INJECTED_DEK.get() {
        Some(dek) => Persistence::open_with_dek(&db_path, *dek),
        None => Persistence::open(&db_path),
    }
    .map_err(|error| error.to_string())?;
    let persistence = Arc::new(persistence);
    set_moss_keystore(persistence.clone());
    moss.install_keystore().map_err(|error| error.to_string())?;
    let shared_node = SharedMossNode::new(Arc::new(moss));
    let attachment_store =
        Arc::new(AttachmentStore::new(data_dir).map_err(|error| error.to_string())?);
    Ok(SharedResources {
        shared_node,
        attachment_store,
        persistence: Some(persistence),
    })
}
