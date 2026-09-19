//! Diagnostics facade.
//!
//! Surfaces the former Tauri command group that reported app-level health:
//! `app_diagnostics` (aggregate frontend/runtime snapshot) and
//! `native_runtime_status` (per-runtime readiness and missing-dependency
//! messages). Returns plain bridge-friendly structs; no streams.
//!
//! Ports the old `src-tauri` command group verbatim; the api facade owns the
//! structs and constants so the bridge (ADR 0010) can serialize them without
//! touching a Tauri-typed type.

use crate::api::shared_runtime::{database_path, ensure_shared_resources};
use crate::diagnostics_log::{self as dlog, kinds, LogLevel};
use crate::moss_ffi::{MossFfiRuntime, MossNodeConfig};
use crate::moss_runtime::{MossDynamicRuntime, MossRuntime, MossRuntimeStatus};
use crate::shared_node::SUBSTRATE_ROOM;
pub use crate::openmls_crypto::{
    run_openmls_alice_bob_roundtrip, run_openmls_smoke_test, OpenMlsRoundTripStatus,
    OpenMlsSmokeStatus,
};
use crate::persistence::PersistenceRuntimeStatus;
use crate::secure_storage::{OsSecureSecretStore, SecureStorageStatus};
use flutter_rust_bridge::frb;
use std::any::Any;
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;

// App-level identity strings. Mirror the previous Tauri shell constants; kept
// as named consts (not inline literals) per AGENTS.md no-hardcoding rule.
const APP_NAME: &str = "Mosh";
const PRIVACY_MODEL: &str = "OpenMLS private messages over Moss transport";
const DISCOVERY_MODEL: &str = "default public Moss trackers";
const MOSS_LINK_MODE: &str = "dynamic";

// The version answer when the library cannot give one: the loaded copy
// predates `Moss_Version` (moss < v0.8.17). A stale library beside the
// binary looks exactly like a real regression, so the panel needs an honest
// "unknown" instead of a load failure (AGENTS.md named-constant rule).
const MOSS_VERSION_UNKNOWN: &str = "unknown";
// The field-log context every `moss_library_info` version line carries, so
// the line is greppable by the reporting call site rather than by session.
const VERSION_LOG_CONTEXT: &str = "moss_library_info";
// Nanoseconds per millisecond, for the RTT conversion Moss reports in.
const NANOS_PER_MS: u64 = 1_000_000;

// Persistence status: the Tauri shell pulled this from a managed
// `PersistenceStatusState` that tracked the live redb instance. When this
// facade was written it had no equivalent owner, so it answered a flat
// "available: false, no instance running here".
//
// It does have one now: `api::shared_runtime::SHARED_RESOURCES` opens the
// encrypted store once per process and hands `Arc<Persistence>` to every
// runtime. The flat answer therefore stopped being honest and became a
// permanent false alarm -- `persistenceWarningProvider` shows its banner
// whenever `available && encrypted_at_rest` is not true, so every session
// was told its history "may be lost after restart" while the DM runtime was
// persisting it perfectly well.
const PERSISTENCE_BACKEND: &str = "redb+aes-256-gcm+os-keychain";
const PERSISTENCE_UNAVAILABLE: &str = "no persistence instance running in this api call";

/// Aggregate frontend/runtime identity snapshot, one row of `app_diagnostics`.
#[frb(non_opaque)]
#[derive(serde::Serialize, Clone)]
pub struct AppDiagnostics {
    // Owned `String` (not `&'static str`): `flutter_rust_bridge` 2.x cannot
    // translate `&'static str` fields of a non-opaque struct across the FFI
    // boundary (the bare `str` is unsized, so its auto-opaque wrapper fails
    // to compile). Owned `String` is the bridge-friendly form and matches the
    // generated Dart `String` fields; the consts below stay `&'static str`
    // literals and are copied into the struct on construction.
    pub app_name: String,
    pub privacy_model: String,
    pub discovery_model: String,
    pub moss_link_mode: String,
}

/// Per-runtime readiness report, one row of `native_runtime_status`. Carries
/// statuses produced by the mosh-core runtimes; persistence is a not-available
/// marker when no host owns a running instance (see module doc).
#[frb(non_opaque)]
#[derive(serde::Serialize, Clone)]
pub struct NativeRuntimeStatus {
    pub moss: MossRuntimeStatus,
    pub secure_storage: SecureStorageStatus,
    pub persistence: PersistenceRuntimeStatus,
    pub openmls_smoke: OpenMlsSmokeRuntimeStatus,
    pub openmls_roundtrip: OpenMlsRoundTripRuntimeStatus,
}

/// Bridge-friendly view of the OpenMLS smoke-test outcome. `flutter_rust_bridge`
/// 2.x auto-opaques `Result<T, E>` fields of non-opaque structs (the wrapper has
/// no Dart constructor and no field accessors), so the api facade flattens the
/// result into a plain non-opaque struct: `ok` carries the success snapshot
/// when the test passed, `error` carries the failure message when it did not.
/// This keeps the field constructible from pure Dart (FakeGateway, tests) and
/// readable by the Diagnostics screen.
#[frb(non_opaque)]
#[derive(serde::Serialize, Clone)]
pub struct OpenMlsSmokeRuntimeStatus {
    pub ok: Option<OpenMlsSmokeStatus>,
    pub error: Option<String>,
}

/// Bridge-friendly view of the OpenMLS Alice/Bob roundtrip outcome; see
/// `OpenMlsSmokeRuntimeStatus` for why the result is flattened rather than
/// carried as a `Result<OpenMlsRoundTripStatus, String>`.
#[frb(non_opaque)]
#[derive(serde::Serialize, Clone)]
pub struct OpenMlsRoundTripRuntimeStatus {
    pub ok: Option<OpenMlsRoundTripStatus>,
    pub error: Option<String>,
}

/// What the loaded moss library itself reports, plus the panel rows that
/// hang off it. All values degrade honestly: `version` falls back to
/// [`MOSS_VERSION_UNKNOWN`] when the library predates `Moss_Version`
/// (v0.8.17), `peer_rtt_ms` stays `None` when there is no live node, the
/// peer is unknown, or the library predates `Moss_PeerRTT`, and `log_path`
/// stays `None` until the field log has opened its file. The version is a
/// library-level answer (no node required); the RTT needs the live shared
/// node. Both load through the same dynamic-symbol table every other moss
/// call uses -- a missing symbol never fails anything here.
#[frb(non_opaque)]
#[derive(serde::Serialize, Clone)]
pub struct MossLibraryInfo {
    /// The version the loaded library stamps itself with, or "unknown".
    pub version: String,
    /// Last measured round-trip time to the active DM counterpart, in
    /// milliseconds. `None` = not measured (no live node, no peer id, or a
    /// library without the symbol).
    pub peer_rtt_ms: Option<u64>,
    /// The field log's current file, so a bug report can carry it. `None`
    /// before the first write opened the file.
    pub log_path: Option<String>,
}

/// Reports the process-wide persistence store.
///
/// Goes through `ensure_shared_resources`, the same accessor every runtime
/// uses, so this reports the store the app actually runs on rather than a
/// guess. It is the idempotent `OnceLock` initialiser: the first caller pays
/// for opening the DB (which the first session-list call would have paid
/// anyway) and the rest just clone `Arc`s.
///
/// `encrypted_at_rest` tracks `available`: `Persistence::open` has no
/// unencrypted mode -- it either resolves an AES-256-GCM DEK from the
/// keychain or fails -- so a live instance is always an encrypted one.
fn persistence_status() -> PersistenceRuntimeStatus {
    let database = database_path().display().to_string();

    match ensure_shared_resources() {
        Ok(resources) if resources.persistence.is_some() => PersistenceRuntimeStatus {
            backend: PERSISTENCE_BACKEND.to_string(),
            database,
            available: true,
            encrypted_at_rest: true,
            error: None,
        },
        // Resources built, but without a store: nothing owns a DB here.
        Ok(_) => PersistenceRuntimeStatus {
            backend: PERSISTENCE_BACKEND.to_string(),
            database,
            available: false,
            encrypted_at_rest: false,
            error: Some(PERSISTENCE_UNAVAILABLE.to_string()),
        },
        // Construction failed -- surface the real cause, which is what the
        // warning banner is for.
        Err(error) => PersistenceRuntimeStatus {
            backend: PERSISTENCE_BACKEND.to_string(),
            database,
            available: false,
            encrypted_at_rest: false,
            error: Some(error),
        },
    }
}

/// Extracts a human-readable message from a panic payload caught by
/// `catch_unwind`. Rust's `panic!` most commonly carries a `&'static str` or
/// `String` message; non-string payloads (e.g. `panic!(42i32)`) collapse to a
/// generic placeholder so the diagnostics caller always receives a usable
/// `String` for the `error` field.
fn panic_payload_to_string(payload: Box<dyn Any + Send>) -> String {
    // `&'static str`: the common `panic!("literal")` form.
    if let Some(message) = payload.downcast_ref::<&'static str>() {
        return format!("panic: {}", message);
    }
    // `String`: the `panic!("{}", format!(..))` form.
    if let Some(message) = payload.downcast_ref::<String>() {
        return format!("panic: {}", message);
    }
    "panic: unknown panic payload".to_string()
}

/// Runs the OpenMLS smoke test and flattens the result into the bridge-friendly
/// `OpenMlsSmokeRuntimeStatus` (see struct doc).
///
/// `catch_unwind` guards against an OpenMLS internal panic (e.g. a poisoned
/// "Vaults list lock" left by an earlier panicked operation) propagating across
/// the FFI boundary and crashing the onboarding screen. A diagnostics call must
/// never panic itself -- its contract is to report every runtime's status,
/// including failures. `AssertUnwindSafe` is sound here: the captured result is
/// a fully-owned `Ok` value (consumed immediately) or a panic payload we
/// stringify and discard; no shared mutable state is observed post-unwind on
/// the success path.
fn openmls_smoke_runtime_status() -> OpenMlsSmokeRuntimeStatus {
    match catch_unwind(AssertUnwindSafe(run_openmls_smoke_test)) {
        Ok(Ok(ok)) => OpenMlsSmokeRuntimeStatus {
            ok: Some(ok),
            error: None,
        },
        Ok(Err(error)) => OpenMlsSmokeRuntimeStatus {
            ok: None,
            error: Some(error.to_string()),
        },
        Err(payload) => OpenMlsSmokeRuntimeStatus {
            ok: None,
            error: Some(panic_payload_to_string(payload)),
        },
    }
}

/// Runs the OpenMLS Alice/Bob roundtrip and flattens the result into the
/// bridge-friendly `OpenMlsRoundTripRuntimeStatus` (see struct doc). Panic-safe
/// for the same reason as `openmls_smoke_runtime_status` (see its doc).
fn openmls_roundtrip_runtime_status() -> OpenMlsRoundTripRuntimeStatus {
    match catch_unwind(AssertUnwindSafe(run_openmls_alice_bob_roundtrip)) {
        Ok(Ok(ok)) => OpenMlsRoundTripRuntimeStatus {
            ok: Some(ok),
            error: None,
        },
        Ok(Err(error)) => OpenMlsRoundTripRuntimeStatus {
            ok: None,
            error: Some(error.to_string()),
        },
        Err(payload) => OpenMlsRoundTripRuntimeStatus {
            ok: None,
            error: Some(panic_payload_to_string(payload)),
        },
    }
}

/// App-level identity diagnostics. One-shot query; owned `String` fields so
/// the non-opaque bridge translation serializes them cleanly (see struct).
pub fn app_diagnostics() -> AppDiagnostics {
    AppDiagnostics {
        app_name: APP_NAME.to_string(),
        privacy_model: PRIVACY_MODEL.to_string(),
        discovery_model: DISCOVERY_MODEL.to_string(),
        moss_link_mode: MOSS_LINK_MODE.to_string(),
    }
}

/// Per-runtime readiness diagnostics. Delegates to the mosh-core runtimes;
/// persistence reports the process-wide shared store (see
/// [`persistence_status`]).
pub fn native_runtime_status() -> NativeRuntimeStatus {
    NativeRuntimeStatus {
        moss: MossDynamicRuntime::from_default_candidates().status(),
        secure_storage: OsSecureSecretStore::status(),
        persistence: persistence_status(),
        openmls_smoke: openmls_smoke_runtime_status(),
        openmls_roundtrip: openmls_roundtrip_runtime_status(),
    }
}

/// What the loaded moss library reports about itself: its own version
/// string, the last measured RTT to the active DM counterpart, and the
/// field log's current file. See [`MossLibraryInfo`] for the degradation
/// contract.
///
/// The first call in a process also files the version into the field log
/// (ticket #4's sink), so a bug report carries what was running. A
/// process-global flag holds the once-per-process guarantee rather than
/// trusting `diagnostics_log`'s open-file state: the sink may have been
/// rotated or absent, and exactly one line per process is the spec's
/// contract.
pub fn moss_library_info(peer_moss_id: Option<String>) -> MossLibraryInfo {
    let version = library_version().unwrap_or_else(|| MOSS_VERSION_UNKNOWN.to_string());
    log_version_once(&version);
    MossLibraryInfo {
        peer_rtt_ms: peer_rtt_ms(peer_moss_id.as_deref()),
        log_path: dlog::current_log_path().map(|path| path.display().to_string()),
        version,
    }
}

/// The version the loaded library stamps itself with. The answer hangs on
/// the loaded table's `Moss_Version` export, which is process-global (it
/// takes no node), but the accessor lives on `MossNode` in the symbol
/// table -- so this initializes one throwaway node against the default
/// candidates to reach it. Using the shared runtime instead would open
/// the encrypted DB just to read a string; this load is deliberately
/// lighter. `None` when the library predates the symbol or cannot load
/// at all.
fn library_version() -> Option<String> {
    Arc::new(MossFfiRuntime::load_default().ok()?)
        .init_default_node(SUBSTRATE_ROOM, &MossNodeConfig::default())
        .ok()?
        .library_version()
}

/// File the library version into the field log exactly once per process.
/// Never fails: the log's own contract drops lines it cannot persist.
fn log_version_once(version: &str) {
    static LOGGED: AtomicBool = AtomicBool::new(false);
    if !LOGGED.swap(true, Ordering::SeqCst) {
        dlog::write(
            LogLevel::Info,
            kinds::IDENTITY,
            VERSION_LOG_CONTEXT,
            &format!("loaded moss library version {version}"),
        );
    }
}

/// The last measured RTT to `peer_id`, in whole milliseconds (ns -> ms,
/// truncating: a sub-millisecond answer still shows as "0 ms", which is a
/// measurement, not "unknown"). `None` when there is no peer id, no live
/// shared node, or no `Moss_PeerRTT` in the library.
fn peer_rtt_ms(peer_moss_id: Option<&str>) -> Option<u64> {
    let peer_moss_id = peer_moss_id?;
    let node = ensure_shared_resources().ok()?.shared_node.current()?;
    let nanos = node.peer_rtt_ns(peer_moss_id)?;
    Some(nanos / NANOS_PER_MS)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn app_diagnostics_reports_static_identity() {
        let diagnostics = app_diagnostics();
        assert_eq!(diagnostics.app_name, APP_NAME);
        assert_eq!(diagnostics.privacy_model, PRIVACY_MODEL);
        assert_eq!(diagnostics.discovery_model, DISCOVERY_MODEL);
        assert_eq!(diagnostics.moss_link_mode, MOSS_LINK_MODE);
    }

    // Proves the panel contract against the real dlopened library: the
    // prebuilt libmoss.so carries `Moss_Version`, so the version is Some
    // and non-empty (its dev-build stamp "dev" is what an unstamped local
    // build reports); with no peer id there is nothing to measure, so the
    // RTT is honestly None; and the version line lands in the field log on
    // the first call (exactly once per process, per the spec).
    #[test]
    fn moss_library_info_reports_the_loaded_library() {
        let info = moss_library_info(None);
        assert!(!info.version.is_empty(), "the library reports a version");
        assert_ne!(info.version, MOSS_VERSION_UNKNOWN);
        assert_eq!(info.peer_rtt_ms, None, "no peer id, no measurement");

        // The version also lands in the field log (once per process), so a
        // bug report carries what was running. The log path is the same
        // file `current_log_path` reports, which this very call opened.
        let log_path = info.log_path.clone().expect("the version write opened the log");
        let logged = std::fs::read_to_string(&log_path).expect("log file is readable");
        assert!(
            logged.contains(&format!(
                "info identity {VERSION_LOG_CONTEXT} loaded moss library version {}",
                info.version
            )),
            "the version line belongs in the field log: {logged}"
        );

        // A second call answers again from the library, not from the flag:
        // the once-guard gates only the field-log line.
        let again = moss_library_info(None);
        assert_eq!(again.version, info.version);
        assert_eq!(again.log_path, info.log_path);
    }

    #[test]
    fn native_runtime_status_includes_moss_and_secure_storage() {
        let status = native_runtime_status();
        assert_eq!(status.moss.link_mode, MOSS_LINK_MODE);
        assert!(!status.moss.checked_paths.is_empty());
        assert!(!status.secure_storage.backend.is_empty());
        // `available` now depends on whether the shared store opened in this
        // environment, so pin the invariants instead of the value: a live
        // store is always an encrypted one (`Persistence::open` has no
        // unencrypted mode), and exactly one of available/error holds.
        assert_eq!(
            status.persistence.encrypted_at_rest, status.persistence.available,
            "a live persistence instance is always encrypted at rest"
        );
        assert!(
            status.persistence.available ^ status.persistence.error.is_some(),
            "persistence must carry exactly one of available/error"
        );
        assert!(!status.persistence.database.is_empty());
        // The OpenMLS results are flattened into bridge-friendly wrappers:
        // exactly one of `ok`/`error` is set per runtime.
        assert!(
            status.openmls_smoke.ok.is_some() ^ status.openmls_smoke.error.is_some(),
            "openmls_smoke must carry exactly one of ok/error"
        );
        assert!(
            status.openmls_roundtrip.ok.is_some() ^ status.openmls_roundtrip.error.is_some(),
            "openmls_roundtrip must carry exactly one of ok/error"
        );
        if let Some(ok) = &status.openmls_smoke.ok {
            assert_eq!(ok.provider, "openmls_rust_crypto");
            assert!(ok.protected_message_created);
        }
        if let Some(ok) = &status.openmls_roundtrip.ok {
            assert_eq!(ok.provider, "openmls_rust_crypto");
            assert!(ok.welcome_joined);
            assert!(ok.plaintext_roundtrip);
        }
    }

    // Pins the contract of `panic_payload_to_string`: a diagnostics call must
    // surface a usable error message for every panic payload shape Rust allows
    // (`&'static str`, `String`, or an arbitrary non-string payload). The real
    // OpenMLS path does not deterministically panic in a host test, so this
    // focused unit test is the direct proof; the
    // `native_runtime_status_includes_moss_and_secure_storage` test above is
    // the end-to-end proof that `native_runtime_status()` never panics.
    #[test]
    fn panic_payload_to_string_formats_each_payload_shape() {
        // &'static str: the common `panic!("literal")` form.
        let str_payload: Box<dyn Any + Send> = Box::new("Vaults list lock poisoned");
        assert_eq!(
            panic_payload_to_string(str_payload),
            "panic: Vaults list lock poisoned"
        );
        // String: the `panic!("{}", format!(..))` form.
        let string_payload: Box<dyn Any + Send> = Box::new("lock poisoned at step 3".to_string());
        assert_eq!(
            panic_payload_to_string(string_payload),
            "panic: lock poisoned at step 3"
        );
        // Non-string payload: collapses to a generic placeholder so the
        // diagnostics caller still receives a usable `String`.
        let int_payload: Box<dyn Any + Send> = Box::new(42i32);
        assert_eq!(
            panic_payload_to_string(int_payload),
            "panic: unknown panic payload"
        );
    }
}
