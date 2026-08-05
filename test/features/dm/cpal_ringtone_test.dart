import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/src/features/dm/cpal_ringtone.dart';
import 'package:mosh/src/features/dm/ringtone_player.dart';

void main() {
  test('production ringtone preserves the RingtonePlayer seam', () {
    const RingtonePlayer player = CpalRingtonePlayer();
    expect(player, isA<RingtonePlayer>());
    expect(player.start, isA<RingtoneHandle Function()>());
  });

  test('isolated production seam test does not open an audio device', () {
    const player = CpalRingtonePlayer();
    expect(player, isNot(isA<NoopRingtonePlayer>()));
  });
}
