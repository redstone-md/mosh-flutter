// Widget tests for the channel leave close-flow -- the 1-в-1 port of React's
// `useChatCloseFlow` channel branch (use-chat-close-flow.ts L57-65). The
// leave IconButton now opens a ConfirmDialog (`Leave #${name}?` / body /
// `Leave channel`) before the real `_leave` (gateway.leaveChannel + nav
// back) runs. Mirrors the seed/override idiom of
// `channel_screen_failed_retry_test.dart` (override `channelSnapshotProvider`
// so the native cdylib is not involved) PLUS a `_RecordingGateway extends
// FakeGateway` (the idiom from `chat_create_screen_test.dart`) whose
// `leaveChannel` records its `name` arg, so the test asserts the real
// close only fires on an explicit confirm (React's
// `closeFlow.confirmCloseActive` gating).
//
// Three cases:
//   1. Tapping leave opens the ConfirmDialog (title renders with the channel
//      name + the localized confirm label).
//   2. Confirming calls the real `_leave` -> `leaveChannel(name: ...)`.
//   3. Cancelling does NOT call `_leave` (no gateway leaveChannel call).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/channel/channel_screen.dart';
import 'package:mosh/src/gateway/fake_gateway.dart';
import 'package:mosh/src/routing/app_router.dart';
import 'package:mosh/src/rust/channel_runtime.dart';
import 'package:mosh/src/state/channel_group_providers.dart';
import 'package:mosh/src/state/gateway_provider.dart';

/// A FakeGateway subclass whose `leaveChannel` records its `name` arg so the
/// close-flow test can assert the real close only fires on confirm. Mirrors
/// the `_ControlledCreateGateway` idiom in `chat_create_screen_test.dart`.
class _RecordingGateway extends FakeGateway {
  String? leftChannelName;

  @override
  Future<ChannelLeaveResult> leaveChannel({required String name}) {
    leftChannelName = name;
    return Future.value(ChannelLeaveResult(name: name, closed: true));
  }
}

ChannelSnapshot _emptySnapshot(String name) => ChannelSnapshot(
      name: name,
      topic: '',
      meshId: 'testmesh',
      displayName: 'me',
      deviceFingerprint: 'fp-me',
      messages: const [],
      attachments: const [],
      dmOffers: const [],
      mesh: null,
      events: const [],
    );

Future<void> _pump(WidgetTester tester, _RecordingGateway gateway,
    {required String name}) async {
  // Use the real appRouter so `context.go(AppRoutes.sessions)` after a
  // confirmed leave does not throw (mirrors `chat_create_screen_test.dart`).
  final router = GoRouter(
    initialLocation: AppRoutes.channelFor(name),
    routes: appRouter.configuration.routes,
  );
  await tester.pumpWidget(ProviderScope(
    overrides: [
      gatewayProvider.overrideWithValue(gateway),
      channelSnapshotProvider(name)
          .overrideWith((ref) async => _emptySnapshot(name)),
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
  const name = 'chan-close';

  testWidgets('tapping leave opens the ConfirmDialog with the channel name',
      (tester) async {
    final gateway = _RecordingGateway();
    await _pump(tester, gateway, name: name);

    // The leave IconButton (Icons.logout) opens the close-flow dialog.
    await tester.tap(find.byIcon(Icons.logout));
    await tester.pumpAndSettle();

    // React `Leave #${label}?` -> ARB `leaveChannelTitle` renders the name.
    expect(find.text('Leave #$name?'), findsOneWidget);
    // The localized confirm button label renders.
    expect(find.text('Leave channel'), findsOneWidget);
    // The gateway leave has NOT fired yet (dialog is open, unconfirmed).
    expect(gateway.leftChannelName, isNull);
  });

  testWidgets('confirming calls leaveChannel (the real _leave)',
      (tester) async {
    final gateway = _RecordingGateway();
    await _pump(tester, gateway, name: name);

    await tester.tap(find.byIcon(Icons.logout));
    await tester.pumpAndSettle();

    // Tap the danger confirm button (labeled with the localized confirmLabel).
    await tester.tap(find.text('Leave channel'));
    await tester.pumpAndSettle();

    // The real close fired with the channel name.
    expect(gateway.leftChannelName, name);
  });

  testWidgets('cancelling does NOT call leaveChannel', (tester) async {
    final gateway = _RecordingGateway();
    await _pump(tester, gateway, name: name);

    await tester.tap(find.byIcon(Icons.logout));
    await tester.pumpAndSettle();

    // Cancel via the ghost TextButton (localized `dialogCancel` -> "Cancel").
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    // No real close fired.
    expect(gateway.leftChannelName, isNull);
    // The dialog is gone and the channel screen is still mounted.
    expect(find.text('Leave #$name?'), findsNothing);
    expect(find.byType(ChannelScreen), findsOneWidget);
  });
}
