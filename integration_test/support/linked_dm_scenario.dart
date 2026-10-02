import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/rust/api/conversation.dart' as conversation;
import 'package:mosh/src/rust/api/device_link.dart' as link;
import 'package:mosh/src/rust/api/private_dm.dart' as dm;
import 'package:mosh/src/rust/api/conversation_bridge.dart';
import 'package:mosh/src/rust/device_link/types.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';

import 'linked_dm_control.dart';
import 'linked_dm_ui.dart';

final class LinkedDmScenario {
  LinkedDmScenario(this.tester, this.control, this.session, this.fingerprint);
  final WidgetTester tester;
  final LinkedDmControl control;
  final String session;
  final String fingerprint;
  late final ui = LinkedDmUi(tester, session);

  Future<void> pair() async {
    final before = await identity();
    await ui.devices();
    await ui
        .visible(find.widgetWithText(OutlinedButton, 'Connect this device'));
    await ui.tap(find.widgetWithText(OutlinedButton, 'Connect this device'));
    final qr = await control.peer('original', 'qr');
    expect(qr['qr_uri'], startsWith('mosh://device-link/'));
    await tester.enterText(
        find.widgetWithText(
            TextField, 'Paste the link from your trusted device'),
        qr['qr_uri'] as String);
    await ui.tap(find.byTooltip('Connect'));
    await ui.eventually(() async =>
        (await identity()).phase == DeviceLinkPhase.awaitingConfirmation);
    final proof = await identity();
    final refused =
        await control.peer('original', 'approve', argument: 'wrong');
    expect(refused['error'], 'CodeMismatch');
    expect((await identity()).devices, hasLength(1));
    await control.peer('original', 'approve',
        argument: proof.confirmationCode!);
    await ui.eventually(
        () async => (await identity()).phase == DeviceLinkPhase.linked);
    final joined = await identity();
    final original = await control.peer('original', 'snapshot');
    expect(joined.userId, original['user_id']);
    expect(joined.ownDeviceId, before.ownDeviceId);
    expect(joined.devices.map((d) => d.mossPeerId).toSet(), hasLength(2));
    final old = before.devices.single;
    final own =
        joined.devices.firstWhere((d) => d.deviceId == joined.ownDeviceId);
    expect(own.signingPublicKey, old.signingPublicKey);
    expect(own.mossPeerId, old.mossPeerId);
    debugPrint('Pairing and independent identity verified; waiting for DM.');
    await ui.eventually(() async {
      final list = await tester.runAsync(dm.listSessions);
      return list!.sessions.any((s) => s.sessionId == session);
    });
    await ui.open();
    debugPrint('DM admitted; waiting for rendered initial history.');
    await text('Before Android pairing');
    await ui.eventually(() async =>
        (await snapshot()).historySync == DmHistorySyncState.complete);
  }

  Future<void> live() async {
    debugPrint('Checking concurrent sends through the real DM.');
    await control.concurrentSend(session, () => _send('Phone concurrent'));
    await text('Phone concurrent');
    await text('Desktop concurrent');
    await control
        .ask('wait-text', {'target': 'contact', 'body': 'Phone concurrent'});
    await control
        .ask('wait-text', {'target': 'contact', 'body': 'Desktop concurrent'});
    await control.ask('stop-original');
    await ui.send('Phone without desktop');
    await control.ask(
        'wait-text', {'target': 'contact', 'body': 'Phone without desktop'});
    await control.peer('contact', 'dm_send',
        argument: session, body: 'Contact without desktop');
    await text('Contact without desktop');
    await control.ask('background');
    debugPrint('Contact restarted; checking conversation after return.');
    await text('After Android reconnect');
    await ui.send('After foreground return');
    await control.ask(
        'wait-text', {'target': 'contact', 'body': 'After foreground return'});
    await control.ask('restart-original');
    final desktop = await control.ask(
        'wait-text', {'target': 'original', 'body': 'Phone without desktop'});
    final local = await text('Phone without desktop');
    final phoneRow =
        local.messages.singleWhere((m) => m.body == 'Phone without desktop');
    final desktopRow = (desktop['messages'] as List)
        .singleWhere((m) => m['body'] == 'Phone without desktop');
    expect(desktopRow['message_id'], phoneRow.messageId);
    expect(desktopRow['from_device'], phoneRow.fromDevice);
    expect(desktopRow['sent_at_ms'], phoneRow.sentAtMs!.toInt());
    unique(local);
    final linked = await identity();
    final own =
        linked.devices.firstWhere((d) => d.deviceId == linked.ownDeviceId);
    await control.ask('save-phone', {
      'user': linked.userId,
      'device': own.deviceId,
      'peer': own.mossPeerId,
      'signing': own.signingPublicKey,
      'ids': local.messages.map((m) => m.messageId).toList(),
    });
    await tester.pumpWidget(const SizedBox.shrink());
  }

  Future<void> restore(Map<String, dynamic> saved) async {
    final linked = await identity();
    final own =
        linked.devices.firstWhere((d) => d.deviceId == linked.ownDeviceId);
    expect(linked.userId, saved['user']);
    expect(own.deviceId, saved['device']);
    expect(own.mossPeerId, saved['peer']);
    expect(own.signingPublicKey, saved['signing']);
    debugPrint('Cold-start identity verified; opening saved DM.');
    await ui.open();
    final restored = await text('While Android stopped');
    expect(restored.messages.map((m) => m.messageId).toSet(),
        containsAll(saved['ids'] as List));
    unique(restored);
    await ui.send('After Android cold start');
    await control.ask(
        'wait-text', {'target': 'contact', 'body': 'After Android cold start'});
    await control.ask('revoke', {'device': own.deviceId});
    await ui.eventually(() async => (await identity()).revoked);
    await ui.eventually(() async {
      final s = await control.peer('original', 'snapshot');
      return (s['revocations'] as List).any((r) => r['state'] == 'Applied');
    });
    await control.peer('contact', 'dm_send',
        argument: session, body: 'After phone removal');
    await control.ask(
        'wait-text', {'target': 'original', 'body': 'After phone removal'});
    await tester.runAsync(() => expectLater(
        _send('Revoked phone send'),
        throwsA(isA<ConversationBridgeError>().having((error) => error.kind,
            'kind', ConversationBridgeErrorKind.revoked))));
    final old = await control.ask('old-qr');
    final beforeReplay = await identity();
    await tester.runAsync(() => expectLater(
          link.joinLink(uri: old['uri'] as String, deviceName: ''),
          throwsA(isA<DeviceLinkError>().having(
              (e) => e.kind,
              'kind',
              isIn([
                DeviceLinkErrorKind.invalidQr,
                DeviceLinkErrorKind.expired
              ]))),
        ));
    final afterReplay = await identity();
    expect(afterReplay.revoked, isTrue);
    expect(afterReplay.userId, beforeReplay.userId);
    expect(afterReplay.ownDeviceId, beforeReplay.ownDeviceId);
    expect(afterReplay.devices, beforeReplay.devices);
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(seconds: 2)));
    final revoked = await snapshot();
    expect(revoked.deviceRevocation, DmDeviceRevocationState.revoked);
    expect(revoked.messages.where((m) => m.body == 'After phone removal'),
        isEmpty);
    expect(revoked.messages.map((m) => m.messageId),
        containsAll(saved['ids'] as List));
    unique(revoked);
    await ui.visible(find.text('This device was removed'));
    expect(tester.widget<TextField>(ui.input).enabled, isFalse);
  }

  Future<DeviceLinkSnapshot> identity() async =>
      (await tester.runAsync(link.snapshot))!;

  Future<SessionSnapshot> snapshot() async =>
      (await tester.runAsync(() => dm.pollSession(sessionId: session)))!;

  Future<void> _send(String body) => conversation.send(
      reference: conversation.BridgeConversationRef(
          kind: conversation.BridgeConversationKind.dm, id: session),
      body: body);

  Future<SessionSnapshot> text(String body) async {
    await ui.visible(find.text(body));
    final value = await snapshot();
    expect(value.fingerprint, fingerprint);
    expect(value.messages.where((m) => m.body == body), hasLength(1));
    return value;
  }

  void unique(SessionSnapshot value) {
    final ids = value.messages.map((m) => m.messageId).toList();
    expect(ids, everyElement(isNotNull));
    expect(ids.toSet(), hasLength(ids.length));
  }
}
