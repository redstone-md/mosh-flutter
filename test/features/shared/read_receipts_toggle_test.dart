// The [[Read receipt]] settings toggle (issue #2, ticket #7): the row
// reads the persisted answer through the bridge facade, writes both ways,
// and rolls back with an inline error when the write fails.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/shared/read_receipts_toggle.dart';

import '../../support/pump.dart';
import '../../support/scriptable_bridge.dart';

final AppLocalizations _l = lookupAppLocalizations(const Locale('en'));

void main() {
  setUpAll(() => initializeDateFormatting());

  testWidgets('renders the stored answer once the read lands', (tester) async {
    final bridge = ScriptableBridge()..seedReadReceiptsEnabled(true);
    await pumpScreen(
        tester, Scaffold(body: ReadReceiptsToggle(bridge: bridge)));

    // The initial disabled state settles once the async read completes.
    await tester.pumpAndSettle();

    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isTrue,
    );
    expect(find.text(_l.settingsReadReceiptsTitle), findsOneWidget);
  });

  testWidgets('a tap writes the new answer through the facade', (tester) async {
    final bridge = ScriptableBridge()..seedReadReceiptsEnabled(false);
    await pumpScreen(
        tester, Scaffold(body: ReadReceiptsToggle(bridge: bridge)));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();

    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isTrue,
    );
    expect(
      bridge.callsTo(BridgeMethod.setReadReceiptsEnabled),
      isNotEmpty,
      reason: 'the tap must go through setReadReceiptsEnabled',
    );
  });

  testWidgets('a failed write rolls the switch back and shows the error',
      (tester) async {
    final bridge = ScriptableBridge()..seedReadReceiptsEnabled(true);
    bridge.failAlways(BridgeMethod.setReadReceiptsEnabled, error: 'disk full');
    await pumpScreen(
        tester, Scaffold(body: ReadReceiptsToggle(bridge: bridge)));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();

    // Rolled back to the stored answer, with the write's failure visible.
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isTrue,
    );
    expect(find.textContaining('disk full'), findsOneWidget);
  });
}
