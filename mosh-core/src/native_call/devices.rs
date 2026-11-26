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

    /// Selects the engine's fallback through `select` after a picked device
    /// disappeared ([`drop_missing`]). The engine no longer runs the pick, so
    /// the next [`Selection::apply`] selects it again.
    pub fn fall_back(&mut self, select: impl FnOnce() -> Result<(), String>) -> Result<(), String> {
        self.picked = None;
        select()
    }
}

/// Drops the picks that left the engine's inventory: a missing input turns
/// the microphone off, a missing output falls back to the default. Whether
/// the engine has to fall back.
pub(super) fn drop_missing(choices: &mut Choices, inputs: &[Device], outputs: &[Device]) -> bool {
    let absent = |devices: &[Device], id: &String| !devices.iter().any(|d| &d.id == id);
    let input_missing =
        inputs.is_empty() || choices.input.as_ref().is_some_and(|id| absent(inputs, id));
    let microphone_lost = input_missing && choices.microphone;
    if microphone_lost {
        choices.microphone = false;
    }
    let output_lost = choices
        .output
        .as_ref()
        .is_some_and(|id| absent(outputs, id));
    if output_lost {
        choices.output = None;
    }
    microphone_lost || output_lost
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
    fn a_returning_input_is_selected_again_after_the_engine_fell_back() {
        let mic = Device {
            id: "mic".into(),
            name: "Mic".into(),
            stable: true,
        };
        let mut selection = Selection::default();
        let mut choices = Choices {
            microphone: true,
            input: Some("mic".into()),
            ..Default::default()
        };
        let mut selects = 0;
        let mut pick = |selection: &mut Selection, choices: &Choices| {
            selection.apply(choices, || {
                selects += 1;
                Ok([true; 2])
            })
        };
        assert!(pick(&mut selection, &choices).unwrap());
        assert!(drop_missing(&mut choices, &[], &[]));
        assert!(!choices.microphone);
        selection.fall_back(|| Ok(())).unwrap();
        // The microphone is plugged back in and switched on again.
        choices.microphone = true;
        assert!(!drop_missing(&mut choices, &[mic], &[]));
        assert!(pick(&mut selection, &choices).unwrap());
        assert_eq!(selects, 2, "the engine stayed on its fallback input");
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
