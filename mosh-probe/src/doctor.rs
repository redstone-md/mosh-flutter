use crate::*;

pub(super) fn doctor(
    moss_lib: Option<std::path::PathBuf>,
    bind_interface: Option<String>,
    with_node: bool,
    listen_port: u16,
) -> Result<(), Box<dyn std::error::Error>> {
    let role = "doctor";
    report_interfaces(role);

    let status = MossDynamicRuntime::from_default_candidates().status();
    emit(
        role,
        "moss_library",
        serde_json::json!({
            "link_mode": status.link_mode,
            "library_name": status.library_name,
            "available": status.available,
            "checked_paths": status.checked_paths,
            "required_symbols": status.required_symbols,
        }),
    );

    emit(
        role,
        "bind_interface",
        serde_json::json!({
            "requested": bind_interface,
            "effective": mosh_core::moss_ffi::current_bind_interface(),
        }),
    );

    if !with_node {
        return Ok(());
    }

    let runtime = load_runtime(moss_lib)?;
    let store = scratch_store()?;
    let mut dm = PrivateDmRuntime::from_shared(runtime, store, None);
    let created = dm.create_invite(StartSessionRequest {
        display_name: "probe-doctor".to_string(),
        listen_port,
        static_peer: None,
    })?;
    emit(
        role,
        "node_started",
        serde_json::json!({ "mesh_id": created.mesh_id, "listen_address": created.listen_address }),
    );

    // A node needs a moment to bind, probe STUN and pick up its first peers;
    // sampling immediately would only ever report "unknown".
    for _ in 0..20 {
        std::thread::sleep(TICK);
        let snap = dm.poll_session(&created.session_id)?;
        snapshot_line(role, &snap);
    }
    let snap = dm.poll_session(&created.session_id)?;
    emit(
        role,
        "verdict",
        serde_json::json!({ "flags": warn_flags(snap.mesh.as_ref()) }),
    );
    Ok(())
}
