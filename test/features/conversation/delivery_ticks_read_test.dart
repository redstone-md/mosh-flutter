// The read-receipt contract on the delivery ticks (issue #2, ticket #7):
// the SAME two ticks change COLOR when the counterpart's authenticated
// receipt lands — never a third tick. A delivered message reads the theme
// accent instead of the faint meta grey; an unread one is unchanged.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_theme.dart' show MoshColors;
import 'package:mosh/src/features/conversation/conversation_message_row.dart';
import 'package:mosh/src/features/conversation/conversation_snapshot.dart';
import 'package:mosh/src/gateway/conversation_target.dart'
    show ConversationKind;
import 'package:mosh/src/rust/outbound_delivery.dart'
    show MessageDeliveryStatus;

import '../../support/pump.dart';

final BigInt _sentAt = BigInt.from(1700000000000);
final AppLocalizations _l = lookupAppLocalizations(const Locale('en'));

ConversationMessage _ownMessage({bool? read}) => ConversationMessage(
      fromDevice: 'alice',
      fromFingerprint: null,
      body: 'hello',
      own: true,
      sentAtMs: _sentAt,
      deliveryStatus: MessageDeliveryStatus.delivered,
      read: read,
    );

Future<void> _pumpRow(
  WidgetTester tester, {
  required ConversationMessage message,
}) =>
    pumpScreen(
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
          l: _l,
        ),
      ),
    );

Text deliveredText(WidgetTester tester) {
  final label = _l.deliveryDelivered;
  return tester.widget<Text>(
    find.text(label),
  );
}

void main() {
  setUpAll(() => initializeDateFormatting());

  testWidgets(
      'the delivered ticks keep the meta grey while no receipt has landed',
      (tester) async {
    await _pumpRow(tester, message: _ownMessage(read: null));
    final text = deliveredText(tester);
    expect(text.style?.color, MoshColors.fg4);
  });

  testWidgets('the read receipt changes the color of the SAME delivered ticks',
      (tester) async {
    await _pumpRow(tester, message: _ownMessage(read: true));

    // Never a third tick: the visible text is still the delivered label,
    // and the row carries exactly one tick row.
    final label = _l.deliveryDelivered;
    expect(find.text(label), findsOneWidget);

    final text = deliveredText(tester);
    expect(text.style?.color, MoshColors.moss);
  });

  testWidgets('the ticks render nothing on a counterpart message',
      (tester) async {
    await _pumpRow(
      tester,
      message: ConversationMessage(
        fromDevice: 'bob',
        fromFingerprint: null,
        body: 'hi back',
        own: false,
        sentAtMs: _sentAt,
        deliveryStatus: MessageDeliveryStatus.delivered,
        read: true,
      ),
    );
    expect(find.text(_l.deliveryDelivered), findsNothing);
  });
}
