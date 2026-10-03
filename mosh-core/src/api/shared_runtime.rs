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

use std::path::{Path, PathBuf};
use std::sync::{Arc, OnceLock};

use crate::attachment_store::AttachmentStore;
use crate::diagnostics_log::{self as dlog, kinds, LogLevel};
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

/// Mobile startup may repeat the same DEK after activity recreation.
/// A different DEK would orphan the database and is refused.
pub fn set_history_dek(dek: Vec<u8>) -> Result<(), String> {
    let fixed = dek.try_into().map_err(|dek: Vec<u8>| {
        format!(
            "set_history_dek: DEK must be exactly 32 bytes, got {}",
            dek.len()
        )
    })?;
    inject_once(
        &INJECTED_DEK,
        fixed,
        "set_history_dek: DEK already injected with a different value; re-injection is not allowed",
    )
}

/// Mobile startup may repeat the same path; a different path is refused.
pub fn set_app_data_dir(path: String) -> Result<(), String> {
    if path.trim().is_empty() {
        return Err("set_app_data_dir: path must be a non-empty directory".to_string());
    }
    crate::diagnostics_log::install_panic_hook();
    inject_once(
        &APP_DATA_DIR,
        PathBuf::from(path),
        "set_app_data_dir: app_data_dir already set to a different path; re-setting is not allowed",
    )
}

fn inject_once<T: PartialEq>(cell: &OnceLock<T>, value: T, error: &str) -> Result<(), String> {
    match cell.set(value) {
        Ok(()) => Ok(()),
        Err(value) if cell.get() == Some(&value) => Ok(()),
        Err(_) => Err(error.to_string()),
    }
}

/// Lazily construct the shared resources once, then return a clone. Each
/// runtime facade calls this at construct time and hands the clones to its
/// `from_shared_node(shared_node, attachment_store, persistence)` ctor.
pub fn ensure_shared_resources() -> Result<SharedResources, String> {
    SHARED_RESOURCES.get_or_init(construct_resources).clone()
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
    restore_vpn_bypass(&data_dir);
    let shared_node = SharedMossNode::new(Arc::new(moss));
    let attachment_store =
        Arc::new(AttachmentStore::new(data_dir).map_err(|error| error.to_string())?);
    Ok(SharedResources {
        shared_node,
        attachment_store,
        persistence: Some(persistence),
    })
}

/// Restore the saved adapter once, before the shared node can start. A stale
/// choice must not block startup, and explicit process overrides take priority.
fn restore_vpn_bypass(data_dir: &Path) {
    if crate::moss_ffi::current_bind_interface().is_some() {
        return;
    }
    let Some(consent) = crate::vpn_consent::load(data_dir) else {
        return;
    };
    let binding = crate::network_inventory::list_interfaces().and_then(|interfaces| {
        crate::vpn_consent::resolve(&consent, &interfaces)
            .map(|iface| iface.name.clone())
            .ok_or_else(|| "saved VPN adapter unavailable".to_string())
    });
    match binding {
        Ok(name) => crate::moss_ffi::set_bind_interface(Some(name)),
        Err(error) => dlog::write(
            LogLevel::Warn,
            kinds::CONNECT,
            "vpn-bypass",
            &format!("VPN bypass unavailable; using default routing: {error}"),
        ),
    }
}
