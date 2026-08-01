// Widget tests for the GroupScreen AppBar header -- the 1-в-1 port of
// React `ActiveChatHeader` (ActiveChatPanes.tsx ~L302-326):
//   - subtitle: is_admin ? `${adminBadge} · ` : ""
//     + `${member_count} member${member_count === 1 ? "" : "s"} · MLS ${state}`
//   - beforeSearchActions admin-pill (crown + "admin" + title tooltip), only
//     if is_admin.
// Asserts (a) an admin sees the admin-pill + the "admin · " subtitle prefix,
// (b) a non-admin sees neither the pill nor the prefix, and (c) the member
// plural ("1 member" vs "2 members"). Mirrors the seed/override idiom of
// group_screen_grouping_test.dart (override groupSnapshotProvider so the
// native cdylib is not involved). Does NOT test the deferred copy-invite
// button (separate atomic).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/group/group_screen.dart';
import 'package:mosh/src/rust/private_group_runtime.dart';
import 'package:mosh/src/state/channel_group_providers.dart';

GroupMessage _msg({
  required String fromDevice,
  required String fromFingerprint,
  required String body,
  BigInt? sentAtMs,
}) =>
    GroupMessage(
      fromDevice: fromDevice,
      fromFingerprint: fromFingerprint,
      body: body,
      messageId: null,
      sentAtMs: sentAtMs,
      attachment: null,
      deliveryStatus: null,
      deliveryError: null,
      retryable: null,
      retryCount: null,
    );

GroupSnapshot _snapshot({
  required String groupId,
  required String deviceFingerprint,
  required bool isAdmin,
  required BigInt memberCount,
  required String state,
  required List<GroupMessage> messages,
}) =>
    GroupSnapshot(
      groupId: groupId,
      meshId: 'testmesh',
      label: null,
      displayName: 'me',
      deviceFingerprint: deviceFingerprint,
      creatorFingerprint: deviceFingerprint,
      isAdmin: isAdmin,
      state: state,
      memberCount: memberCount,
      inviteUri: null,
      messages: messages,
      attachments: const [],
      dmOffers: const [],
      mesh: null,
      events: const [],
      needsRejoin: false,
      orgPubkey: null,
      memberPeerIds: const [],
    );

Future<void> _pumpGroup(
  WidgetTester tester,
  GroupSnapshot snapshot,
) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      groupSnapshotProvider(snapshot.groupId)
          .overrideWith((ref) async => snapshot),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: GroupScreen(groupId: snapshot.groupId),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('admin user sees the admin-pill + the admin subtitle prefix',
      (tester) async {
    const groupId = 'grp-admin';
    final snapshot = _snapshot(
      groupId: groupId,
      deviceFingerprint: 'fp-me',
      isAdmin: true,
      memberCount: BigInt.two,
      state: 'Active',
      messages: [
        _msg(
          fromDevice: 'bob',
          fromFingerprint: 'fp-bob',
          body: 'hi',
          sentAtMs: BigInt.from(1700000000000),
        ),
      ],
    );
    await _pumpGroup(tester, snapshot);

    // Admin-pill: crown icon (Icons.workspace_premium) + the "admin" label.
    expect(find.byIcon(Icons.workspace_premium), findsOneWidget);
    expect(find.text('admin'), findsWidgets);

    // Subtitle (en): "admin · 2 members · MLS Active".
    expect(find.text('admin · 2 members · MLS Active'), findsOneWidget);
  });

  testWidgets('non-admin user sees no admin-pill and no admin subtitle prefix',
      (tester) async {
    const groupId = 'grp-member';
    final snapshot = _snapshot(
      groupId: groupId,
      deviceFingerprint: 'fp-me',
      isAdmin: false,
      memberCount: BigInt.two,
      state: 'Active',
      messages: [
        _msg(
          fromDevice: 'bob',
          fromFingerprint: 'fp-bob',
          body: 'hi',
          sentAtMs: BigInt.from(1700000000000),
        ),
      ],
    );
    await _pumpGroup(tester, snapshot);

    // No admin-pill (crown icon absent from the AppBar actions).
    expect(find.byIcon(Icons.workspace_premium), findsNothing);

    // Subtitle (en): "2 members · MLS Active" (no "admin · " prefix).
    expect(find.text('2 members · MLS Active'), findsOneWidget);
  });

  testWidgets('member count plural: 1 member (singular form)', (tester) async {
    const groupId = 'grp-one';
    final snapshot = _snapshot(
      groupId: groupId,
      deviceFingerprint: 'fp-me',
      isAdmin: true,
      memberCount: BigInt.one,
      state: 'Active',
      messages: [
        _msg(
          fromDevice: 'bob',
          fromFingerprint: 'fp-bob',
          body: 'hi',
          sentAtMs: BigInt.from(1700000000000),
        ),
      ],
    );
    await _pumpGroup(tester, snapshot);
    // Singular form ("1 member") -- mirrors React's `member_count === 1`.
    expect(find.text('admin · 1 member · MLS Active'), findsOneWidget);
  });

  testWidgets('member count plural: 2 members (plural form)', (tester) async {
    const groupId = 'grp-two';
    final snapshot = _snapshot(
      groupId: groupId,
      deviceFingerprint: 'fp-me',
      isAdmin: true,
      memberCount: BigInt.two,
      state: 'Active',
      messages: [
        _msg(
          fromDevice: 'bob',
          fromFingerprint: 'fp-bob',
          body: 'hi',
          sentAtMs: BigInt.from(1700000000000),
        ),
      ],
    );
    await _pumpGroup(tester, snapshot);
    // Plural form ("2 members") -- mirrors React's `member_count !== 1`.
    expect(find.text('admin · 2 members · MLS Active'), findsOneWidget);
  });
}
