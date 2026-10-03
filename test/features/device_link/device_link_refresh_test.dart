import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/device_link/device_link_provider.dart';
import 'package:mosh/src/features/device_link/device_link_state.dart';
import 'package:mosh/src/rust/device_link/types.dart';

import '../../support/device_link_workflow.dart';
import '../../support/scriptable_device_link.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DeviceLinkHarness harness;
  setUp(() async {
    harness = DeviceLinkHarness();
    await harness.ready;
  });
  tearDown(() => harness.dispose());

  test('initial loading skips refresh and refuses commands without native work',
      () async {
    final commands = ScriptableDeviceLink()..hold(DeviceLinkMethod.snapshot);
    final loading = DeviceLinkHarness(commands: commands);
    addTearDown(loading.dispose);
    await loading.controller.refresh();
    await expectLater(
        loading.controller.beginLink(), throwsA(isA<DeviceLinkError>()));
    expect(commands.countOf(DeviceLinkMethod.snapshot), 1);
    expect(commands.countOf(DeviceLinkMethod.beginLink), 0);
    commands.release(DeviceLinkMethod.snapshot);
    await loading.ready;
  });

  testWidgets('production polling uses the same real refresh operation',
      (tester) async {
    harness.container.updateOverrides([
      deviceLinkCommandsProvider.overrideWithValue(harness.commands),
      deviceLinkPollIntervalProvider
          .overrideWithValue(const Duration(milliseconds: 10)),
    ]);
    await harness.ready;
    final before = harness.commands.countOf(DeviceLinkMethod.snapshot);
    await tester.pump(const Duration(milliseconds: 10));
    expect(harness.commands.countOf(DeviceLinkMethod.snapshot), before + 1);
    harness.dispose();
  });

  for (final failRead in [false, true]) {
    test('a stale read cannot overwrite a command, failRead=$failRead',
        () async {
      final response = Completer<DeviceLinkSnapshot>();
      harness.commands.respondNext(DeviceLinkMethod.snapshot, response.future);
      final reading = harness.controller.refresh();
      await harness.controller.joinLink('uri', 'PC');
      if (failRead) {
        response.completeError(StateError('Old read'));
      } else {
        response.complete(setupDeviceSnapshot());
      }
      await reading;
      expect(harness.state.snapshot.confirmationCode, 'ABCDEF123456');
      expect(harness.state.busy, isFalse);
    });
  }

  test('refresh joins an outstanding read and skips a pending command',
      () async {
    final response = Completer<DeviceLinkSnapshot>();
    harness.commands.respondNext(DeviceLinkMethod.snapshot, response.future);
    final reading = harness.controller.refresh();
    await harness.controller.refresh();
    expect(harness.commands.countOf(DeviceLinkMethod.snapshot), 2);
    response.complete(setupDeviceSnapshot());
    await reading;
    harness.commands.hold(DeviceLinkMethod.joinLink);
    final joining = harness.controller.joinLink('uri', 'PC');
    await harness.controller.refresh();
    expect(harness.commands.countOf(DeviceLinkMethod.snapshot), 2);
    harness.commands.release(DeviceLinkMethod.joinLink);
    await joining;
  });

  test('read errors remain retryable through the real refresh', () async {
    final failure = StateError('Snapshot failed');
    harness.commands.failNext(DeviceLinkMethod.snapshot, error: failure);
    await harness.controller.refresh();
    expect(harness.state.readError, same(failure));
    await harness.controller.refresh();
    expect(harness.state.snapshot.phase, DeviceLinkPhase.idle);
    expect(harness.state.readError, isNull);
  });

  for (final failRead in [false, true]) {
    test('an adapter rebuild discards an old read, failRead=$failRead',
        () async {
      final response = Completer<DeviceLinkSnapshot>();
      harness.commands.respondNext(DeviceLinkMethod.snapshot, response.future);
      final reading = harness.controller.refresh();
      final replacement = ScriptableDeviceLink(
          snapshot: setupDeviceSnapshot(devices: 2, canJoin: false));
      harness.replaceCommands(replacement);
      await harness.ready;
      if (failRead) {
        response.completeError(StateError('Old read'));
      } else {
        response.complete(setupDeviceSnapshot());
      }
      await reading;
      expect(harness.state.snapshot.devices, hasLength(2));
      await harness.controller.refresh();
      expect(replacement.countOf(DeviceLinkMethod.snapshot), 2);
    });
  }

  for (final failCommand in [false, true]) {
    test(
        'old action completion cannot clear a replacement action lock '
        'or publish its result, failCommand=$failCommand', () async {
      final response = Completer<DeviceLinkSnapshot>();
      harness.commands.respondNext(DeviceLinkMethod.joinLink, response.future);
      final oldJoin = harness.controller.joinLink('old', 'PC');
      final observed = expectLater(
          oldJoin, failCommand ? throwsA(isA<StateError>()) : completes);
      final replacement = ScriptableDeviceLink(
          snapshot: setupDeviceSnapshot(devices: 2, canJoin: false));
      replacement.hold(DeviceLinkMethod.approve);
      harness.replaceCommands(replacement);
      await harness.ready;
      final approval = harness.controller.approve('new');
      if (failCommand) {
        response.completeError(StateError('Old command'));
      } else {
        response.complete(setupDeviceSnapshot());
      }
      await observed;
      expect(harness.state.busy, isTrue);
      expect(harness.state.actionError, isNull);
      expect(harness.state.snapshot.devices, hasLength(2));
      replacement.release(DeviceLinkMethod.approve);
      await approval;
      expect(harness.state.busy, isFalse);
    });
  }

  test('rebuild during acquisition cannot join using replacement commands',
      () async {
    final acquisition = Completer<String?>();
    final joining = harness.controller.joinFrom(() => acquisition.future, 'PC');
    final replacement = ScriptableDeviceLink();
    harness.replaceCommands(replacement);
    await harness.ready;
    acquisition.complete('late-uri');
    expect(await joining, isFalse);
    expect(replacement.countOf(DeviceLinkMethod.joinLink), 0);
    expect(harness.state.busy, isFalse);
  });

  test('rebuild during continuation cannot invoke its navigation callback',
      () async {
    final response = Completer<DeviceLinkSnapshot>();
    harness.commands.respondNext(DeviceLinkMethod.snapshot, response.future);
    final continuing = harness.controller
        .continueSetup(() async => fail('Old continuation navigated'));
    harness.replaceCommands(ScriptableDeviceLink());
    await harness.ready;
    response.complete(setupDeviceSnapshot());
    expect(await continuing, DeviceLinkExit.blocked);
    expect(harness.state.busy, isFalse);
  });

  test('disposal during acquisition cannot issue a native join', () async {
    final acquisition = Completer<String?>();
    final joining = harness.controller.joinFrom(() => acquisition.future, 'PC');
    harness.dispose();
    acquisition.complete('late-uri');
    expect(await joining, isFalse);
    expect(harness.commands.countOf(DeviceLinkMethod.joinLink), 0);
  });
}
