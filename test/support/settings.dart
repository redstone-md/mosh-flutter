import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:mosh/src/features/voice_call/ringtone_player.dart';
import 'package:mosh/src/rust/api/audio_devices.dart';
import 'package:mosh/src/state/audio_device_picks_provider.dart';
import 'package:mosh/src/state/voice_call_orchestrator_provider.dart';
import 'package:record/record.dart' show InputDevice;

/// Audio choices without native hardware or storage, using the real providers.
class MemoryAudioPicks extends AudioDevicePicksNotifier {
  MemoryAudioPicks([this.initial = const AudioDevicePicks()]);

  final AudioDevicePicks initial;
  bool failWrite = false;

  @override
  AudioDevicePicks build() => initial;

  @override
  void set({String? inputDeviceId, String? outputDeviceId}) {
    if (failWrite) throw StateError('scripted storage failure');
    state = AudioDevicePicks(
      inputDeviceId: inputDeviceId,
      outputDeviceId: outputDeviceId,
    );
  }
}

class RecordingSettingsRingtone implements RingtonePlayer, RingtoneHandle {
  int starts = 0;
  int stops = 0;
  bool failStart = false;

  @override
  RingtoneHandle start() {
    if (failStart) throw StateError('scripted output failure');
    starts++;
    return this;
  }

  @override
  void stop() => stops++;
}

List<Override> settingsAudioOverrides({
  MemoryAudioPicks? picks,
  RecordingSettingsRingtone? ringtone,
  Future<List<InputDevice>> Function()? inputs,
}) =>
    [
      audioDevicePicksProvider.overrideWith(() => picks ?? MemoryAudioPicks()),
      inputDevicesProvider.overrideWith((ref) async => inputs == null
          ? [
              const InputDevice(id: 'mic', label: 'USB microphone'),
            ]
          : await inputs()),
      outputDevicesProvider.overrideWith((ref) async => [
            const AudioDeviceInfo(id: 'speaker', name: 'Desk speakers'),
          ]),
      if (ringtone != null) ringtonePlayerProvider.overrideWithValue(ringtone),
    ];
