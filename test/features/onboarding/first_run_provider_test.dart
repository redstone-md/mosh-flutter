import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/device_link/device_link_provider.dart';
import 'package:mosh/src/features/onboarding/first_run_profile.dart';
import 'package:mosh/src/features/onboarding/first_run_provider.dart';
import 'package:mosh/src/rust/device_link/types.dart';
import 'package:mosh/src/state/gateway_provider.dart';
import 'package:mosh/src/state/session_providers.dart';

import '../../support/message_builders.dart';
import '../../support/scriptable_bridge.dart';
import '../../support/scriptable_device_link.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late FirstRunStore store;
  late ScriptableBridge bridge;
  late ScriptableDeviceLink link;
  late ProviderContainer container;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('mosh-setup-provider-');
    store = FirstRunStore(directory);
    bridge = ScriptableBridge();
    link = ScriptableDeviceLink();
    container = ProviderContainer(retry: (_, __) => null, overrides: [
      firstRunStoreProvider.overrideWithValue(store),
      bridgeFacadeProvider.overrideWithValue(bridge),
      deviceLinkCommandsProvider.overrideWithValue(link),
      deviceLinkPollIntervalProvider.overrideWithValue(null),
    ]);
  });
  tearDown(() async {
    container.dispose();
    await directory.delete(recursive: true);
  });

  test('fresh installation requires setup and seeds the saved name on reload',
      () async {
    expect((await container.read(firstRunProfileProvider.future)).completed,
        isFalse);
    final controller = container.read(firstRunProfileProvider.notifier);
    await controller.saveName('  Juno  ', advance: true);
    expect(container.read(inviteFlowProvider).displayName, 'Juno');
    container.invalidate(firstRunProfileProvider);
    final restored = await container.read(firstRunProfileProvider.future);
    expect(restored.step, SetupStep.device);
    expect(restored.displayName, 'Juno');
  });

  test('conversation history skips setup', () async {
    bridge.seedSessions([TestSnapshots.dm(sessionId: 'old')]);
    expect((await container.read(firstRunProfileProvider.future)).completed,
        isTrue);
    expect((await store.read())!.completed, isTrue);
  });

  test('known conversation history skips setup despite another read failing',
      () async {
    bridge.seedSessions([TestSnapshots.dm(sessionId: 'old')]);
    bridge.failNext(BridgeMethod.listGroups);
    expect((await container.read(firstRunProfileProvider.future)).completed,
        isTrue);
  });

  test('known linked devices skip setup despite a history read failing',
      () async {
    link.current = setupDeviceSnapshot(devices: 2);
    bridge.failNext(BridgeMethod.listGroups);
    expect((await container.read(firstRunProfileProvider.future)).completed,
        isTrue);
  });

  for (final identity in [
    setupDeviceSnapshot(devices: 2),
    setupDeviceSnapshot(canJoin: false),
    setupDeviceSnapshot(revoked: true),
    setupDeviceSnapshot(
        phase: DeviceLinkPhase.awaitingConfirmation,
        role: DeviceLinkRole.joining),
  ]) {
    test(
        'existing identity ${identity.phase}/${identity.canJoin}/'
        '${identity.revoked}/${identity.devices.length} skips setup', () async {
      link.current = identity;
      expect((await container.read(firstRunProfileProvider.future)).completed,
          isTrue);
      expect(link.cancellations, 0);
    });
  }

  test('a restored draft takes precedence over recently linked devices',
      () async {
    await store.write(
        const FirstRunProfile(displayName: 'Juno', step: SetupStep.device));
    link.current = setupDeviceSnapshot(devices: 2);
    final profile = await container.read(firstRunProfileProvider.future);
    expect(profile.completed, isFalse);
    expect(profile.step, SetupStep.device);
    expect(bridge.calls, isEmpty);
  });

  test('a failed history read cannot mark the installation as fresh', () async {
    bridge.failNext(BridgeMethod.listGroups);
    await expectLater(
        container.read(firstRunProfileProvider.future), throwsException);
    expect(await store.read(), isNull);
    container.invalidate(firstRunProfileProvider);
    expect((await container.read(firstRunProfileProvider.future)).completed,
        isFalse);
  });

  test('name edits preserve invitation state and reject invalid names',
      () async {
    await container.read(firstRunProfileProvider.future);
    final invite = container.read(inviteFlowProvider.notifier);
    invite.setListenPort(42);
    invite.setStaticPeer('local-test');
    final controller = container.read(firstRunProfileProvider.notifier);
    await controller.saveName('Juno');
    expect(container.read(inviteFlowProvider).listenPort, 42);
    expect(container.read(inviteFlowProvider).staticPeer, 'local-test');
    await expectLater(controller.saveName('  '), throwsFormatException);
    await expectLater(controller.saveName('a' * 65), throwsFormatException);
  });

  test('cannot advance until a name is saved', () async {
    await container.read(firstRunProfileProvider.future);
    await expectLater(
        container
            .read(firstRunProfileProvider.notifier)
            .goTo(SetupStep.network),
        throwsStateError);
  });

  test('completion is durable before restart and returns to chats afterward',
      () async {
    await container.read(firstRunProfileProvider.future);
    final controller = container.read(firstRunProfileProvider.notifier);
    await controller.saveName('Juno', advance: true);
    await controller.goTo(SetupStep.network);
    await controller.finish(() async {
      expect((await store.read())!.completed, isTrue);
      expect(container.read(firstRunProfileProvider).requireValue.completed,
          isFalse);
    });
    expect(
        container.read(firstRunProfileProvider).requireValue.completed, isTrue);
  });

  test('failed restart keeps controls available, later launch skips setup',
      () async {
    await store.write(
        const FirstRunProfile(displayName: 'Juno', step: SetupStep.network));
    await container.read(firstRunProfileProvider.future);
    final controller = container.read(firstRunProfileProvider.notifier);
    await expectLater(
        controller.finish(() async => throw StateError('restart')),
        throwsStateError);
    expect(container.read(firstRunProfileProvider).requireValue.completed,
        isFalse);
    container.invalidate(firstRunProfileProvider);
    expect((await container.read(firstRunProfileProvider.future)).completed,
        isTrue);
  });
}
