//! On phones the app's platform code owns call audio routes and the camera;
//! the call owner asks it through one JSON command (`devices`, `select`,
//! `audioStop`, `cameras`, `cameraStart`, `cameraStop`). Android answers over
//! JNI (`MoshMedia.kt`), iOS through the function its runner registers
//! (`ios/Runner/CallMedia.swift`). The boundary carries device metadata and
//! commands, never media.
#[cfg(target_os = "android")]
pub(crate) use crate::android::media::command;
#[cfg(target_os = "ios")]
pub(crate) use ios::command;
use serde_json::Value;

#[cfg(target_os = "ios")]
#[path = "mobile_media/ios.rs"]
mod ios;

/// Writes where call audio plays to the field log each time the platform
/// reports a new route or volume. A call polls `devices` every two seconds,
/// so a volume press or a reroute shows up within that.
#[cfg(target_os = "ios")]
fn log_route(reply: &Value) {
    use crate::diagnostics_log::{kinds, write, LogLevel};
    static LAST: std::sync::Mutex<Option<Value>> = std::sync::Mutex::new(None);
    let mut last = LAST.lock().unwrap_or_else(|error| error.into_inner());
    if let Some(route) = new_route(&mut last, reply) {
        write(
            LogLevel::Info,
            kinds::VOICE,
            "",
            &format!("call audio route: {route}"),
        );
    }
}

/// The reply's route when it differs from the last one seen.
#[cfg(any(test, target_os = "ios"))]
fn new_route<'a>(last: &mut Option<Value>, reply: &'a Value) -> Option<&'a Value> {
    let route = reply.get("route")?;
    if last.as_ref() == Some(route) {
        return None;
    }
    *last = Some(route.clone());
    Some(route)
}

/// The platform's answer, or the error it reported.
pub(crate) fn reply(response: &str) -> Result<Value, String> {
    let result: Value = serde_json::from_str(response).map_err(|error| error.to_string())?;
    if let Some(error) = result["error"].as_str() {
        return Err(error.into());
    }
    Ok(result)
}

#[cfg(test)]
mod tests {
    use super::{new_route, reply};
    use serde_json::json;

    #[test]
    fn a_route_is_reported_once_until_it_changes() {
        let mut last = None;
        let receiver = json!({"outputs": [], "route": {"outputs": ["Receiver"], "volume": 0.5}});
        let louder = json!({"route": {"outputs": ["Receiver"], "volume": 0.75}});
        assert_eq!(new_route(&mut last, &receiver), Some(&receiver["route"]));
        assert_eq!(new_route(&mut last, &receiver), None);
        assert_eq!(new_route(&mut last, &json!({"cameras": []})), None);
        assert_eq!(new_route(&mut last, &louder), Some(&louder["route"]));
    }

    #[test]
    fn a_reported_error_fails_the_command() {
        assert_eq!(reply(r#"{"error":"CameraBusy"}"#), Err("CameraBusy".into()));
        assert_eq!(
            reply(r#"{"outputs":[]}"#).unwrap()["outputs"],
            serde_json::json!([])
        );
        assert!(reply("not json").is_err());
    }
}
