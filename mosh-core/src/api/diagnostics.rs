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

// App-level identity strings. Mirror the previous Tauri shell constants; kept
// as named consts (not inline literals) per AGENTS.md no-hardcoding rule.
const APP_NAME: &str = "Mosh";
const PRIVACY_MODEL: &str = "OpenMLS private messages over Moss transport";
const DISCOVERY_MODEL: &str = "default public Moss trackers";
const MOSS_LINK_MODE: &str = "dynamic";

// Persistence status: the Tauri shell pulled this from a managed
// `PersistenceStatusState` that tracked the live redb instance. The api facade
// has no process owner for persistence (ADR 0010: Tauri-free), and
// `mosh-core::persistence` exposes only `Persistence::open(path)`, which opens
// a real DB — there is no standalone status constructor. The honest standalone
// answer for the bridge smoke call (S2) is therefore "available: false, no
// instance running here". A host that owns a running persistence instance will
// report the richer status out-of-band.
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

/// Builds the not-available persistence status used when no host owns a running
/// redb instance for this api call.
fn persistence_status_without_instance() -> PersistenceRuntimeStatus {
    PersistenceRuntimeStatus {
        backend: PERSISTENCE_BACKEND.to_string(),
        database: "unavailable".to_string(),
        available: false,
        encrypted_at_rest: false,
        error: Some(PERSISTENCE_UNAVAILABLE.to_string()),
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
    match catch_unwind(AssertUnwindSafe(|| run_openmls_smoke_test())) {
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
    match catch_unwind(AssertUnwindSafe(|| run_openmls_alice_bob_roundtrip())) {
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
/// persistence reports not-available because the api facade owns no DB handle.
pub fn native_runtime_status() -> NativeRuntimeStatus {
    NativeRuntimeStatus {
        moss: MossDynamicRuntime::from_default_candidates().status(),
        secure_storage: OsSecureSecretStore::status(),
        persistence: persistence_status_without_instance(),
        openmls_smoke: openmls_smoke_runtime_status(),
        openmls_roundtrip: openmls_roundtrip_runtime_status(),
    }
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

    #[test]
    fn native_runtime_status_includes_moss_and_secure_storage() {
        let status = native_runtime_status();
        assert_eq!(status.moss.link_mode, MOSS_LINK_MODE);
        assert!(!status.moss.checked_paths.is_empty());
        assert!(!status.secure_storage.backend.is_empty());
        assert!(!status.persistence.available);
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
