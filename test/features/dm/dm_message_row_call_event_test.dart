// Parity test for the CallLogEntry slot in DmMessageRow.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/dm/dm_message_row.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import 'package:mosh/src/rust/outbound_delivery.dart' show MessageDeliveryStatus;

ChatMessage _message({
  String body = 'hi',
  CallEvent? callEvent,
  String fromDevice = 'alice',
}) =>
    ChatMessage(
      fromDevice: fromDevice,
      body: body,
      messageId: 'm1',
      sentAtMs: BigInt.from(1000),
      attachment: null,
      callEvent: callEvent,
      deliveryStatus: MessageDeliveryStatus.sent,
      deliveryError: null,
      retryable: null,
      retryCount: null,
    );

CallEvent _missedEvent() => CallEvent(
      kind: 'missed',
      durationMs: BigInt.zero,
      callId: 'call-1',
    );

Future<AppLocalizations> _l() =>
    AppLocalizations.delegate.load(const Locale('en'));

Future<void> _pumpRow(
  WidgetTester tester, {
  required ChatMessage message,
  required bool own,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: DmMessageRow(
          message: message,
          own: own,
          grouped: false,
          onAttachmentDownload: (_) {},
          onAttachmentCancel: (_) {},
          onAttachmentOpen: (_) {},
          busy: false,
          onRetry: (_) {},
          l: await _l(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'a message with a callEvent renders the CallLogEntry pill',
    (tester) async {
      await _pumpRow(
        tester,
        message: _message(callEvent: _missedEvent()),
        own: false,
      );
      expect(find.text('Missed call'), findsOneWidget);
      expect(find.byIcon(Icons.phone_disabled), findsOneWidget);
    },
  );

  testWidgets(
    'a message without a callEvent renders no pill',
    (tester) async {
      await _pumpRow(
        tester,
        message: _message(callEvent: null),
        own: false,
      );
      expect(find.text('Missed call'), findsNothing);
      expect(find.byIcon(Icons.phone_disabled), findsNothing);
    },
  );
}
