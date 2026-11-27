import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/background/android_waiting_owner.dart';
import 'package:mosh/src/features/background/background_commands.dart';
import 'package:mosh/src/platform/android_waiting_platform.dart';

/// Native background events, without the Rust runtime.
class _Commands extends BackgroundCommands {
  final events = StreamController<BigInt>.broadcast();

  @override
  Stream<BigInt> changes() => events.stream;
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late List<String> calls;

  setUp(() {
    calls = [];
    binding.defaultBinaryMessenger
        .setMockMethodCallHandler(AndroidWaitingPlatform.channel, (call) async {
      calls.add(call.method);
      if (call.method == 'enable') {
        throw PlatformException(code: 'WAITING_UNAVAILABLE');
      }
      return {
        'revision': 1,
        'intentRevision': 1,
        'interactive': true,
        'waitingEnabled': true,
        'serviceRunning': false,
        'setupComplete': false,
        'notificationsAllowed': true,
        'batteryExempt': false,
      };
    });
  });
  tearDown(() => binding.defaultBinaryMessenger
      .setMockMethodCallHandler(AndroidWaitingPlatform.channel, null));

  // Regression (CodeAnt PR #8): a refused service start at the end of setup
  // left the owner unattached, with the failure shown nowhere.
  test('a refused service start still attaches and reports the failure',
      () async {
    final platform = AndroidWaitingPlatform();
    final commands = _Commands();
    final owner = AndroidWaitingOwner(platform, commands);
    addTearDown(() {
      owner.dispose();
      platform.dispose();
      commands.events.close();
    });

    await owner.attach(setupCompleted: true);

    expect(owner.attached, isTrue);
    expect(commands.events.hasListener, isTrue);
    expect(owner.failure, isA<PlatformException>());
    expect(calls, contains('startupFailed'));
  });
}
