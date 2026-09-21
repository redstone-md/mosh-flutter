// The org prompt above an org group: "N roster members are not in this
// group", with one button that adds them all.
//
// It shows only to an org admin, and only while someone is missing.
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/src/features/conversation/group_screen.dart';
import 'package:mosh/src/rust/org_runtime.dart';
import 'package:mosh/src/rust/private_group_runtime.dart';
import 'package:mosh/src/state/channel_group_providers.dart';
import 'package:mosh/src/state/gateway_provider.dart' show bridgeFacadeProvider;

import '../../support/pump.dart';
import '../../support/scriptable_bridge.dart';

const String _groupId = 'org-group-1';
const String _orgPubkey = 'org-pub-1';

GroupSnapshot _group({required List<String> memberPeerIds}) => GroupSnapshot(
      groupId: _groupId,
      meshId: 'testmesh',
      label: 'Squad',
      displayName: 'me',
      deviceFingerprint: 'fp-me',
      creatorFingerprint: 'fp-me',
      isAdmin: true,
      state: 'ready',
      memberCount: BigInt.from(memberPeerIds.length),
      messages: const [],
      attachments: const [],
      dmOffers: const [],
      events: const [],
      needsRejoin: false,
      orgPubkey: _orgPubkey,
      memberPeerIds: memberPeerIds,
      typingMembers: const [],
    );

OrgSnapshot _org({required String selfRole}) => OrgSnapshot(
      orgPubkey: _orgPubkey,
      orgName: 'Acme',
      meshId: 'testmesh',
      ownPeerId: 'peer-me',
      confirmationCode: '000000',
      inRoster: true,
      members: [
        OrgMemberView(
          mossPeerId: 'peer-me',
          name: 'me',
          role: selfRole,
          isSelf: true,
        ),
        const OrgMemberView(
          mossPeerId: 'peer-bob',
          name: 'bob',
          role: 'member',
          isSelf: false,
        ),
      ],
      dmOffers: const [],
      groupOffers: const [],
      dmLinks: const [],
    );

Future<void> _pump(
  WidgetTester tester, {
  required GroupSnapshot group,
  required OrgSnapshot org,
  required ScriptableBridge bridge,
}) {
  // seedOrgs serves the org read (a facade mirror, ADR 0025); the group's
  // own snapshot is overridden, so no seam double is needed here.
  bridge.seedOrgs([org]);
  return pumpScreen(tester, const GroupScreen(groupId: _groupId), overrides: [
    bridgeFacadeProvider.overrideWithValue(bridge),
    groupSnapshotProvider(_groupId).overrideWith((ref) async => group),
  ]);
}

void main() {
  testWidgets('an admin sees the missing member and can add them',
      (tester) async {
    final bridge = ScriptableBridge();
    await _pump(
      tester,
      bridge: bridge,
      group: _group(memberPeerIds: const ['peer-me']),
      org: _org(selfRole: 'admin'),
    );

    expect(find.textContaining('1 '), findsWidgets);
    expect(find.text('Add to group'), findsOneWidget);

    await tester.tap(find.text('Add to group'));
    await tester.pumpAndSettle();

    final call = bridge.lastCall(BridgeMethod.orgGroupInviteMembers);
    expect(call?.arg<String>('orgPubkey'), _orgPubkey);
    expect(call?.arg<String>('groupId'), _groupId);
    expect(call?.arg<List<String>>('memberPeerIds'), ['peer-bob']);
  });

  testWidgets('nobody is missing, so there is no prompt', (tester) async {
    await _pump(
      tester,
      bridge: ScriptableBridge(),
      group: _group(memberPeerIds: const ['peer-me', 'peer-bob']),
      org: _org(selfRole: 'admin'),
    );

    expect(find.text('Add to group'), findsNothing);
  });

  testWidgets('a plain member never sees the prompt', (tester) async {
    await _pump(
      tester,
      bridge: ScriptableBridge(),
      group: _group(memberPeerIds: const ['peer-me']),
      org: _org(selfRole: 'member'),
    );

    expect(find.text('Add to group'), findsNothing);
  });
}
