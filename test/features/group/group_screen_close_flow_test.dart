// Widget tests for the group leave close-flow -- the 1-в-1 port of React's
// `useChatCloseFlow` group branch (use-chat-close-flow.ts L67-77). The leave
// action (GroupScreenHeader's leave IconButton, wired via the screen's
// `onLeave`) now opens a ConfirmDialog (`Leave ${label}?` / body /
// `Leave group`) before the real `_leave` (gateway.leave + nav back)
// runs. The `label` is `group.label ?? shorten(groupId, 6)` (React's
// `group?.label ?? (group ? shorten(group.group_id, 6) : "this group")`;
// the group screen always has a resolved group, so the "this group" arm is
// unreachable). Mirrors the seed/override idiom of
// `group_screen_rejoin_test.dart` (override `groupSnapshotProvider`). The
// test gateway records the `leave` call, so the test asserts the real
// close only fires on confirm (React's
// `closeFlow.confirmCloseActive` gating).
//
// Four cases:
//   1. Tapping leave opens the ConfirmDialog with the group label.
//   2. When the group has NO label, the title falls back to shorten(groupId, 6).
//   3. Confirming calls the real `_leave` -> `leave(GroupTarget(...))`.
//   4. Cancelling does NOT call `_leave` (no gateway leave call).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/group/group_screen.dart';
import 'package:mosh/src/gateway/conversation_target.dart';
import '../../support/scriptable_gateway.dart';
import 'package:mosh/src/routing/app_router.dart';
import 'package:mosh/src/rust/private_group_runtime.dart';
import 'package:mosh/src/state/channel_group_providers.dart';
import 'package:mosh/src/state/gateway_provider.dart';

GroupSnapshot _emptySnapshot({
  required String groupId,
  String? label,
}) =>
    GroupSnapshot(
      groupId: groupId,
      meshId: 'testmesh',
      label: label,
      displayName: 'me',
      deviceFingerprint: 'fp-me',
      creatorFingerprint: 'fp-me',
      isAdmin: true,
      state: 'ready',
      memberCount: BigInt.from(2),
      inviteUri: null,
      messages: const [],
      attachments: const [],
      dmOffers: const [],
      mesh: null,
      events: const [],
      needsRejoin: false,
      orgPubkey: null,
      memberPeerIds: const [],
    );

Future<void> _pump(
  WidgetTester tester,
  ScriptableGateway gateway, {
  required String groupId,
  String? label,
}) async {
  // Use the real appRouter so `context.go(AppRoutes.sessions)` after a
  // confirmed leave does not throw (mirrors `chat_create_screen_test.dart`).
  final router = GoRouter(
    initialLocation: AppRoutes.groupFor(groupId),
    routes: appRouter.configuration.routes,
  );
  await tester.pumpWidget(ProviderScope(
    overrides: [
      gatewayProvider.overrideWithValue(gateway),
      groupSnapshotProvider(groupId)
          .overrideWith((ref) async => _emptySnapshot(groupId: groupId, label: label)),
    ],
    child: MaterialApp.router(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('tapping leave opens the ConfirmDialog with the group label',
      (tester) async {
    final gateway = ScriptableGateway();
    const groupId = 'grp-close-labeled';
    await _pump(tester, gateway, groupId: groupId, label: 'Tea Club');

    // The leave IconButton (Icons.logout) opens the close-flow dialog.
    await tester.tap(find.byIcon(Icons.logout));
    await tester.pumpAndSettle();

    // React `Leave ${label}?` -> ARB `leaveGroupTitle` renders the label.
    expect(find.text('Leave Tea Club?'), findsOneWidget);
    expect(find.text('Leave group'), findsOneWidget);
    // The gateway close has NOT fired yet (dialog is open, unconfirmed).
    expect(gateway.countOf(GatewayMethod.leave), 0);
  });

  testWidgets(
      'group with no label falls back to shorten(groupId, 6) in the title',
      (tester) async {
    final gateway = ScriptableGateway();
    // A 16-char groupId is long enough to trigger shorten's `head…tail`
    // form (head=6 -> 6 + 1 + 4 = 11 chars shown; e.g. "abcdef…wxyz").
    const groupId = 'abcdef0123456789';
    await _pump(tester, gateway, groupId: groupId, label: null);

    await tester.tap(find.byIcon(Icons.logout));
    await tester.pumpAndSettle();

    // shorten(groupId, 6) -> first 6 + '…' + last 4 = "abcdef…6789".
    expect(find.text('Leave abcdef…6789?'), findsOneWidget);
  });

  testWidgets('confirming calls leave (the real _leave)', (tester) async {
    final gateway = ScriptableGateway();
    const groupId = 'grp-close-confirm';
    await _pump(tester, gateway, groupId: groupId, label: 'Tea Club');

    await tester.tap(find.byIcon(Icons.logout));
    await tester.pumpAndSettle();

    // Tap the danger confirm button (labeled with the localized confirmLabel).
    await tester.tap(find.text('Leave group'));
    await tester.pumpAndSettle();

    // The real close fired with the groupId.
    expect(gateway.lastCall(GatewayMethod.leave)?.target, GroupTarget(groupId));
  });

  testWidgets('cancelling does NOT call leave', (tester) async {
    final gateway = ScriptableGateway();
    const groupId = 'grp-close-cancel';
    await _pump(tester, gateway, groupId: groupId, label: 'Tea Club');

    await tester.tap(find.byIcon(Icons.logout));
    await tester.pumpAndSettle();

    // Cancel via the ghost TextButton (localized `dialogCancel` -> "Cancel").
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    // No real close fired.
    expect(gateway.countOf(GatewayMethod.leave), 0);
    // The dialog is gone and the group screen is still mounted.
    expect(find.text('Leave Tea Club?'), findsNothing);
    expect(find.byType(GroupScreen), findsOneWidget);
  });
}
