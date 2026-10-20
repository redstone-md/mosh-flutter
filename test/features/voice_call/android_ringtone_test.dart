import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/voice_call/android_ringtone.dart';
import 'package:mosh/src/features/voice_call/ringtone_player.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <MethodCall>[];
  final delayedStart = Completer<void>();
  setUp(() {
    calls.clear();
    binding.defaultBinaryMessenger
        .setMockMethodCallHandler(AndroidRingtonePlayer.channel, (call) async {
      calls.add(call);
      if (call.method == 'start') await delayedStart.future;
      return null;
    });
  });
  tearDown(() => binding.defaultBinaryMessenger
      .setMockMethodCallHandler(AndroidRingtonePlayer.channel, null));

  test('answer stops a preparing ring; an old handle cannot stop a new ring',
      () async {
    const player = AndroidRingtonePlayer();
    final old = player.start(RingtoneKind.incoming);
    old.stop();
    old.stop();
    final current = player.start(RingtoneKind.outgoing);
    await Future<void>.delayed(Duration.zero);
    expect(calls.map((c) => c.method), ['start', 'stop', 'start']);
    final oldId = (calls.first.arguments as Map)['id'];
    final newId = (calls.last.arguments as Map)['id'];
    expect((calls[1].arguments as Map)['id'], oldId);
    expect(newId, isNot(oldId));
    delayedStart.complete();
    await Future<void>.delayed(Duration.zero);
    old.stop();
    current.stop();
    await Future<void>.delayed(Duration.zero);
    expect((calls.last.arguments as Map)['id'], newId);
    expect(calls.map((c) => c.method), ['start', 'stop', 'start', 'stop']);
  });
}
