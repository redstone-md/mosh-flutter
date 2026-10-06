import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import '../../support/voice_call_fakes.dart';

void main() {
  test('capture fake joins pending stop and stops each handle only once',
      () async {
    final stopping = Completer<void>();
    addTearDown(() {
      if (!stopping.isCompleted) stopping.complete();
    });
    final factory = RecordingCapture()..stopping = stopping;
    final handle = await factory.start((_) {});
    final first = handle.stop();
    final second = handle.stop();
    var finished = false;
    unawaited(second.then((_) => finished = true));
    await Future<void>.delayed(Duration.zero);
    expect(factory.stops, 1);
    expect(finished, isFalse);
    stopping.complete();
    await Future.wait([first, second]);
    await handle.stop();
    expect(factory.stops, 1);
    final replacement = await factory.start((_) {});
    await replacement.stop();
    expect(factory.stops, 2);
  });

  test('playback fake stops each handle only once', () async {
    final factory = RecordingPlayback();
    final handle = await factory.start();
    await handle.stop();
    await handle.stop();
    expect(factory.stops, 1);
    final replacement = await factory.start();
    await replacement.stop();
    expect(factory.stops, 2);
  });
}
