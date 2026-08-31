// Production RingtonePlayer backed by mosh-core's synchronous CPAL stream.

library;

import 'package:mosh/src/rust/api/voice_call_ringtone.dart'
    show VoiceCallRingtone, voiceCallRingtoneStart, voiceCallRingtoneStop;

import 'ringtone_player.dart';

class CpalRingtonePlayer implements RingtonePlayer {
  const CpalRingtonePlayer();

  @override
  RingtoneHandle start() => _CpalRingtoneHandle(voiceCallRingtoneStart());
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
