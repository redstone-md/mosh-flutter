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
    use super::reply;

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
