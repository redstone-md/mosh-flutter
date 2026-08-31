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
// native cdylib is not involved). Also covers the copy-invite button (the
// beforeSearchActions slot's second child): invite present renders a copy
// icon + "Copy invite" tooltip; tap writes the URI to the clipboard and
// flips the icon to a check + tooltip to "Invite copied"; invite null
// renders no button.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemChannels;
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/src/features/conversation/group_screen.dart';
import 'package:mosh/src/rust/private_group_runtime.dart';
import 'package:mosh/src/state/channel_group_providers.dart';
import '../../support/pump.dart';

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
  String? inviteUri,
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
      inviteUri: inviteUri,
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
  // Use a wide surface so the AppBar `actions:` row fits the admin-pill +
  // copy-invite + peer-status + leave IconButtons without collapsing into
  // the trailing overflow indicator (the default 800x600 surface is too
  // narrow once the copy-invite button is added).
  await tester.binding.setSurfaceSize(const Size(1600, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await pumpScreen(tester, GroupScreen(groupId: snapshot.groupId), overrides: [
    groupSnapshotProvider(snapshot.groupId)
        .overrideWith((ref) async => snapshot),
  ]);
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

  // --- Copy-invite button (beforeSearchActions, second child) ---
  // Mirrors React ActiveChatPanes.tsx ~L327-337. The clipboard channel is
  // intercepted with the same idiom as chat_create_screen_test.dart so the
  // tap test can assert exactly what Clipboard.setData received.
  //
  // NOTE: assertions target the copy-invite IconButton by its tooltip
  // rather than `find.byIcon` globally, because the ConversationTools
  // SegmentedButton renders a selected-segment checkmark (Icons.check)
  // unconditionally, and the AppBar already carries other icons -- so a
  // global `find.byIcon(Icons.check/copy)` would match the wrong widget.

  testWidgets(
      'invite present renders the copy-invite button with a copy '
      'icon and "Copy invite" tooltip', (tester) async {
    const groupId = 'grp-copy';
    final snapshot = _snapshot(
      groupId: groupId,
      deviceFingerprint: 'fp-me',
      isAdmin: false,
      memberCount: BigInt.two,
      state: 'Active',
      inviteUri: 'mosh://invite?mesh=m&session=g#fp=Y',
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

    // The copy-invite button renders with the "Copy invite" tooltip and a
    // copy icon (Icons.copy) -- the not-yet-copied state.
    expect(find.byTooltip('Copy invite'), findsOneWidget);
    final button = tester.widget<IconButton>(find.ancestor(
      of: find.byTooltip('Copy invite'),
      matching: find.byType(IconButton),
    ));
    expect((button.icon as Icon).icon, Icons.copy);
    // Not yet copied: no "Invite copied" tooltip anywhere.
    expect(find.byTooltip('Invite copied'), findsNothing);
  });

  testWidgets(
      'tapping copy-invite writes the URI to the clipboard and '
      'flips the icon to a check + "Invite copied" tooltip', (tester) async {
    const uri = 'mosh://invite?mesh=m&session=g#fp=Y';
    const groupId = 'grp-copy-tap';
    final snapshot = _snapshot(
      groupId: groupId,
      deviceFingerprint: 'fp-me',
      isAdmin: false,
      memberCount: BigInt.two,
      state: 'Active',
      inviteUri: uri,
      messages: [
        _msg(
          fromDevice: 'bob',
          fromFingerprint: 'fp-bob',
          body: 'hi',
          sentAtMs: BigInt.from(1700000000000),
        ),
      ],
    );
    // Intercept the flutter/services clipboard method channel so the test
    // can assert exactly what Clipboard.setData received (same idiom as
    // chat_create_screen_test.dart).
    String? copied;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map?)?['text'] as String?;
      }
      return null;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    await _pumpGroup(tester, snapshot);

    // Before tap: the copy-invite button shows the copy icon.
    expect(
        (tester
                .widget<IconButton>(find.ancestor(
                  of: find.byTooltip('Copy invite'),
                  matching: find.byType(IconButton),
                ))
                .icon as Icon)
            .icon,
        Icons.copy);
    await tester.tap(find.byTooltip('Copy invite'));
    await tester.pumpAndSettle();

    // The URI was written to the clipboard and the button flipped to the
    // copied state: check icon + "Invite copied" tooltip; the "Copy
    // invite" tooltip is gone.
    expect(copied, uri);
    expect(find.byTooltip('Invite copied'), findsOneWidget);
    expect(find.byTooltip('Copy invite'), findsNothing);
    expect(
        (tester
                .widget<IconButton>(find.ancestor(
                  of: find.byTooltip('Invite copied'),
                  matching: find.byType(IconButton),
                ))
                .icon as Icon)
            .icon,
        Icons.check);

    // After the 1600ms revert window (React's setTimeout(..., 1600)), the
    // button reverts to the copy icon + "Copy invite" tooltip.
    await tester.pump(const Duration(milliseconds: 1600));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Copy invite'), findsOneWidget);
    expect(find.byTooltip('Invite copied'), findsNothing);
    expect(
        (tester
                .widget<IconButton>(find.ancestor(
                  of: find.byTooltip('Copy invite'),
                  matching: find.byType(IconButton),
                ))
                .icon as Icon)
            .icon,
        Icons.copy);
  });

  testWidgets('invite null renders no copy-invite button', (tester) async {
    const groupId = 'grp-no-invite';
    final snapshot = _snapshot(
      groupId: groupId,
      deviceFingerprint: 'fp-me',
      isAdmin: true,
      memberCount: BigInt.two,
      state: 'Active',
      // inviteUri omitted (null).
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

    // No copy-invite button: neither invite tooltip present.
    expect(find.byTooltip('Copy invite'), findsNothing);
    expect(find.byTooltip('Invite copied'), findsNothing);
  });
}
