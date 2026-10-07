// IVO-16: the collapsed chat list is an avatar strip. Rows open their
// chats, while anything that needs the full row (an invitation, an
// organization, a failed load's details) expands the list first.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/sessions/rail_compact.dart';
import 'package:mosh/src/features/sessions/rail_item.dart';
import 'package:mosh/src/features/settings/settings_screen.dart';
import 'package:mosh/src/rust/channel_runtime/types.dart';
import 'package:mosh/src/rust/conversation/dm_offers.dart';
import 'package:mosh/src/state/rail_layout_provider.dart';

import '../../support/gateway_snapshots.dart';
import '../../support/rail.dart';
import '../../support/scriptable_bridge.dart';
import '../../support/settings.dart';

MemoryRailLayoutStore _collapsed() =>
    MemoryRailLayoutStore(const RailLayout(collapsed: true));

ChannelSnapshot _withOffer() => ChannelSnapshot(
      name: 'drift-room',
      topic: '',
      meshId: 'm',
      displayName: '',
      deviceFingerprint: 'SELF',
      messages: const [],
      attachments: const [],
      dmOffers: const [
        DmOffer(
          offerId: 'offer-1',
          fromDevice: 'alpha-peer',
          fromFingerprint: 'PEERFP',
          targetFingerprint: 'SELF',
          inviteUri: 'mosh://invite?mesh=m&session=drift-41#fp=91A4-D2C8-77B0',
        ),
      ],
      mesh: null,
      events: const [],
    );

void main() {
  testWidgets('a row opens its chat and names it for screen readers',
      (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      final router = await pumpRail(tester, store: _collapsed());
      expect(
          find.bySemanticsLabel(RegExp('Channel\n#general')), findsOneWidget);
      await tester.tap(find.byType(CompactRailItem));
      await tester.pumpAndSettle();
      expect(
          router.routeInformationProvider.value.uri.path, '/channel/general');
      expect(find.byType(CompactRailItem), findsOneWidget);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('an invitation expands the list instead of accepting',
      (tester) async {
    await pumpRail(tester,
        channels: const [],
        store: _collapsed(),
        seed: (bridge) => bridge.seedChannels([_withOffer()]));
    final offer = find.byWidgetPredicate(
        (w) => w is CompactRailItem && w.item.action != null);
    await tester.tap(offer);
    await tester.pumpAndSettle();
    expect(find.byType(RailNewButton), findsOneWidget);
    expect(find.text('alpha-peer'), findsOneWidget);
  });

  testWidgets('an organization expands the list to its section',
      (tester) async {
    await pumpRail(tester,
        store: _collapsed(),
        seed: (bridge) => bridge.seedOrgs(
            [cannedOrgSnapshot(orgPubkey: 'org-1', orgName: 'Crew')]));
    await tester.tap(find.byTooltip('Crew'));
    await tester.pumpAndSettle();
    expect(find.byType(RailNewButton), findsOneWidget);
    expect(find.text('Crew'), findsOneWidget);
  });

  testWidgets('a failed load retries from the strip', (tester) async {
    late ScriptableBridge failing;
    await pumpRail(tester,
        store: _collapsed(),
        seed: (bridge) =>
            (failing = bridge).failAlways(BridgeMethod.listSessions));
    failing.failNext(BridgeMethod.listSessions, times: 0);
    await tester.tap(find.byTooltip('Unable to load conversations'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Unable to load conversations'), findsNothing);
  });

  testWidgets('an empty strip leaves creation to its New button',
      (tester) async {
    await pumpRail(tester, channels: const [], store: _collapsed());
    expect(find.byType(FilledButton), findsNothing);
    await tester.tap(find.byTooltip('Start a conversation'));
    await tester.pumpAndSettle();
    expect(find.byType(CompactRailItem), findsNothing);
  });

  testWidgets('settings opens from the strip', (tester) async {
    await pumpRail(tester,
        store: _collapsed(), overrides: settingsAudioOverrides());
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
  });

  testWidgets('screen readers hear an invitation expands the list',
      (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await pumpRail(tester,
          channels: const [],
          store: _collapsed(),
          seed: (bridge) => bridge.seedChannels([_withOffer()]));
      final offer =
          tester.getSemantics(find.bySemanticsLabel(RegExp('alpha-peer')));
      expect(offer.label, isNot(contains('Accept')));
      expect(offer.hint, 'Expand chat list');
    } finally {
      semantics.dispose();
    }
  });
}
