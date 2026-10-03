import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/vpn/network_choice_provider.dart';
import 'package:mosh/src/rust/vpn_consent.dart';

import '../../support/scriptable_bridge.dart';

void main() {
  late ScriptableBridge bridge;
  late ProviderContainer container;
  late NetworkChoiceController choice;
  setUp(() {
    bridge = ScriptableBridge();
    container = ProviderContainer();
    choice = container.read(networkChoiceProvider(bridge).notifier);
  });
  tearDown(() => container.dispose());

  test('retry after setup save failure keeps choice and avoids another write',
      () async {
    await choice.readSaved();
    var restarts = 0;
    await expectLater(
        choice.apply('Ethernet',
            complete: (_) async => throw StateError('setup disk error'),
            restart: () async => restarts++),
        throwsA(isA<NetworkChoiceError>()
            .having((error) => error.kind, 'kind', NetworkChoiceFailure.save)));
    expect(
        container.read(networkChoiceProvider(bridge)).savedAdapter, 'Ethernet');
    expect(restarts, 0);
    await choice.apply('Ethernet',
        complete: (restart) async => restart(),
        restart: () async => restarts++);
    expect(bridge.countOf(BridgeMethod.setVpnBypassConsent), 1);
    expect(restarts, 1);
  });

  test('shared write lock lasts through setup completion and restart',
      () async {
    await choice.readSaved();
    final completion = Completer<void>();
    final restart = Completer<void>();
    final entered = Completer<void>();
    final pending = choice.apply('Ethernet',
        complete: (apply) async {
          entered.complete();
          await completion.future;
          await apply();
        },
        restart: () => restart.future);
    await entered.future;
    await expectLater(choice.apply(null, restart: () async {}),
        throwsA(isA<NetworkChoiceError>()));
    expect(container.read(networkChoiceProvider(bridge)).busy, isTrue);
    completion.complete();
    await Future<void>.delayed(Duration.zero);
    expect(container.read(networkChoiceProvider(bridge)).busy, isTrue);
    restart.complete();
    await pending;
    expect(container.read(networkChoiceProvider(bridge)).busy, isFalse);
    expect(bridge.countOf(BridgeMethod.setVpnBypassConsent), 1);
  });

  test('read started during write cannot replace the saved choice', () async {
    await choice.readSaved();
    bridge.hold(BridgeMethod.setVpnBypassConsent);
    final save = choice.apply('Ethernet', restart: () async {});
    final consent = Completer<VpnBypassConsent?>();
    bridge.respondNext(BridgeMethod.getVpnBypassConsent, consent.future);
    final read = choice.readSaved();
    await Future<void>.delayed(Duration.zero);
    bridge.release(BridgeMethod.setVpnBypassConsent);
    await save;
    consent.complete(null);
    await read;
    final state = container.read(networkChoiceProvider(bridge));
    expect(state.savedAdapter, 'Ethernet');
    expect(state.needsRestart, isTrue);
  });

  test('a saved choice matching automatic still restarts a bound runtime',
      () async {
    bridge.seedBindInterface('Ethernet');
    await choice.readRouting();
    var restarts = 0;
    await choice.apply(null, restart: () async => restarts++);
    expect(restarts, 1);
    expect(bridge.countOf(BridgeMethod.setVpnBypassConsent), 0);
  });

  test('applying automatic before inspection still restarts an unknown binding',
      () async {
    bridge.seedVpnConsent(
        const VpnBypassConsent(interface_: 'Ethernet', index: 1));
    bridge.seedBindInterface('Ethernet');
    var restarts = 0;
    await choice.apply(null, restart: () async => restarts++);
    expect(restarts, 1);
    expect(await bridge.getVpnBypassConsent(), isNull);
    expect(bridge.countOf(BridgeMethod.getBindInterface), 0);
  });

  test('a prompt waiting on detection returns the latest saved choice',
      () async {
    await choice.readSaved();
    bridge.hold(BridgeMethod.detectVpn);
    final prompt = choice.readPrompt();
    await Future<void>.delayed(Duration.zero);
    await choice.apply('Ethernet', restart: () async {});
    bridge.release(BridgeMethod.detectVpn);
    expect((await prompt).$1.adapter, 'Ethernet');
  });

  for (final failOld in [false, true]) {
    test(
        'old write cannot overwrite rebuilt choice or release its lock: $failOld',
        () async {
      await choice.readSaved();
      final oldResponse = Completer<void>();
      bridge.respondNext(BridgeMethod.setVpnBypassConsent, oldResponse.future);
      final oldSave = choice.apply('Ethernet', restart: () async {});
      final observed = expectLater(
          oldSave, failOld ? throwsA(isA<NetworkChoiceError>()) : completes);
      container.invalidate(networkChoiceProvider(bridge));
      final replacement =
          container.read(networkChoiceProvider(bridge).notifier);
      await replacement.readSaved();
      final newResponse = Completer<void>();
      bridge.respondNext(BridgeMethod.setVpnBypassConsent, newResponse.future);
      final newSave = replacement.apply('Wi-Fi', restart: () async {});
      if (failOld) {
        oldResponse.completeError(StateError('old write failed'));
      } else {
        oldResponse.complete();
      }
      await observed;
      final state = container.read(networkChoiceProvider(bridge));
      expect(state.busy, isTrue);
      expect(state.savedAdapter, isNull);
      newResponse.complete();
      await newSave;
      expect(
          container.read(networkChoiceProvider(bridge)).savedAdapter, 'Wi-Fi');
    });
  }

  test('old read reports disposal instead of returning stale consent',
      () async {
    final response = Completer<VpnBypassConsent?>();
    bridge.respondNext(BridgeMethod.getVpnBypassConsent, response.future);
    final read = choice.readSaved();
    final observed = expectLater(read, throwsStateError);
    container.invalidate(networkChoiceProvider(bridge));
    final replacement = container.read(networkChoiceProvider(bridge).notifier);
    await replacement.readSaved();
    response.complete(const VpnBypassConsent(interface_: 'Old', index: 1));
    await observed;
    expect(container.read(networkChoiceProvider(bridge)).savedAdapter, isNull);
  });

  test('successful persistence still attempts restart after container disposal',
      () async {
    await choice.readSaved();
    bridge.hold(BridgeMethod.setVpnBypassConsent);
    var restarts = 0;
    final pending = choice.apply('Ethernet', restart: () async => restarts++);
    container.dispose();
    bridge.release(BridgeMethod.setVpnBypassConsent);
    await pending;
    expect(restarts, 1);
  });
}
