use super::types::{Choices, Device};

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

/// The audio devices the engine last selected, both usable. Selecting
/// restarts the recording and playout devices, so only a new pick selects;
/// the microphone and camera switches leave the devices running.
#[derive(Default)]
pub(super) struct Selection {
    picked: Option<(Option<String>, Option<String>)>,
}

impl Selection {
    /// Selects the devices of `choices` through `select`, which tells whether
    /// the input and the output are usable, unless they are the ones in use.
    /// Whether the input is usable. A refused device is not remembered, so
    /// the next switch tries the pick again.
    pub fn apply(
        &mut self,
        choices: &Choices,
        select: impl FnOnce() -> Result<[bool; 2], String>,
    ) -> Result<bool, String> {
        let pick = (choices.input.clone(), choices.output.clone());
        if self.picked.as_ref() == Some(&pick) {
            return Ok(true);
        }
        self.picked = None;
        let [input_ok, output_ok] = select()?;
        if input_ok && output_ok {
            self.picked = Some(pick);
        }
        Ok(input_ok)
    }
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

    #[test]
    fn toggling_the_microphone_or_camera_does_not_select_devices_again() {
        let mut selection = Selection::default();
        let mut selected = 0;
        let mut choices = Choices {
            microphone: true,
            input: Some("mic".into()),
            ..Default::default()
        };
        let mut apply = |choices: &Choices| {
            selection.apply(choices, || {
                selected += 1;
                Ok([true; 2])
            })
        };
        assert!(apply(&choices).unwrap());
        choices.microphone = false;
        assert!(apply(&choices).unwrap());
        choices.camera = true;
        assert!(apply(&choices).unwrap());
        choices.output = Some("speaker".into());
        assert!(apply(&choices).unwrap());
        assert_eq!(selected, 2);
    }

    #[test]
    fn a_failed_or_refused_selection_is_tried_again_on_the_next_switch() {
        let mut selection = Selection::default();
        let choices = Choices::default();
        assert!(selection.apply(&choices, || Err("engine".into())).is_err());
        assert!(!selection.apply(&choices, || Ok([false, true])).unwrap());
        assert!(selection.apply(&choices, || Ok([true, false])).unwrap());
        assert!(selection.apply(&choices, || Ok([true; 2])).unwrap());
        assert!(selection
            .apply(&choices, || panic!("selected the same devices again"))
            .unwrap());
    }
}
