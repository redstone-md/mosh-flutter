// Widget tests for the render-only FailedMessageRetry row inside a GROUP
// message bubble (lib/src/features/shared/failed_message_retry.dart, wired
// into the group row by lib/src/features/group/group_message_row.dart +
// group_screen.dart). This mirrors the channel retry test
// (channel_screen_failed_retry_test.dart) and the AttachmentCard
// display-only test (group_screen_attachment_test.dart): the onRetry
// callback is a NO-OP stub (the Gateway retry seam -- Rust
// `private_group_retry_message` + frb codegen + Gateway method -- is a
// LATER atomic), so we only assert the row RENDERS under the React
// `FailedMessageRetry` condition and does NOT render otherwise.
//
// React render condition ported 1-1 (MessageLists.tsx L438-443):
//   !outbound || delivery_status !== "failed" || !retryable || !message_id
//   -> return null
// i.e. the row renders iff outbound(== own) && failed && retryable && id.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/group/group_screen.dart';
import 'package:mosh/src/rust/private_group_runtime.dart';
import 'package:mosh/src/rust/outbound_delivery.dart';
import 'package:mosh/src/state/channel_group_providers.dart';
import '../../support/scriptable_gateway.dart';
import 'package:mosh/src/state/gateway_provider.dart';

GroupMessage _msg({
  required String fromFingerprint,
  required String body,
  String? messageId,
  MessageDeliveryStatus? deliveryStatus,
  String? deliveryError,
  bool? retryable,
  BigInt? sentAtMs,
}) =>
    GroupMessage(
      fromDevice: 'me',
      fromFingerprint: fromFingerprint,
      body: body,
      messageId: messageId,
      sentAtMs: sentAtMs,
      attachment: null,
      deliveryStatus: deliveryStatus,
      deliveryError: deliveryError,
      retryable: retryable,
      retryCount: null,
    );

GroupSnapshot _snapshot({
  required String groupId,
  required String deviceFingerprint,
  required List<GroupMessage> messages,
}) =>
    GroupSnapshot(
      groupId: groupId,
      meshId: 'testmesh',
      label: null,
      displayName: 'me',
      deviceFingerprint: deviceFingerprint,
      creatorFingerprint: deviceFingerprint,
      isAdmin: true,
      state: 'ready',
      memberCount: BigInt.from(2),
      inviteUri: null,
      messages: messages,
      attachments: const [],
      dmOffers: const [],
      mesh: null,
      events: const [],
      needsRejoin: false,
      orgPubkey: null,
      memberPeerIds: const [],
    );

Future<void> _pump(
  WidgetTester tester, {
  required String groupId,
  required GroupSnapshot snapshot,
}) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      groupSnapshotProvider(groupId).overrideWith((ref) async => snapshot),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: GroupScreen(groupId: groupId),
    ),
  ));
  await tester.pumpAndSettle();
}

Future<void> _pumpWithGateway(
  WidgetTester tester,
  ScriptableGateway gateway, {
  required String groupId,
  required GroupSnapshot snapshot,
}) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      gatewayProvider.overrideWithValue(gateway),
      groupSnapshotProvider(groupId).overrideWith((ref) async => snapshot),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: GroupScreen(groupId: groupId),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  const groupId = 'group-retry';
  final base = BigInt.from(1700000000000); // 2023-11-14T22:13:20Z

  // Happy path: an own outbound failed+retryable message with an id renders
  // the FailedMessageRetry row -- the trimmed deliveryError text + the
  // localized "Retry" button (React: `deliveryError?.trim() || "Failed to
  // send"` + a "Retry" button). Pins the 1-в-1 render condition.
  testWidgets(
      'own failed+retryable group message renders the FailedMessageRetry row',
      (tester) async {
    final msg = _msg(
      fromFingerprint: 'fp-me',
      body: 'boom',
      messageId: 'm1',
      deliveryStatus: MessageDeliveryStatus.failed,
      deliveryError: '  peer offline  ',
      retryable: true,
      sentAtMs: base,
    );
    await _pump(
      tester,
      groupId: groupId,
      snapshot: _snapshot(
        groupId: groupId,
        deviceFingerprint: 'fp-me',
        messages: [msg],
      ),
    );

    // The message body still renders.
    expect(find.text('boom'), findsOneWidget);
    // The trimmed delivery error renders (React `deliveryError?.trim()`).
    expect(find.text('peer offline'), findsOneWidget);
    // The localized "Retry" button renders (React "Retry" button text).
    expect(find.text('Retry'), findsOneWidget);
  });

  // Fallback: an own failed+retryable message with NO deliveryError renders
  // the localized "Failed to send" fallback (React
  // `deliveryError?.trim() || "Failed to send"`).
  testWidgets(
      'own failed+retryable group message with no error renders "Failed to send"',
      (tester) async {
    final msg = _msg(
      fromFingerprint: 'fp-me',
      body: 'boom',
      messageId: 'm2',
      deliveryStatus: MessageDeliveryStatus.failed,
      deliveryError: null,
      retryable: true,
      sentAtMs: base,
    );
    await _pump(
      tester,
      groupId: groupId,
      snapshot: _snapshot(
        groupId: groupId,
        deviceFingerprint: 'fp-me',
        messages: [msg],
      ),
    );

    expect(find.text('Failed to send'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  // Negative: a sent (non-failed) own message renders NO retry row.
  testWidgets('non-failed own group message renders no retry row',
      (tester) async {
    final msg = _msg(
      fromFingerprint: 'fp-me',
      body: 'ok',
      messageId: 'm3',
      deliveryStatus: MessageDeliveryStatus.sent,
      deliveryError: null,
      retryable: true,
      sentAtMs: base,
    );
    await _pump(
      tester,
      groupId: groupId,
      snapshot: _snapshot(
        groupId: groupId,
        deviceFingerprint: 'fp-me',
        messages: [msg],
      ),
    );

    expect(find.text('Failed to send'), findsNothing);
    expect(find.text('Retry'), findsNothing);
  });

  // Negative: a failed-but-not-retryable own message renders NO retry row
  // (React `!message.retryable -> return null`).
  testWidgets('failed-but-not-retryable own group message renders no row',
      (tester) async {
    final msg = _msg(
      fromFingerprint: 'fp-me',
      body: 'ok',
      messageId: 'm4',
      deliveryStatus: MessageDeliveryStatus.failed,
      deliveryError: 'nope',
      retryable: false,
      sentAtMs: base,
    );
    await _pump(
      tester,
      groupId: groupId,
      snapshot: _snapshot(
        groupId: groupId,
        deviceFingerprint: 'fp-me',
        messages: [msg],
      ),
    );

    expect(find.text('nope'), findsNothing);
    expect(find.text('Retry'), findsNothing);
  });

  // Negative: a failed+retryable INBOUND (peer) message renders NO retry row
  // (React `!outbound -> return null`; outbound == own == fromFingerprint
  // == ownFingerprint). Pins that the own-gate is fingerprint-based, not
  // display-name-based (groups are multi-party).
  testWidgets('failed+retryable inbound group message renders no row',
      (tester) async {
    final msg = _msg(
      fromFingerprint: 'fp-bob',
      body: 'boom',
      messageId: 'm5',
      deliveryStatus: MessageDeliveryStatus.failed,
      deliveryError: 'nope',
      retryable: true,
      sentAtMs: base,
    );
    await _pump(
      tester,
      groupId: groupId,
      snapshot: _snapshot(
        groupId: groupId,
        deviceFingerprint: 'fp-me',
        messages: [msg],
      ),
    );

    expect(find.text('nope'), findsNothing);
    expect(find.text('Retry'), findsNothing);
  });

  // Negative: a failed+retryable own message with NO id renders NO retry row
  // (React `!message.message_id -> return null`). Pins the messageId gate.
  testWidgets('failed+retryable own group message with no id renders no row',
      (tester) async {
    final msg = _msg(
      fromFingerprint: 'fp-me',
      body: 'boom',
      messageId: null,
      deliveryStatus: MessageDeliveryStatus.failed,
      deliveryError: 'nope',
      retryable: true,
      sentAtMs: base,
    );
    await _pump(
      tester,
      groupId: groupId,
      snapshot: _snapshot(
        groupId: groupId,
        deviceFingerprint: 'fp-me',
        messages: [msg],
      ),
    );

    expect(find.text('nope'), findsNothing);
    expect(find.text('Retry'), findsNothing);
  });

  // Retry-seam wiring: tapping the localized "Retry" button fires the
  // Gateway retry seam (retryGroupMessage -> frb private_group_retry_message)
  // with the group id + the failed message id. The snapshot then
  // invalidates so the next poll re-renders the row.
  testWidgets('tapping Retry fires retryGroupMessage with the message id',
      (tester) async {
    final gateway = ScriptableGateway();
    const msgId = 'm-retry-1';
    final msg = _msg(
      fromFingerprint: 'fp-me',
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
      groupId: groupId,
      snapshot: _snapshot(
        groupId: groupId,
        deviceFingerprint: 'fp-me',
        messages: [msg],
      ),
    );

    // Pre-condition: the Retry button rendered (the row is shown).
    expect(find.text('Retry'), findsOneWidget);
    expect(gateway.lastCall(GatewayMethod.retryGroupMessage)?.arg<String>('groupId'), isNull);
    expect(gateway.lastCall(GatewayMethod.retryGroupMessage)?.arg<String>('messageId'), isNull);

    // Tap the Retry button -- this fires the Gateway retry seam.
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    // The Gateway retry seam fired with the group id + message id.
    expect(gateway.lastCall(GatewayMethod.retryGroupMessage)?.arg<String>('groupId'), groupId);
    expect(gateway.lastCall(GatewayMethod.retryGroupMessage)?.arg<String>('messageId'), msgId);
  });
}
