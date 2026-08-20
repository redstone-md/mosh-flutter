// Widget tests for the FailedMessageRetry row inside a DM message bubble
// (lib/src/features/shared/failed_message_retry.dart, wired into the DM
// row by lib/src/features/dm/dm_message_row.dart + dm_screen.dart). Mirrors
// the channel/group failed_retry suites: the row renders iff
// outbound(== own == fromDevice == ownDeviceName) && failed && retryable
// && message_id, and tapping the Retry button fires the Gateway retry seam
// (retryDmMessage -> frb private_dm_retry_message).
//
// React render condition ported 1-1 (MessageLists.tsx DmMessageRow
// L350-357): the FailedMessageRetry row sits BELOW the body + AttachmentCard
// + DeliveryTicks, mirroring React's message-body order.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/dm/dm_screen.dart';
import '../../support/scriptable_gateway.dart';
import 'package:mosh/src/rust/outbound_delivery.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import 'package:mosh/src/state/gateway_provider.dart';
import 'package:mosh/src/state/session_providers.dart';

ChatMessage _msg({
  required String fromDevice,
  required String body,
  String? messageId,
  MessageDeliveryStatus? deliveryStatus,
  String? deliveryError,
  bool? retryable,
  BigInt? sentAtMs,
}) =>
    ChatMessage(
      fromDevice: fromDevice,
      body: body,
      messageId: messageId,
      sentAtMs: sentAtMs,
      attachment: null,
      callEvent: null,
      deliveryStatus: deliveryStatus,
      deliveryError: deliveryError,
      retryable: retryable,
      retryCount: null,
    );

SessionSnapshot _snapshot({
  required String sessionId,
  required String displayName,
  required List<ChatMessage> messages,
}) =>
    SessionSnapshot(
      sessionId: sessionId,
      meshId: 'testmesh',
      role: 'inviter',
      displayName: displayName,
      peerDisplayName: 'peer',
      state: 'ready',
      path: 'direct',
      relayReady: null,
      inviteUri: null,
      fingerprint: 'fp-me-1234',
      messages: messages,
      attachments: const [],
      mesh: null,
      events: const [],
      pendingCall: null,
      outgoingCall: null,
      activeCall: null,
    );

Future<void> _pump(
  WidgetTester tester, {
  required String sessionId,
  required SessionSnapshot snapshot,
}) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      activeSessionProvider(sessionId).overrideWith((ref) async => snapshot),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: DmScreen(sessionId: sessionId),
    ),
  ));
  await tester.pumpAndSettle();
}

Future<void> _pumpWithGateway(
  WidgetTester tester,
  ScriptableGateway gateway, {
  required String sessionId,
  required SessionSnapshot snapshot,
}) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      gatewayProvider.overrideWithValue(gateway),
      activeSessionProvider(sessionId).overrideWith((ref) async => snapshot),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: DmScreen(sessionId: sessionId),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  const sessionId = 'sess-retry';
  final base = BigInt.from(1700000000000); // 2023-11-14T22:13:20Z

  // Happy path: an own outbound failed+retryable message with an id renders
  // the FailedMessageRetry row -- the trimmed deliveryError text + the
  // localized "Retry" button (React: deliveryError?.trim() || "Failed to
  // send" + a "Retry" button). Pins the 1-1 render condition.
  testWidgets(
      'own failed+retryable DM message renders the FailedMessageRetry row',
      (tester) async {
    final msg = _msg(
      fromDevice: 'me',
      body: 'boom',
      messageId: 'm1',
      deliveryStatus: MessageDeliveryStatus.failed,
      deliveryError: '  peer offline  ',
      retryable: true,
      sentAtMs: base,
    );
    await _pump(
      tester,
      sessionId: sessionId,
      snapshot: _snapshot(
        sessionId: sessionId,
        displayName: 'me',
        messages: [msg],
      ),
    );

    expect(find.text('boom'), findsOneWidget);
    expect(find.text('peer offline'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  // Fallback: an own failed+retryable message with NO deliveryError renders
  // the localized "Failed to send" fallback.
  testWidgets(
      'own failed+retryable DM message with no error renders "Failed to send"',
      (tester) async {
    final msg = _msg(
      fromDevice: 'me',
      body: 'boom',
      messageId: 'm2',
      deliveryStatus: MessageDeliveryStatus.failed,
      deliveryError: null,
      retryable: true,
      sentAtMs: base,
    );
    await _pump(
      tester,
      sessionId: sessionId,
      snapshot: _snapshot(
        sessionId: sessionId,
        displayName: 'me',
        messages: [msg],
      ),
    );

    expect(find.text('Failed to send'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  // Negative: a sent (non-failed) own message renders NO retry row.
  testWidgets('non-failed own DM message renders no retry row', (tester) async {
    final msg = _msg(
      fromDevice: 'me',
      body: 'ok',
      messageId: 'm3',
      deliveryStatus: MessageDeliveryStatus.sent,
      deliveryError: null,
      retryable: true,
      sentAtMs: base,
    );
    await _pump(
      tester,
      sessionId: sessionId,
      snapshot: _snapshot(
        sessionId: sessionId,
        displayName: 'me',
        messages: [msg],
      ),
    );

    expect(find.text('Failed to send'), findsNothing);
    expect(find.text('Retry'), findsNothing);
  });

  // Negative: a failed-but-not-retryable own message renders NO retry row.
  testWidgets('failed-but-not-retryable own DM message renders no row',
      (tester) async {
    final msg = _msg(
      fromDevice: 'me',
      body: 'ok',
      messageId: 'm4',
      deliveryStatus: MessageDeliveryStatus.failed,
      deliveryError: 'nope',
      retryable: false,
      sentAtMs: base,
    );
    await _pump(
      tester,
      sessionId: sessionId,
      snapshot: _snapshot(
        sessionId: sessionId,
        displayName: 'me',
        messages: [msg],
      ),
    );

    expect(find.text('nope'), findsNothing);
    expect(find.text('Retry'), findsNothing);
  });

  // Negative: a failed+retryable INBOUND (peer) message renders NO retry row
  // (outbound == own == fromDevice == ownDeviceName).
  testWidgets('failed+retryable inbound DM message renders no row',
      (tester) async {
    final msg = _msg(
      fromDevice: 'bob',
      body: 'boom',
      messageId: 'm5',
      deliveryStatus: MessageDeliveryStatus.failed,
      deliveryError: 'nope',
      retryable: true,
      sentAtMs: base,
    );
    await _pump(
      tester,
      sessionId: sessionId,
      snapshot: _snapshot(
        sessionId: sessionId,
        displayName: 'me',
        messages: [msg],
      ),
    );

    expect(find.text('nope'), findsNothing);
    expect(find.text('Retry'), findsNothing);
  });

  // Negative: a failed+retryable own message with NO id renders NO retry row.
  testWidgets('failed+retryable own DM message with no id renders no row',
      (tester) async {
    final msg = _msg(
      fromDevice: 'me',
      body: 'boom',
      messageId: null,
      deliveryStatus: MessageDeliveryStatus.failed,
      deliveryError: 'nope',
      retryable: true,
      sentAtMs: base,
    );
    await _pump(
      tester,
      sessionId: sessionId,
      snapshot: _snapshot(
        sessionId: sessionId,
        displayName: 'me',
        messages: [msg],
      ),
    );

    expect(find.text('nope'), findsNothing);
    expect(find.text('Retry'), findsNothing);
  });

  // Retry-seam wiring: tapping the localized "Retry" button fires the
  // Gateway retry seam (retryDmMessage -> frb private_dm_retry_message)
  // with the session id + the failed message id. The snapshot then
  // invalidates so the next poll re-renders the row.
  testWidgets('tapping Retry fires retryDmMessage with the message id',
      (tester) async {
    final gateway = ScriptableGateway();
    const msgId = 'm-retry-1';
    final msg = _msg(
      fromDevice: 'me',
      body: 'boom',
      messageId: msgId,
      deliveryStatus: MessageDeliveryStatus.failed,
      deliveryError: 'peer offline',
      retryable: true,
      sentAtMs: base,
    );
    await _pumpWithGateway(
      tester,
      gateway,
      sessionId: sessionId,
      snapshot: _snapshot(
        sessionId: sessionId,
        displayName: 'me',
        messages: [msg],
      ),
    );

    // Pre-condition: the Retry button rendered.
    expect(find.text('Retry'), findsOneWidget);
    expect(gateway.lastCall(GatewayMethod.retryDmMessage)?.arg<String>('sessionId'), isNull);
    expect(gateway.lastCall(GatewayMethod.retryDmMessage)?.arg<String>('messageId'), isNull);

    // Tap the Retry button -- this fires the Gateway retry seam.
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    // The Gateway retry seam fired with the session id + message id.
    expect(gateway.lastCall(GatewayMethod.retryDmMessage)?.arg<String>('sessionId'), sessionId);
    expect(gateway.lastCall(GatewayMethod.retryDmMessage)?.arg<String>('messageId'), msgId);
  });
}
