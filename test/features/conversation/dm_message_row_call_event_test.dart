// The call log pill inside a message row. Only a DM carries call events.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/conversation/conversation_message_row.dart';
import 'package:mosh/src/features/conversation/conversation_snapshot.dart';
import 'package:mosh/src/gateway/conversation_target.dart'
    show ConversationKind;
import 'package:mosh/src/rust/outbound_delivery.dart'
    show MessageDeliveryStatus;
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart' show CallEvent;

import '../../support/pump.dart';

ConversationMessage _message({CallEvent? callEvent}) => ConversationMessage(
      fromDevice: 'alice',
      body: 'hi',
      own: false,
      messageId: 'm1',
      sentAtMs: BigInt.from(1000),
      callEvent: callEvent,
      deliveryStatus: MessageDeliveryStatus.sent,
    );

CallEvent _missedCall() =>
    CallEvent(kind: 'missed', durationMs: BigInt.zero, callId: 'call-1');

Future<void> _pumpRow(WidgetTester tester, ConversationMessage message) async {
  final l = await AppLocalizations.delegate.load(const Locale('en'));
  await pumpScreen(
    tester,
    Scaffold(
      body: ConversationMessageRow(
        message: message,
        kind: ConversationKind.dm,
        grouped: false,
        busy: false,
        onAttachmentDownload: (_) {},
        onAttachmentCancel: (_) {},
        onAttachmentOpen: (_) {},
        onRetry: (_) {},
        l: l,
      ),
    ),
  );
}

void main() {
  testWidgets('a message with a call event shows the call pill',
      (tester) async {
    await _pumpRow(tester, _message(callEvent: _missedCall()));

    expect(find.text('Missed call'), findsOneWidget);
    expect(find.byIcon(Icons.phone_disabled), findsOneWidget);
  });

  testWidgets('a message without one shows no pill', (tester) async {
    await _pumpRow(tester, _message());

    expect(find.text('Missed call'), findsNothing);
    expect(find.byIcon(Icons.phone_disabled), findsNothing);
  });
}
