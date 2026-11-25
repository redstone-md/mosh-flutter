// The call entry of a DM's feed. Only a DM carries call events.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_icons.dart';
import 'package:mosh/src/app/mosh_theme.dart' show MoshColors;
import 'package:mosh/src/features/conversation/call_log_entry.dart';
import 'package:mosh/src/features/conversation/conversation_call_binding.dart';
import 'package:mosh/src/features/conversation/conversation_helpers.dart'
    show formatClock;
import 'package:mosh/src/features/conversation/conversation_message_row.dart';
import 'package:mosh/src/features/conversation/conversation_snapshot.dart';
import 'package:mosh/src/gateway/conversation_target.dart'
    show ConversationKind;
import 'package:mosh/src/rust/outbound_delivery.dart'
    show MessageDeliveryStatus;
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart' show CallEvent;

import '../../support/pump.dart';

final _sentAt = BigInt.from(1700000000000);

ConversationMessage _message({CallEvent? callEvent, bool own = false}) =>
    ConversationMessage(
      fromDevice: 'alice',
      body: callEvent == null ? 'hi' : '',
      own: own,
      messageId: 'm1',
      sentAtMs: _sentAt,
      callEvent: callEvent,
      deliveryStatus: MessageDeliveryStatus.sent,
    );

CallEvent _missedCall() =>
    CallEvent(kind: 'missed', durationMs: BigInt.zero, callId: 'call-1');

Future<void> _pumpRow(WidgetTester tester, ConversationMessage message,
    {ConversationCallBinding? binding}) async {
  final l = await AppLocalizations.delegate.load(const Locale('en'));
  await pumpScreen(
    tester,
    Scaffold(
      body: ConversationMessageRow(
        message: message,
        conversationId: 'session-1',
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
    overrides: [
      if (binding != null)
        conversationCallBindingProvider.overrideWithValue(binding),
    ],
  );
}

Color _arrow(WidgetTester tester, IconData icon) =>
    tester.widget<Icon>(find.byIcon(icon)).color!;

void main() {
  late final String rang;
  setUpAll(() async {
    await initializeDateFormatting();
    rang = formatClock(_sentAt, locale: 'en')!;
  });

  testWidgets(
      'an unanswered outgoing call is not labelled as a missed incoming call',
      (tester) async {
    await _pumpRow(tester, _message(callEvent: _missedCall(), own: true));
    expect(find.text('No answer'), findsOneWidget);
    expect(find.text('Missed call'), findsNothing);
    expect(_arrow(tester, MoshIcons.callMade), MoshColors.dark.outgoingError);
  });

  testWidgets(
      'a completed call shows its direction, when it rang and how long it '
      'lasted', (tester) async {
    for (final (durationMs, detail) in [
      (0, rang),
      (65000, '$rang, 1 min 5 s'),
    ]) {
      final event = CallEvent(
          kind: 'completed',
          durationMs: BigInt.from(durationMs),
          callId: 'call');
      await _pumpRow(tester, _message(callEvent: event, own: true));
      expect(find.text('Outgoing call'), findsOneWidget);
      expect(find.text(detail), findsOneWidget);
      expect(_arrow(tester, MoshIcons.callMade), MoshColors.dark.onOutgoing);
      await _pumpRow(tester, _message(callEvent: event));
      expect(find.text('Incoming call'), findsOneWidget);
      expect(find.text(detail), findsOneWidget);
      expect(_arrow(tester, MoshIcons.callReceived), MoshColors.dark.primary);
    }
  });

  testWidgets('a call between incompatible versions asks to update Mosh',
      (tester) async {
    final event = CallEvent(
        kind: 'update_required', durationMs: BigInt.zero, callId: 'call');
    for (final own in [true, false]) {
      await _pumpRow(tester, _message(callEvent: event, own: own));
      expect(find.text('Call failed: update Mosh'), findsOneWidget);
    }
  });

  testWidgets(
      'a missed call is told by the arrow in the error colour and has no '
      'length', (tester) async {
    await _pumpRow(tester, _message(callEvent: _missedCall()));

    expect(find.text('Missed call'), findsOneWidget);
    expect(find.text(rang), findsOneWidget);
    expect(_arrow(tester, MoshIcons.callReceived), MoshColors.dark.error);
  });

  testWidgets('a message without a call event shows no call entry',
      (tester) async {
    await _pumpRow(tester, _message());
    expect(find.byType(CallLogEntry), findsNothing);
  });

  testWidgets(
      'the handset rings the same DM back and rests while the call starts',
      (tester) async {
    final started = <String>[];
    final starting = Completer<Object?>();
    await _pumpRow(tester, _message(callEvent: _missedCall()),
        binding: ConversationCallBinding(
            start: (ref, id) {
              started.add(id);
              return starting.future;
            },
            overlay: (context, host) => const SizedBox.shrink()));
    final handset = find.byTooltip('Start voice call');

    await tester.tap(handset);
    await tester.pump();
    await tester.tap(handset, warnIfMissed: false);
    expect(started, ['session-1']);

    starting.complete(null);
    await tester.pump();
    await tester.tap(handset);
    expect(started, ['session-1', 'session-1']);
  });

  testWidgets('with no call module bound the handset does nothing',
      (tester) async {
    await _pumpRow(tester, _message(callEvent: _missedCall()));
    final handset = tester.widget<IconButton>(find.descendant(
        of: find.byType(CallLogEntry), matching: find.byType(IconButton)));
    expect(handset.onPressed, isNull);
  });

  test('formatCallDuration spells the length of a call', () {
    final l = lookupAppLocalizations(const Locale('en'));
    expect(formatCallDuration(l, BigInt.zero), '');
    expect(formatCallDuration(l, BigInt.from(999)), '');
    expect(formatCallDuration(l, BigInt.from(1000)), '1 s');
    expect(formatCallDuration(l, BigInt.from(65000)), '1 min 5 s');
    expect(formatCallDuration(l, BigInt.from(3661000)), '61 min 1 s');
  });
}
