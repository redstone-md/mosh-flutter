// A group with no label falls back to a short form of its id in the leave
// dialog. The rest of the leave flow is shared and covered in
// test/features/conversation/conversation_close_flow_test.dart.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/src/routing/app_router.dart';
import 'package:mosh/src/rust/private_group_runtime.dart';
import 'package:mosh/src/state/channel_group_providers.dart';

import '../../support/pump.dart';

GroupSnapshot _unlabelled(String groupId) => GroupSnapshot(
      groupId: groupId,
      meshId: 'testmesh',
      displayName: 'me',
      deviceFingerprint: 'fp-me',
      creatorFingerprint: 'fp-me',
      isAdmin: true,
      state: 'ready',
      memberCount: BigInt.from(2),
      messages: const [],
      attachments: const [],
      dmOffers: const [],
      events: const [],
      needsRejoin: false,
      memberPeerIds: const [],
      typingMembers: const [],
    );

void main() {
  testWidgets('the leave dialog shortens the id when there is no label',
      (tester) async {
    // Long enough that shorten() uses its head...tail form.
    const groupId = 'abcdef0123456789';
    await pumpRoute(tester, AppRoutes.groupFor(groupId), overrides: [
      groupSnapshotProvider(groupId).overrideWith(
        (ref) async => _unlabelled(groupId),
      ),
    ]);

    await tester.tap(find.byIcon(Icons.logout));
    await tester.pumpAndSettle();

    expect(find.text('Leave abcdef…6789?'), findsOneWidget);
  });
}
