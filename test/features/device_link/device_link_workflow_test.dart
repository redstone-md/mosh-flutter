import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/device_link/device_link_state.dart';
import 'package:mosh/src/rust/device_link/types.dart';

import '../../support/device_link_workflow.dart';
import '../../support/scriptable_device_link.dart';

final _busy = isA<DeviceLinkError>()
    .having((error) => error.kind, 'kind', DeviceLinkErrorKind.busy);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DeviceLinkHarness harness;
  setUp(() async {
    harness = DeviceLinkHarness();
    await harness.ready;
  });
  tearDown(() => harness.dispose());

  test('join rejects overlapping cancellation and setup navigation', () async {
    harness.commands.hold(DeviceLinkMethod.joinLink);
    final joining = harness.controller.joinLink('  mosh://link  ', 'Desktop');
    expect(harness.state.busy, isTrue);
    expect(harness.state.snapshot.phase, DeviceLinkPhase.idle);
    await expectLater(harness.controller.cancel(), throwsA(_busy));
    await expectLater(
        harness.controller.continueSetup(() async => fail('advanced')),
        throwsA(_busy));
    await expectLater(
        harness.controller.backSetup(() async => fail('went back')),
        throwsA(_busy));
    expect(harness.commands.countOf(DeviceLinkMethod.cancel), 0);
    harness.commands.release(DeviceLinkMethod.joinLink);
    await joining;
    expect(harness.state.busy, isFalse);
    expect(harness.state.snapshot.confirmationCode, 'ABCDEF123456');
    expect(harness.commands.imported, ['mosh://link']);
  });

  test('acquisition holds the same lock before any native join', () async {
    final acquisition = Completer<String?>();
    final joining = harness.controller.joinFrom(() => acquisition.future, 'PC');
    expect(harness.state.busy, isTrue);
    expect(harness.commands.countOf(DeviceLinkMethod.joinLink), 0);
    await expectLater(harness.controller.beginLink(), throwsA(_busy));
    acquisition.complete('  mosh://image-or-camera  ');
    expect(await joining, isTrue);
    expect(harness.commands.imported, ['mosh://image-or-camera']);
    expect(harness.state.busy, isFalse);
  });

  test('dismissing acquisition releases the lock without a native join',
      () async {
    expect(await harness.controller.joinFrom(() async => null, 'PC'), isFalse);
    expect(harness.commands.countOf(DeviceLinkMethod.joinLink), 0);
    expect(harness.state.busy, isFalse);
    expect(harness.state.snapshot.phase, DeviceLinkPhase.idle);
  });

  test('acquisition failure remains visible through refresh and allows retry',
      () async {
    const failure = FormatException('Image decoding failed');
    await expectLater(
        harness.controller.joinFrom(() async => throw failure, 'PC'),
        throwsA(same(failure)));
    expect(harness.state.actionError, same(failure));
    expect(harness.state.busy, isFalse);
    await harness.controller.refresh();
    expect(harness.state.actionError, same(failure));
    harness.commands.failNext(DeviceLinkMethod.snapshot);
    await harness.controller.refresh();
    expect(harness.state.actionError, same(failure));
    expect(harness.state.readError, isNotNull);
    await harness.controller.refresh();
    expect(harness.state.actionError, same(failure));
    await harness.controller.joinFrom(() async => 'mosh://retry', 'PC');
    expect(harness.state.actionError, isNull);
    expect(harness.state.snapshot.confirmationCode, 'ABCDEF123456');
  });

  test('all native commands retain real workflow state and typed arguments',
      () async {
    await harness.controller.beginLink();
    expect(harness.state.snapshot.phase, DeviceLinkPhase.showingQr);
    await harness.controller.approve('CODE');
    expect(harness.state.connected, isTrue);
    expect(harness.commands.lastCall(DeviceLinkMethod.approve)!.arg('code'),
        'CODE');
    await harness.controller.revoke('device-1');
    expect(harness.state.snapshot.devices, hasLength(1));
    expect(harness.commands.lastCall(DeviceLinkMethod.revoke)!.arg('deviceId'),
        'device-1');
    expect(harness.state.busy, isFalse);
  });

  test('setup continuation keeps the lock until the progress save completes',
      () async {
    final saved = Completer<void>();
    final continuing = harness.controller.continueSetup(() => saved.future);
    await Future<void>.delayed(Duration.zero);
    expect(harness.state.busy, isTrue);
    await expectLater(harness.controller.joinLink('uri', 'PC'), throwsA(_busy));
    saved.complete();
    expect(await continuing, DeviceLinkExit.ready);
    expect(harness.commands.cancellations, 0);
    expect(harness.state.busy, isFalse);
  });

  test('setup save failure releases the lock without becoming a link error',
      () async {
    final failure = StateError('Disk failed');
    await expectLater(
        harness.controller.continueSetup(() async => throw failure),
        throwsA(same(failure)));
    expect(harness.state.busy, isFalse);
    expect(harness.state.actionError, isNull);
    expect(await harness.controller.continueSetup(() async {}),
        DeviceLinkExit.ready);
  });

  test('pending join settles once before continuing setup', () async {
    await harness.controller.joinLink('uri', 'PC');
    var advances = 0;
    expect(await harness.controller.continueSetup(() async => advances++),
        DeviceLinkExit.ready);
    expect(harness.commands.cancellations, 1);
    expect(advances, 1);
    expect(harness.state.snapshot.role, isNull);
  });

  test('failed cancellation retains proof and can retry', () async {
    await harness.controller.joinLink('uri', 'PC');
    final failure = StateError('Cancel failed');
    harness.commands.failNext(DeviceLinkMethod.cancel, error: failure);
    await expectLater(harness.controller.cancel(), throwsA(same(failure)));
    expect(harness.state.snapshot.confirmationCode, 'ABCDEF123456');
    expect(harness.state.actionError, same(failure));
    expect(await harness.controller.cancel(), DeviceLinkExit.ready);
    expect(harness.state.actionError, isNull);
  });

  test('approval winning cancellation requires a deliberate continuation',
      () async {
    await harness.controller.joinLink('uri', 'PC');
    harness.commands.snapshotAfterCancel = setupDeviceSnapshot(
        phase: DeviceLinkPhase.failed, canJoin: false, devices: 2);
    var advances = 0;
    expect(await harness.controller.continueSetup(() async => advances++),
        DeviceLinkExit.linkApproved);
    expect(advances, 0);
    expect(harness.state.connected, isTrue);
    expect(await harness.controller.continueSetup(() async => advances++),
        DeviceLinkExit.ready);
    expect(advances, 1);
  });

  for (final phase in [
    DeviceLinkPhase.delivering,
    DeviceLinkPhase.awaitingConfirmation,
  ]) {
    test('cancellation returning $phase prevents navigation', () async {
      await harness.controller.joinLink('uri', 'PC');
      harness.commands.snapshotAfterCancel =
          setupDeviceSnapshot(phase: phase, role: DeviceLinkRole.joining);
      expect(
          await harness.controller.continueSetup(() async => fail('advanced')),
          DeviceLinkExit.blocked);
      expect(harness.state.snapshot.phase, phase);
    });
  }

  test('fresh native delivery blocks cancellation and continuation', () async {
    harness.commands.publish(setupDeviceSnapshot(
        phase: DeviceLinkPhase.delivering, role: DeviceLinkRole.joining));
    expect(await harness.controller.cancel(), DeviceLinkExit.blocked);
    expect(await harness.controller.continueSetup(() async => fail('advanced')),
        DeviceLinkExit.blocked);
    expect(harness.commands.cancellations, 0);
  });

  test('Back preserves a pending link and holds the lock during its save',
      () async {
    await harness.controller.joinLink('uri', 'PC');
    expect(await harness.controller.backSetup(() async => fail('went back')),
        isFalse);
    expect(harness.commands.cancellations, 0);
    await harness.controller.cancel();
    final saved = Completer<void>();
    final backing = harness.controller.backSetup(() => saved.future);
    await Future<void>.delayed(Duration.zero);
    expect(harness.state.busy, isTrue);
    saved.complete();
    expect(await backing, isTrue);
    expect(harness.state.busy, isFalse);
  });
}
