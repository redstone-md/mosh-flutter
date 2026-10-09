use super::types::Device;

/// Record IDs are native; CPAL output IDs include a host prefix. Only select an
/// identifier found in the engine's current inventory; stale picks use default.
pub(super) fn initial_pick(stored: Option<&str>, devices: &[Device]) -> Option<String> {
    let stored = stored?;
    let native = canonical(stored);
    devices
        .iter()
        .find(|device| device.id == stored || device.id == native)
        .map(|device| device.id.clone())
}

pub(super) fn canonical(stored: &str) -> &str {
    ["coreaudio:", "wasapi:", "alsa:", "pulseaudio:"]
        .iter()
        .find_map(|prefix| stored.strip_prefix(prefix))
        .unwrap_or(stored)
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn persisted_host_ids_select_the_same_native_device_without_name_guessing() {
        let devices = vec![Device {
            id: "device:uid".into(),
            name: "Speaker".into(),
            stable: true,
        }];
        for pick in ["device:uid", "wasapi:device:uid", "coreaudio:device:uid"] {
            assert_eq!(
                initial_pick(Some(pick), &devices),
                Some("device:uid".into())
            );
        }
        assert_eq!(initial_pick(Some("coreaudio:missing"), &devices), None);
        assert_eq!(initial_pick(Some("Speaker"), &devices), None);
        assert_eq!(initial_pick(None, &devices), None);
    }
}
