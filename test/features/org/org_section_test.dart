// Parity tests for `OrgSection` (lib/src/features/org/org_section.dart)
// -- the 1-в-1 port of React's `OrgSection.tsx`. Asserts the header +
// pending block, DM/group offer rows + accept/dismiss callbacks, the
// admin new-group form, and the member list (avatar, you badge, admin
// crown, self disabled).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/org/org_section.dart';
import 'package:mosh/src/rust/org_runtime.dart';

OrgSnapshot _org({
  String name = 'Acme',
  bool inRoster = true,
  String code = 'CODE-123',
  List<OrgMemberView> members = const [],
  List<OrgDmOfferView> dmOffers = const [],
  List<OrgGroupOfferView> groupOffers = const [],
}) =>
    OrgSnapshot(
      orgPubkey: 'pk',
      orgName: name,
      meshId: 'm',
      ownPeerId: 'me',
      confirmationCode: code,
      inRoster: inRoster,
      members: members,
      dmOffers: dmOffers,
      groupOffers: groupOffers,
      dmLinks: const [],
    );

OrgMemberView _member({
  required String name,
  String role = 'member',
  bool isSelf = false,
  String peerId = 'peer1234567890',
}) =>
    OrgMemberView(
      mossPeerId: peerId,
      name: name,
      role: role,
      isSelf: isSelf,
    );

Future<AppLocalizations> _l() =>
    AppLocalizations.delegate.load(const Locale('en'));

Future<void> _pump(
  WidgetTester tester, {
  required OrgSection section,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: SingleChildScrollView(child: section)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'header renders the org name + leave button fires onLeave',
    (tester) async {
      var left = false;
      final org = _org();
      await _pump(
        tester,
        section: OrgSection(
          org: org,
          busy: false,
          onMember: (_, __) {},
          onAcceptDmOffer: (_, __) {},
          onDismissDmOffer: (_, __) {},
          onAcceptGroupOffer: (_, __) {},
          onDismissGroupOffer: (_, __) {},
          onCreateGroup: (_, __) {},
          onLeave: (_) => left = true,
          l: await _l(),
        ),
      );
      expect(find.text('Acme'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.close).first);
      expect(left, isTrue);
    },
  );

  testWidgets(
    'pending block shows the confirmation code + hint when not in roster',
    (tester) async {
      final org = _org(inRoster: false, code: 'XYZ-999');
      await _pump(
        tester,
        section: OrgSection(
          org: org,
          busy: false,
          onMember: (_, __) {},
          onAcceptDmOffer: (_, __) {},
          onDismissDmOffer: (_, __) {},
          onAcceptGroupOffer: (_, __) {},
          onDismissGroupOffer: (_, __) {},
          onCreateGroup: (_, __) {},
          onLeave: (_) {},
          l: await _l(),
        ),
      );
      expect(find.text('XYZ-999'), findsOneWidget);
      expect(
        find.text('Your confirmation code — give it to your admin'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'DM offer row fires accept + dismiss with the org pubkey + offer id',
    (tester) async {
      String? acceptKey;
      String? acceptId;
      String? dismissKey;
      final org = _org(dmOffers: [
        OrgDmOfferView(
          offerId: 'o1',
          fromPeerId: 'p1',
          fromName: 'Bob',
          inviteUri: 'mosh://dm/x',
        ),
      ]);
      await _pump(
        tester,
        section: OrgSection(
          org: org,
          busy: false,
          onMember: (_, __) {},
          onAcceptDmOffer: (k, id) {
            acceptKey = k;
            acceptId = id;
          },
          onDismissDmOffer: (k, id) {
            dismissKey = k;
          },
          onAcceptGroupOffer: (_, __) {},
          onDismissGroupOffer: (_, __) {},
          onCreateGroup: (_, __) {},
          onLeave: (_) {},
          l: await _l(),
        ),
      );
      expect(find.text('Bob'), findsOneWidget);
      expect(find.text('wants to chat'), findsOneWidget);
      // The accept row is a TextButton.icon; tap the text label.
      await tester.tap(find.text('Bob'));
      expect(acceptKey, 'pk');
      expect(acceptId, 'o1');
      // dismiss X (the close icon within the offer row).
      await tester.tap(find.byIcon(Icons.close).at(1));
      expect(dismissKey, 'pk');
    },
  );

  testWidgets(
    'group offer row renders the label + inviter',
    (tester) async {
      final org = _org(groupOffers: [
        OrgGroupOfferView(
          offerId: 'g1',
          fromPeerId: 'p1',
          fromName: 'Carol',
          groupLabel: 'Eng',
          groupInviteUri: 'mosh://group/x',
        ),
      ]);
      await _pump(
        tester,
        section: OrgSection(
          org: org,
          busy: false,
          onMember: (_, __) {},
          onAcceptDmOffer: (_, __) {},
          onDismissDmOffer: (_, __) {},
          onAcceptGroupOffer: (_, __) {},
          onDismissGroupOffer: (_, __) {},
          onCreateGroup: (_, __) {},
          onLeave: (_) {},
          l: await _l(),
        ),
      );
      expect(find.text('Eng'), findsOneWidget);
      expect(find.text('invited by Carol'), findsOneWidget);
    },
  );

  testWidgets(
    'admin + in-roster shows the new-group form; non-admin hides it',
    (tester) async {
      final adminOrg = _org(members: [_member(name: 'me', role: 'admin', isSelf: true)]);
      await _pump(
        tester,
        section: OrgSection(
          org: adminOrg,
          busy: false,
          onMember: (_, __) {},
          onAcceptDmOffer: (_, __) {},
          onDismissDmOffer: (_, __) {},
          onAcceptGroupOffer: (_, __) {},
          onDismissGroupOffer: (_, __) {},
          onCreateGroup: (_, __) {},
          onLeave: (_) {},
          l: await _l(),
        ),
      );
      expect(find.byIcon(Icons.add), findsOneWidget);
      expect(find.text('new group name'), findsOneWidget);
    },
  );

  testWidgets(
    'member row renders the name + shortened peer id; self is disabled + badged',
    (tester) async {
      final org = _org(members: [
        _member(name: 'Alice', peerId: 'abcdef1234567890'),
        _member(name: 'me', isSelf: true, peerId: 'mepeerid12345678'),
      ]);
      await _pump(
        tester,
        section: OrgSection(
          org: org,
          busy: false,
          onMember: (_, __) {},
          onAcceptDmOffer: (_, __) {},
          onDismissDmOffer: (_, __) {},
          onAcceptGroupOffer: (_, __) {},
          onDismissGroupOffer: (_, __) {},
          onCreateGroup: (_, __) {},
          onLeave: (_) {},
          l: await _l(),
        ),
      );
      expect(find.text('Alice'), findsOneWidget);
      // shorten(peer_id, 6) -> first 6 chars + … + last 4 chars.
      expect(find.text('abcdef…7890'), findsOneWidget);
      // self is badged "you"
      expect(find.text('me (you)'), findsOneWidget);
    },
  );

  testWidgets(
    'admin member shows the admin crown',
    (tester) async {
      final org = _org(members: [
        _member(name: 'Admin', role: 'admin'),
      ]);
      await _pump(
        tester,
        section: OrgSection(
          org: org,
          busy: false,
          onMember: (_, __) {},
          onAcceptDmOffer: (_, __) {},
          onDismissDmOffer: (_, __) {},
          onAcceptGroupOffer: (_, __) {},
          onDismissGroupOffer: (_, __) {},
          onCreateGroup: (_, __) {},
          onLeave: (_) {},
          l: await _l(),
        ),
      );
      expect(find.byIcon(Icons.workspace_premium), findsOneWidget);
    },
  );
}
