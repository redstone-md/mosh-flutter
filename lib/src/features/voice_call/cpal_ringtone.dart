import 'package:mosh/src/rust/api/audio_devices.dart' show audioOutputDeviceId;
import 'package:mosh/src/rust/api/voice_call_ringtone.dart'
    show
        VoiceCallRingtone,
        VoiceCallRingtoneKind,
        voiceCallRingtoneStart,
        voiceCallRingtoneStop;

import 'ringtone_player.dart';

class CpalRingtonePlayer implements RingtonePlayer {
  const CpalRingtonePlayer();

  @override
  // The stored output pick (audio-devices.json) resolves inside Rust; an
  // unknown id degrades to the default device there.
  RingtoneHandle start(RingtoneKind kind) =>
      _CpalRingtoneHandle(voiceCallRingtoneStart(
          outputDeviceId: audioOutputDeviceId(),
          kind: switch (kind) {
            RingtoneKind.incoming => VoiceCallRingtoneKind.incoming,
            RingtoneKind.outgoing => VoiceCallRingtoneKind.outgoing,
          }));
}

class _CpalRingtoneHandle implements RingtoneHandle {
  _CpalRingtoneHandle(this._inner);

  final VoiceCallRingtone _inner;
  bool _stopped = false;

  @override
  void stop() {
    if (_stopped) return;
    _stopped = true;
    voiceCallRingtoneStop(ringtone: _inner);
  }
}
