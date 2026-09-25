//! Diagnostics facade.
//!
//! Surfaces the commands that report app-level health:
//! `app_diagnostics` (aggregate identity snapshot) and `native_runtime_status`
//! (per-runtime readiness), plus `moss_library_info` (spec #5: what the loaded
//! library reports about itself). Plain bridge-friendly structs; no streams.
//! The api facade owns the structs and constants so the bridge (ADR 0010)
//! serializes them without touching a runtime-typed type.

use crate::api::shared_runtime::{database_path, ensure_shared_resources};
use crate::diagnostics_log::{self as dlog, kinds, LogLevel};
use crate::moss_runtime::{MossDynamicRuntime, MossRuntime, MossRuntimeStatus};
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

// App-level identity strings. Kept as named consts (not inline literals) per
// AGENTS.md no-hardcoding rule.
const APP_NAME: &str = "Mosh";
const PRIVACY_MODEL: &str = "OpenMLS private messages over Moss transport";
const DISCOVERY_MODEL: &str = "default public Moss trackers";
const MOSS_LINK_MODE: &str = "dynamic";

// The version answer when the loaded copy predates `Moss_Version`
// (moss < v0.8.17): a stale library beside the binary must read as "unknown",
// not fail the load (AGENTS.md named-constant rule).
const MOSS_VERSION_UNKNOWN: &str = "unknown";
// The field-log context the `moss_library_info` version line carries, so the
// line is greppable by call site rather than by session.
const VERSION_LOG_CONTEXT: &str = "moss_library_info";
// Nanoseconds per millisecond, for the RTT conversion Moss reports in.
const NANOS_PER_MS: u64 = 1_000_000;

// Persistence status: the facade used to answer a flat "not available"
// before the shared store existed; `api::shared_runtime::SHARED_RESOURCES`
// now opens it once per process, so this reports the store the app runs on
// and `persistenceWarningProvider` stops showing a permanent false alarm.
#[cfg(not(target_os = "macos"))]
const PERSISTENCE_BACKEND: &str = "redb+aes-256-gcm+os-keychain";
/// macOS keeps the DEK in a file in the app container (`file_secret_store`).
#[cfg(target_os = "macos")]
const PERSISTENCE_BACKEND: &str = "redb+aes-256-gcm+container-file";
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
/// hang off it (see `moss_library_info` for the degradation contract; the
/// field docs carry the per-field honesty).
#[frb(non_opaque)]
#[derive(serde::Serialize, Clone)]
pub struct MossLibraryInfo {
    /// The version the loaded library stamps itself with, or "unknown".
    pub version: String,
    /// Last measured RTT to the active DM counterpart in ms; `None` = not
    /// measured (no live node, no peer id, or a library without the symbol).
    pub peer_rtt_ms: Option<u64>,
    /// The field log's current file; `None` before the first write opened it.
    pub log_path: Option<String>,
}

/// Reports the process-wide persistence store through `ensure_shared_resources`,
/// the same accessor every runtime uses, so this reports the store the app
/// actually runs on rather than a guess. `encrypted_at_rest` tracks
/// `available`: `Persistence::open` has no unencrypted mode, so a live
/// instance is always an encrypted one.
fn persistence_status() -> PersistenceRuntimeStatus {
    let database = database_path().display().to_string();

    // The three answers share every field but `available`/`error`: the two
    // unavailable branches differ only in their error text (construction
    // failed -- surface the real cause, which is what the warning banner is
    // for -- vs. resources built but nothing owns a DB here).
    let (available, error) = match ensure_shared_resources() {
        Ok(resources) if resources.persistence.is_some() => (true, None),
        Ok(_) => (false, Some(PERSISTENCE_UNAVAILABLE.to_string())),
        Err(error) => (false, Some(error)),
    };
    PersistenceRuntimeStatus {
        backend: PERSISTENCE_BACKEND.to_string(),
        database,
        available,
        // `Persistence::open` has no unencrypted mode, so a live instance is
        // always an encrypted one.
        encrypted_at_rest: available,
        error,
    }
}

/// A panic payload caught by `catch_unwind` as a usable message: the common
/// `&'static str`/`String` shapes render their text; any other payload
/// collapses to a placeholder, so the caller always receives a usable
/// `String`.
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

/// Runs one OpenMLS probe and flattens its outcome into the pair the
/// bridge-friendly wrappers carry: `ok` holds the success snapshot when the
/// probe passed, `error` the message when it panicked or failed. Exactly
/// one of the two is set.
///
/// `catch_unwind` guards against an OpenMLS internal panic (e.g. a poisoned
/// "Vaults list lock" left by an earlier panicked operation) propagating across
/// the FFI boundary and crashing the onboarding screen. A diagnostics call must
/// never panic itself -- its contract is to report every runtime's status,
/// including failures. `AssertUnwindSafe` is sound here: the captured result is
/// a fully-owned `Ok` value (consumed immediately) or a panic payload we
/// stringify and discard; no shared mutable state is observed post-unwind on
/// the success path.
fn flatten_probe<T>(
    outcome: Result<Result<T, crate::openmls_crypto::OpenMlsAdapterError>, Box<dyn Any + Send>>,
) -> (Option<T>, Option<String>) {
    match outcome {
        Ok(Ok(ok)) => (Some(ok), None),
        Ok(Err(error)) => (None, Some(error.to_string())),
        Err(payload) => (None, Some(panic_payload_to_string(payload))),
    }
}

/// The OpenMLS smoke test, flattened and panic-safe (see [`flatten_probe`]).
fn openmls_smoke_runtime_status() -> OpenMlsSmokeRuntimeStatus {
    let (ok, error) = flatten_probe(catch_unwind(AssertUnwindSafe(run_openmls_smoke_test)));
    OpenMlsSmokeRuntimeStatus { ok, error }
}

/// The OpenMLS Alice/Bob roundtrip, flattened and panic-safe (see
/// [`flatten_probe`]).
fn openmls_roundtrip_runtime_status() -> OpenMlsRoundTripRuntimeStatus {
    let (ok, error) = flatten_probe(catch_unwind(AssertUnwindSafe(
        run_openmls_alice_bob_roundtrip,
    )));
    OpenMlsRoundTripRuntimeStatus { ok, error }
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
/// field log's current file. Every value loads through the dynamic-symbol
/// table every other moss call uses and degrades honestly (missing symbol
/// = "unknown"/`None`, never a load failure). The first call in a process
/// also files the version into the field log (ticket #4's sink), so a bug
/// report carries what was running; a process-global flag holds the
/// once-per-process guarantee rather than trusting the sink's open-file
/// state.
pub fn moss_library_info(peer_moss_id: Option<String>) -> MossLibraryInfo {
    let version =
        crate::moss_ffi::library_version_once().unwrap_or_else(|| MOSS_VERSION_UNKNOWN.to_string());
    log_version_once(&version);
    MossLibraryInfo {
        peer_rtt_ms: peer_rtt_ms(peer_moss_id.as_deref()),
        log_path: dlog::current_log_path().map(|path| path.display().to_string()),
        version,
    }
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
        let log_path = info
            .log_path
            .clone()
            .expect("the version write opened the log");
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
