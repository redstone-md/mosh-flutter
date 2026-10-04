// Shared header: admin role once, localized membership, invitation menu and
// fingerprint action. Real clipboard channel calls are observed below.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemChannels, LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/conversation/group_screen.dart';
import 'package:mosh/src/rust/private_group_runtime.dart'
    show GroupSnapshot, GroupNameStatus;
import 'package:mosh/src/state/channel_group_providers.dart';

import '../../support/message_builders.dart';
import '../../support/pump.dart';

Future<void> _pumpGroup(WidgetTester tester, GroupSnapshot snapshot) =>
    pumpScreen(tester, GroupScreen(groupId: snapshot.groupId), overrides: [
      groupSnapshotProvider(snapshot.groupId)
          .overrideWith((ref) async => snapshot),
    ]);

Future<void> _openMenu(WidgetTester tester) async {
  await tester.tap(find.byTooltip('More chat actions'));
  await tester.pumpAndSettle();
}

GroupSnapshot _snapshot(
        {bool admin = false,
        int members = 2,
        GroupNameStatus? nameStatus,
        String? invite,
        String fingerprint = ''}) =>
    TestSnapshots.group(
        groupId: 'header-group',
        deviceFingerprint: 'fp-me',
        messages: [],
        label: 'Design team',
        isAdmin: admin,
        nameStatus: nameStatus,
        memberCount: BigInt.from(members),
        state: 'Active',
        inviteUri: invite,
        creatorFingerprint: fingerprint);

void main() {
  for (final status in [
    const GroupNameStatus(pending: true),
    const GroupNameStatus(pending: false, error: 'permission_changed'),
  ]) {
    testWidgets(
        'rename status preserves membership, role and MLS state: $status',
        (tester) async {
      await _pumpGroup(tester, _snapshot(admin: true, nameStatus: status));
      expect(
          find.textContaining('admin, 2 members · MLS Active'), findsOneWidget);
      expect(
          find.textContaining(status.pending
              ? 'Name change waiting to send'
              : 'Name change rejected'),
          findsOneWidget);
    });
  }

  for (final admin in [true, false]) {
    for (final count in [1, 2]) {
      testWidgets('admin=$admin, members=$count: one compact role/status line',
          (tester) async {
        await _pumpGroup(tester, _snapshot(admin: admin, members: count));
        final members = '$count ${count == 1 ? 'member' : 'members'}';
        expect(find.text('${admin ? 'admin, ' : ''}$members · MLS Active'),
            findsOneWidget);
        expect(find.byIcon(Icons.workspace_premium_outlined), findsNothing);
        expect(find.text('admin'), findsNothing);
      });
    }
  }

  testWidgets('invitation is available in the menu, with no duplicate button',
      (tester) async {
    await _pumpGroup(
        tester, _snapshot(invite: 'mosh://invite?mesh=m&session=g#fp=Y'));
    expect(find.byTooltip('Copy invite'), findsNothing);
    await _openMenu(tester);
    expect(find.text('Copy invite'), findsOneWidget);
    expect(find.byIcon(Icons.copy), findsOneWidget);
  });

  testWidgets('copy invitation writes the URI and acknowledges it in the menu',
      (tester) async {
    const uri = 'mosh://invite?mesh=m&session=g#fp=Y';
    String? copied;
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String;
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    await _pumpGroup(tester, _snapshot(invite: uri));
    await _openMenu(tester);
    await tester.tap(find.text('Copy invite'));
    await tester.pumpAndSettle();
    expect(copied, uri);
    await _openMenu(tester);
    expect(find.text('Invite copied'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1600));
    await tester.pumpAndSettle();
    // A popup is a snapshot of its entries; reopen to read the reverted state.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await _openMenu(tester);
    expect(find.text('Copy invite'), findsOneWidget);
    expect(find.text('Invite copied'), findsNothing);
  });

  testWidgets('absent invitation exposes no copy action', (tester) async {
    await _pumpGroup(tester, _snapshot(admin: true));
    await _openMenu(tester);
    expect(find.text('Copy invite'), findsNothing);
    expect(find.text('Invite copied'), findsNothing);
  });

  testWidgets('a non-empty creator fingerprint exposes the security action',
      (tester) async {
    await _pumpGroup(tester, _snapshot(fingerprint: '0011223344556677'));
    expect(find.byTooltip('End-to-end encrypted'), findsOneWidget);
  });

  testWidgets('group fingerprint opens the dialog with the group-specific hint',
      (tester) async {
    const fingerprint = '0011223344556677';
    await _pumpGroup(tester, _snapshot(fingerprint: fingerprint));
    await tester.tap(find.byTooltip('End-to-end encrypted'));
    await tester.pumpAndSettle();
    expect(find.text('Encryption fingerprint'), findsOneWidget);
    expect(find.text(fingerprint), findsOneWidget);
    expect(
        find.text(
            'The same for every member. Compare it with the group creator.'),
        findsOneWidget);
    expect(
        find.text(
            'The same on both sides. Compare it with your peer over a call or in person.'),
        findsNothing);
  });
}
