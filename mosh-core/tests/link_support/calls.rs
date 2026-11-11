use mosh_core::api::private_dm;
use serde_json::{json, Value};
use std::sync::Mutex;

/// This headless peer's remote video texture: it keeps what a window's
/// plugin would draw. `mosh-core/src/native_call/texture.rs` has the layout
/// Rust presents into.
#[repr(C)]
struct Recorder {
    present: unsafe extern "C" fn(*const Recorder, *const u8, u32, u32),
    /// The latest frame, counted from the first one presented.
    latest: Mutex<Option<Value>>,
}

static REMOTE: Recorder = Recorder {
    present: record,
    latest: Mutex::new(None),
};

unsafe extern "C" fn record(recorder: *const Recorder, rgba: *const u8, width: u32, height: u32) {
    if width == 0 || height == 0 {
        return;
    }
    // SAFETY: Rust presents into the `REMOTE` it was handed, with
    // `width * height * 4` readable bytes.
    let (recorder, first_pixel) = unsafe { (&*recorder, std::slice::from_raw_parts(rgba, 4)) };
    let mut latest = recorder.latest.lock().unwrap();
    let sequence = latest
        .as_ref()
        .map_or(0, |frame| frame["sequence"].as_u64().unwrap())
        + 1;
    *latest = Some(json!({"sequence":sequence,"width":width,"height":height,
        "first_pixel":first_pixel}));
}

pub(super) fn command(action: &str, session: &str, args: &Value) -> Value {
    let call = args["call_id"].as_str().unwrap_or_default().to_owned();
    let result = match action {
        "call_native_prepare" => {
            return mosh_core::api::native_call::prepare(
                session.into(),
                call,
                false,
                args["camera"].as_bool().unwrap_or(false),
            )
            .and_then(|()| {
                // A texture is accepted once a call is prepared.
                mosh_core::api::native_call::show_video_in(0, &raw const REMOTE as i64)
            })
            .map(|()| json!({}))
            .unwrap_or_else(|error| json!({"error":error}));
        }
        "call_native_snapshot" => {
            return mosh_core::api::native_call::snapshot(session.into(), call)
                .map(|snapshot| serde_json::to_value(snapshot).unwrap())
                .unwrap_or_else(|error| json!({"error":error}));
        }
        "call_native_camera_stall" => {
            return mosh_core::api::native_call::set_choices(
                session.into(),
                call,
                false,
                false,
                true,
                None,
                None,
                Some("test-camera-stall".into()),
                true,
            )
            .map(|()| json!({}))
            .unwrap_or_else(|error| json!({"error":error}));
        }
        "call_native_camera_off" => {
            return mosh_core::api::native_call::set_choices(
                session.into(),
                call,
                false,
                false,
                false,
                None,
                None,
                None,
                false,
            )
            .map(|()| json!({}))
            .unwrap_or_else(|error| json!({"error":error}));
        }
        "call_native_frame" => return json!(*REMOTE.latest.lock().unwrap()),
        "call_start" => {
            return match private_dm::call_start(session.into()) {
                Ok(started) => serde_json::to_value(started).unwrap(),
                Err(error) => json!({"error": format!("{:?}", error.kind)}),
            }
        }
        "call_accept" => private_dm::call_accept(session.into(), call),
        "call_decline" => private_dm::call_decline(session.into(), call, "declined".into()),
        "call_end" => private_dm::call_end(session.into(), call, "hangup".into()),
        _ => panic!("unknown call command"),
    };
    match result {
        Ok(()) => json!({}),
        Err(error) => json!({"error": format!("{:?}", error.kind)}),
    }
}
