// The message row itself: the avatar slot, and the small things that follow
// the kind -- the sender meta, the fingerprint chip and the delivery state.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/conversation/conversation_helpers.dart';
import 'package:mosh/src/features/conversation/conversation_message_row.dart';
import 'package:mosh/src/features/conversation/conversation_sender_meta.dart';
import 'package:mosh/src/features/conversation/conversation_snapshot.dart';
import 'package:mosh/src/gateway/conversation_target.dart'
    show ConversationKind;
import 'package:mosh/src/rust/outbound_delivery.dart'
    show MessageDeliveryStatus;
import 'package:mosh/src/util/format.dart' show shorten;

import '../../support/pump.dart';

final BigInt _sentAt = BigInt.from(1700000000000);

ConversationMessage _failed({
  bool own = true,
  String? messageId = 'm1',
  String? deliveryError = 'peer offline',
  bool? retryable = true,
  MessageDeliveryStatus? deliveryStatus = MessageDeliveryStatus.failed,
}) =>
    ConversationMessage(
      fromDevice: own ? 'me' : 'peer',
      body: 'boom',
      own: own,
      sentAtMs: _sentAt,
      messageId: messageId,
      deliveryStatus: deliveryStatus,
      deliveryError: deliveryError,
      retryable: retryable,
    );

ConversationMessage _message({
  String fromDevice = 'bob',
  String? fromFingerprint = 'fp-bob-0123456789',
  String body = 'hi',
  bool own = false,
  MessageDeliveryStatus? deliveryStatus,
}) =>
    ConversationMessage(
      fromDevice: fromDevice,
      fromFingerprint: fromFingerprint,
      body: body,
      own: own,
      sentAtMs: _sentAt,
      deliveryStatus: deliveryStatus,
    );

Future<void> _pumpRow(
  WidgetTester tester, {
  required ConversationMessage message,
  required ConversationKind kind,
  bool grouped = false,
}) =>
    pumpScreen(
      tester,
      Scaffold(
        body: ConversationMessageRow(
          message: message,
          kind: kind,
          grouped: grouped,
          busy: false,
          onAttachmentDownload: (_) {},
          onAttachmentCancel: (_) {},
          onAttachmentOpen: (_) {},
          onRetry: (_) {},
          l: lookupAppLocalizations(const Locale('en')),
        ),
      ),
    );

void main() {
  setUpAll(initializeDateFormatting);

  group('Retry', () {
    testWidgets('an own failed retryable message shows the trimmed error',
        (tester) async {
      await _pumpRow(tester,
          message: _failed(deliveryError: '  peer offline  '),
          kind: ConversationKind.dm);
      expect(find.text('boom'), findsOneWidget);
      expect(find.text('peer offline'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('missing error text falls back to Failed to send',
        (tester) async {
      await _pumpRow(tester,
          message: _failed(deliveryError: null), kind: ConversationKind.dm);
      expect(find.text('Failed to send'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('a message that did not fail shows no Retry', (tester) async {
      await _pumpRow(tester,
          message: _failed(
              deliveryStatus: MessageDeliveryStatus.sent, deliveryError: null),
          kind: ConversationKind.dm);
      expect(find.text('Retry'), findsNothing);
    });

    testWidgets('a failure the runtime will not retry shows no Retry',
        (tester) async {
      await _pumpRow(tester,
          message: _failed(retryable: false), kind: ConversationKind.dm);
      expect(find.text('peer offline'), findsNothing);
      expect(find.text('Retry'), findsNothing);
    });

    testWidgets('a failed message with no id shows no Retry', (tester) async {
      await _pumpRow(tester,
          message: _failed(messageId: null), kind: ConversationKind.dm);
      expect(find.text('Retry'), findsNothing);
    });

    testWidgets("someone else's failed message shows no Retry", (tester) async {
      await _pumpRow(tester,
          message: _failed(own: false), kind: ConversationKind.dm);
      expect(find.text('Retry'), findsNothing);
    });
  });

  group('avatar slot', () {
    testWidgets('the first row of a block shows the sender avatar',
        (tester) async {
      await _pumpRow(
        tester,
        message: _message(),
        kind: ConversationKind.channel,
      );

      expect(find.byType(CircleAvatar), findsOneWidget);
      expect(find.text(avatarInitials('bob')), findsOneWidget);
    });

    testWidgets('a continuation row leaves a gap instead', (tester) async {
      await _pumpRow(
        tester,
        message: _message(),
        kind: ConversationKind.channel,
        grouped: true,
      );

      expect(find.byType(CircleAvatar), findsNothing);
    });

    testWidgets('an own row is right aligned without redundant sender chrome',
        (tester) async {
      await _pumpRow(
        tester,
        message: _message(
          fromDevice: 'me',
          fromFingerprint: 'fp-me',
          own: true,
        ),
        kind: ConversationKind.channel,
      );

      expect(find.byType(CircleAvatar), findsNothing);
      expect(find.text('me'), findsNothing);
      final bubble =
          tester.getRect(find.byKey(const ValueKey('message-bubble-hi')));
      expect(bubble.right,
          tester.view.physicalSize.width / tester.view.devicePixelRatio);
    });
  });

  group('what the kind changes', () {
    testWidgets(
        'a DM shows no redundant sender meta or delivery state on a '
        'message from someone else', (tester) async {
      await _pumpRow(
        tester,
        message: _message(fromFingerprint: null),
        kind: ConversationKind.dm,
      );

      expect(find.byType(DeviceFingerprintChip), findsNothing);
      expect(find.byType(ConversationSenderMeta), findsNothing);
      expect(find.textContaining('delivered'), findsNothing);
    });

    testWidgets('a DM shows the delivery state on an own message',
        (tester) async {
      await _pumpRow(
        tester,
        message: _message(
          fromDevice: 'me',
          fromFingerprint: null,
          own: true,
          deliveryStatus: MessageDeliveryStatus.delivered,
        ),
        kind: ConversationKind.dm,
      );

      expect(find.byIcon(Icons.done_all), findsOneWidget);
      expect(find.byTooltip('✓✓ delivered'), findsOneWidget);
    });

    for (final kind in [ConversationKind.channel, ConversationKind.group]) {
      testWidgets('a ${kind.name} shows the fingerprint chip', (tester) async {
        await _pumpRow(tester, message: _message(), kind: kind);

        expect(find.text(shorten('fp-bob-0123456789', 6)), findsOneWidget);
      });
    }

    testWidgets('a channel and a group show no delivery state on own rows',
        (tester) async {
      for (final kind in [ConversationKind.channel, ConversationKind.group]) {
        await _pumpRow(
          tester,
          message: _message(
            fromDevice: 'me',
            fromFingerprint: 'fp-me',
            own: true,
            deliveryStatus: MessageDeliveryStatus.delivered,
          ),
          kind: kind,
        );
        expect(find.textContaining('delivered'), findsNothing);
      }
    });
  });
}
