// Audio-device picks: the app-level state for which input (mic) and
// output (speaker) the voice paths use, backed by mosh-core's
// `audio-devices.json` store (frb get/set) and two device enumerators.
//
// The Rust store is the single source of truth — the same file
// `voice_call_playback_start` / `voice_call_ringtone_start` resolve their
// output device from, and the input pick Dart hands to `record`'s
// `RecordConfig.device`. This provider is the Riverpod-facing cache:
// a Notifier holding the current picks (sync-loaded from the frb
// getters, which are `#[frb(sync)]` file reads), a setter that persists
// both picks in one write, and two enumerators exposed as injectable
// functions so tests stub the seams without a native plugin.
//
// Server state (device lists) is NOT held here: lists are read at
// settings-screen open (FutureProvider below), because device sets
// change with hardware, not with app state.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mosh/src/rust/api/audio_devices.dart' as api
    show
        AudioDeviceInfo,
        audioInputDeviceId,
        audioOutputDeviceId,
        listOutputDevices,
        setAudioDevices;
import 'package:record/record.dart' show AudioRecorder, InputDevice;

/// The stored picks; `null` means "system default". Immutable value.
class AudioDevicePicks {
  const AudioDevicePicks({this.inputDeviceId, this.outputDeviceId});

  final String? inputDeviceId;
  final String? outputDeviceId;
}

/// Enumerates capture devices through the real `record` plugin. Injected
/// so tests stub the seam instead of a native mic.
typedef InputDeviceEnumerator = Future<List<InputDevice>> Function();

Future<List<InputDevice>> recordListInputDevices() async =>
    AudioRecorder().listInputDevices();

/// The input-device enumerator seam. Tests override with a stub.
final inputDeviceEnumeratorProvider =
    Provider<InputDeviceEnumerator>((ref) => recordListInputDevices);

/// Enumerates output devices through mosh-core's cpal surface. Sync frb
/// call, wrapped in a Future for provider uniformity.
final outputDevicesProvider = FutureProvider<List<api.AudioDeviceInfo>>(
    (ref) async => api.listOutputDevices());

/// The input devices for the settings dropdown; the same enumerator seam
/// the capture path reads its pick from.
final inputDevicesProvider = FutureProvider<List<InputDevice>>(
    (ref) async => ref.read(inputDeviceEnumeratorProvider)());

/// The app-level picks. `build` seeds from the Rust store (a sync file
/// read, so the initial value is available in the first frame); `set`
/// persists both picks in one write and updates the cache. Kept as a
/// plain Notifier: the picks are small, sync-loadable, and read at call
/// start / composer start — no async lifecycle to model.
final audioDevicePicksProvider =
    NotifierProvider<AudioDevicePicksNotifier, AudioDevicePicks>(
        AudioDevicePicksNotifier.new);

class AudioDevicePicksNotifier extends Notifier<AudioDevicePicks> {
  @override
  AudioDevicePicks build() => AudioDevicePicks(
        inputDeviceId: api.audioInputDeviceId(),
        outputDeviceId: api.audioOutputDeviceId(),
      );

  /// Persists BOTH picks in one write (the Rust store's contract: a
  /// partial update must not lose the other field) and refreshes the
  /// cache so listeners (the settings dropdowns, the capture paths)
  /// see the new pick without re-reading the file.
  void set({String? inputDeviceId, String? outputDeviceId}) {
    api.setAudioDevices(
      inputDeviceId: inputDeviceId,
      outputDeviceId: outputDeviceId,
    );
    state = AudioDevicePicks(
      inputDeviceId: inputDeviceId,
      outputDeviceId: outputDeviceId,
    );
  }
}
