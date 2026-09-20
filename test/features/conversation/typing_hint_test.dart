// The [[Typing indicator]] rendering contract (issue #2, ticket #6): the
// hint renders from the snapshot the poll already carries, names who is
// typing, and renders nothing when nobody is — including a channel, which
// never carries typing.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/conversation/conversation_snapshot.dart';
import 'package:mosh/src/features/conversation/typing_hint.dart';
import 'package:mosh/src/gateway/conversation_target.dart';
import 'package:mosh/src/rust/channel_runtime.dart' show ChannelSnapshot;
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart'
    show DmSessionState, SessionSnapshot;
import 'package:mosh/src/rust/private_dm_runtime/transport.dart'
    show PeerTransport;
import 'package:mosh/src/rust/private_group_runtime.dart'
    show GroupSnapshot, TypingMember;

import '../../support/gateway_snapshots.dart' show cannedChannelSnapshot;
import '../../support/pump.dart';

final AppLocalizations _l = lookupAppLocalizations(const Locale('en'));

/// A DM session snapshot shaped the way the canned snapshots are, with the
/// typing deadline the test wants.
SessionSnapshot _dm({BigInt? peerTypingUntilMs}) => SessionSnapshot(
      sessionId: 's1',
      meshId: 'm',
      role: 'inviter',
      displayName: 'alice',
      peerDisplayName: 'Bob',
      state: DmSessionState.connected,
      transport: PeerTransport.direct,
      inviteUri: null,
      fingerprint: 'fp',
      messages: const [],
      attachments: const [],
      events: const [],
      peerTypingUntilMs: peerTypingUntilMs,
    );

GroupSnapshot _group({required List<TypingMember> typing}) => GroupSnapshot(
      groupId: 'g1',
      meshId: '',
      label: null,
      displayName: 'alice',
      deviceFingerprint: 'fp',
      creatorFingerprint: 'fp',
      isAdmin: false,
      state: 'ready',
      memberCount: BigInt.zero,
      inviteUri: null,
      messages: const [],
      attachments: const [],
      dmOffers: const [],
      mesh: null,
      events: const [],
      needsRejoin: false,
      orgPubkey: null,
      memberPeerIds: const [],
      typingMembers: typing,
    );

void main() {
  testWidgets('the DM hint names the counterpart while the deadline stands',
      (tester) async {
    final deadline = BigInt
        .from(DateTime.now().millisecondsSinceEpoch + 4000); // inside window
    final snapshot =
        DmConversation(const DmTarget('s1'), _dm(peerTypingUntilMs: deadline));
    await pumpScreen(tester, TypingHint(names: typingNames(snapshot)));

    expect(find.text(_l.typingHint('Bob')), findsOneWidget);
  });

  testWidgets('an expired DM deadline renders nothing', (tester) async {
    final stale = BigInt
        .from(DateTime.now().millisecondsSinceEpoch - 1000); // already past
    final snapshot =
        DmConversation(const DmTarget('s1'), _dm(peerTypingUntilMs: stale));
    await pumpScreen(tester, TypingHint(names: typingNames(snapshot)));

    expect(find.byType(Text), findsNothing);
  });

  testWidgets('the group hint identifies each member typing', (tester) async {
    final deadline = BigInt.from(DateTime.now().millisecondsSinceEpoch + 4000);
    final members = [
      TypingMember(
        fingerprint: 'fp-cleo',
        displayName: 'cleo',
        untilMs: deadline,
      ),
      TypingMember(
        fingerprint: 'fp-dana',
        displayName: 'dana',
        untilMs: deadline,
      ),
    ];
    final snapshot =
        GroupConversation(const GroupTarget('g1'), _group(typing: members));
    await pumpScreen(tester, TypingHint(names: typingNames(snapshot)));

    expect(find.textContaining('cleo'), findsOneWidget);
    expect(find.textContaining('dana'), findsOneWidget);
  });

  testWidgets('a channel never carries typing: nothing renders',
      (tester) async {
    final ChannelSnapshot source = cannedChannelSnapshot(name: 'c1');
    final snapshot = ChannelConversation(const ChannelTarget('c1'), source);
    await pumpScreen(tester, TypingHint(names: typingNames(snapshot)));

    expect(find.byType(Text), findsNothing);
  });
}
