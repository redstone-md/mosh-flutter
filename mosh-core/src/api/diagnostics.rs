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
use crate::openmls_crypto::{
    run_openmls_alice_bob_roundtrip, run_openmls_smoke_test, OpenMlsRoundTripStatus,
    OpenMlsSmokeStatus,
};
use crate::persistence::PersistenceRuntimeStatus;
use crate::secure_storage::{OsSecureSecretStore, SecureStorageStatus};

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
#[derive(serde::Serialize, Clone)]
pub struct AppDiagnostics {
    pub app_name: &'static str,
    pub privacy_model: &'static str,
    pub discovery_model: &'static str,
    pub moss_link_mode: &'static str,
}

/// Per-runtime readiness report, one row of `native_runtime_status`. Carries
/// statuses produced by the mosh-core runtimes; persistence is a not-available
/// marker when no host owns a running instance (see module doc).
#[derive(serde::Serialize, Clone)]
pub struct NativeRuntimeStatus {
    pub moss: MossRuntimeStatus,
    pub secure_storage: SecureStorageStatus,
    pub persistence: PersistenceRuntimeStatus,
    pub openmls_smoke: Result<OpenMlsSmokeStatus, String>,
    pub openmls_roundtrip: Result<OpenMlsRoundTripStatus, String>,
}

/// Builds the not-available persistence status used when no host owns a running
/// redb instance for this api call.
fn persistence_status_without_instance() -> PersistenceRuntimeStatus {
    PersistenceRuntimeStatus {
        backend: PERSISTENCE_BACKEND,
        database: "unavailable".to_string(),
        available: false,
        encrypted_at_rest: false,
        error: Some(PERSISTENCE_UNAVAILABLE.to_string()),
    }
}

/// App-level identity diagnostics. One-shot query; no lifetime params, all
/// fields are `'static` so the bridge serializes it cleanly.
pub fn app_diagnostics() -> AppDiagnostics {
    AppDiagnostics {
        app_name: APP_NAME,
        privacy_model: PRIVACY_MODEL,
        discovery_model: DISCOVERY_MODEL,
        moss_link_mode: MOSS_LINK_MODE,
    }
}

/// Per-runtime readiness diagnostics. Delegates to the mosh-core runtimes;
/// persistence reports not-available because the api facade owns no DB handle.
pub fn native_runtime_status() -> NativeRuntimeStatus {
    NativeRuntimeStatus {
        moss: MossDynamicRuntime::from_default_candidates().status(),
        secure_storage: OsSecureSecretStore::status(),
        persistence: persistence_status_without_instance(),
        openmls_smoke: run_openmls_smoke_test().map_err(|error| error.to_string()),
        openmls_roundtrip: run_openmls_alice_bob_roundtrip().map_err(|error| error.to_string()),
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
    }
}
