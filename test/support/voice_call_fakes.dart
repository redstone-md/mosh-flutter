import 'package:mosh/src/features/voice_call/ringtone_player.dart';

class RecordingRingtone implements RingtonePlayer {
  int starts = 0;
  int stops = 0;
  final kinds = <RingtoneKind>[];
  @override
  RingtoneHandle start(RingtoneKind kind) {
    starts++;
    kinds.add(kind);
    return _Ring(() => stops++);
  }
}

class _Ring implements RingtoneHandle {
  _Ring(this.onStop);
  final void Function() onStop;
  @override
  void stop() => onStop();
}
