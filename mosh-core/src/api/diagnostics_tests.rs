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
