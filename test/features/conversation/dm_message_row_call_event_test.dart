// The call log pill inside a message row. Only a DM carries call events.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/conversation/call_log_entry.dart';
import 'package:mosh/src/features/conversation/conversation_message_row.dart';
import 'package:mosh/src/features/conversation/conversation_snapshot.dart';
import 'package:mosh/src/gateway/conversation_target.dart'
    show ConversationKind;
import 'package:mosh/src/rust/outbound_delivery.dart'
    show MessageDeliveryStatus;
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart' show CallEvent;

import '../../support/pump.dart';

ConversationMessage _message({CallEvent? callEvent, bool own = false}) =>
    ConversationMessage(
      fromDevice: 'alice',
      body: 'hi',
      own: own,
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
  testWidgets(
      'an unanswered outgoing call is not labelled as a missed incoming call',
      (tester) async {
    await _pumpRow(tester, _message(callEvent: _missedCall(), own: true));
    expect(find.text('No answer'), findsOneWidget);
    expect(find.text('Missed call'), findsNothing);
    expect(find.byIcon(Icons.call_made), findsOneWidget);
  });

  testWidgets('completed incoming and outgoing calls show their direction',
      (tester) async {
    for (final (durationMs, suffix) in [
      (0, ''),
      (65000, ' · 1:05'),
    ]) {
      final event = CallEvent(
          kind: 'completed',
          durationMs: BigInt.from(durationMs),
          callId: 'call');
      await _pumpRow(tester, _message(callEvent: event, own: true));
      expect(find.text('Outgoing call$suffix'), findsOneWidget);
      expect(find.byIcon(Icons.call_made), findsOneWidget);
      await _pumpRow(tester, _message(callEvent: event));
      expect(find.text('Incoming call$suffix'), findsOneWidget);
      expect(find.byIcon(Icons.call_received), findsOneWidget);
      expect(find.byIcon(Icons.call_missed), findsNothing);
    }
  });
  testWidgets('a message with a call event shows the call pill',
      (tester) async {
    await _pumpRow(tester, _message(callEvent: _missedCall()));

    expect(find.text('Missed call'), findsOneWidget);
    expect(find.byIcon(Icons.call_missed), findsOneWidget);
    expect(find.byIcon(Icons.call_received), findsNothing);
    expect(
        find.descendant(
            of: find.byType(CallLogEntry),
            matching: find.textContaining(' · ')),
        findsNothing);
  });

  testWidgets('a message without one shows no pill', (tester) async {
    await _pumpRow(tester, _message());

    expect(find.text('Missed call'), findsNothing);
    expect(find.byIcon(Icons.call_missed), findsNothing);
  });

  test('formatCallDuration renders duration text', () {
    expect(formatCallDuration(BigInt.zero), '');
    expect(formatCallDuration(BigInt.from(999)), '');
    expect(formatCallDuration(BigInt.from(1000)), '0:01');
    expect(formatCallDuration(BigInt.from(65000)), '1:05');
    expect(formatCallDuration(BigInt.from(86000)), '1:26');
    expect(formatCallDuration(BigInt.from(3661000)), '61:01');
  });
}
