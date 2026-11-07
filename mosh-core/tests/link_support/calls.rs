use mosh_core::api::private_dm;
use serde_json::{json, Value};

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
        "call_native_frame" => {
            return mosh_core::api::native_call::frame(session.into(), call, false, 0)
                .map(|frame| {
                    frame.map(|frame| {
                        json!({"sequence":frame.sequence,
                    "width":frame.width,"height":frame.height,"rgba_bytes":frame.pixels.len(),
                    "first_pixel":frame.pixels.get(..4),"source_age_ms":frame.source_age_ms})
                    })
                })
                .map(|frame| json!(frame))
                .unwrap_or_else(|error| json!({"error":error}));
        }
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
