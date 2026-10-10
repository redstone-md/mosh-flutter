import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/conversation/peer_status_drawer.dart';
import 'package:mosh/src/features/onboarding/first_run_profile.dart';
import 'package:mosh/src/features/shared/focus_ring.dart';
import 'package:mosh/src/platform/desktop_window_controller.dart';
import 'package:mosh/src/routing/app_router.dart';
import 'package:mosh/src/routing/mosh_title_bar.dart';

import '../../support/desktop_window_platform.dart';
import '../../support/first_run.dart';
import '../../support/scriptable_gateway.dart';
import 'shell_harness.dart';

Future<DesktopWindowController> _window(DesktopWindowPlatform platform,
    {TargetPlatform target = TargetPlatform.windows}) async {
  platform.install();
  final window = (await DesktopWindowController.initialize(platform: target))!;
  addTearDown(window.dispose);
  return window;
}

Future<void> _app(WidgetTester tester, DesktopWindowController window,
        {Size size = const Size(400, 800)}) =>
    pumpShellApp(tester,
        gateway: ScriptableGateway()
          ..seedSessions([shellSession(sessionId: 'alice-1', peer: 'Alice')]),
        physical: size,
        windowController: window);

Finder _inBar(Finder matching) =>
    find.descendant(of: find.byType(MoshTitleBar), matching: matching);

void main() {
  testWidgets('narrow desktop menu returns from the chat to its list',
      (tester) async {
    final platform = DesktopWindowPlatform();
    final window = await _window(platform);
    await _app(tester, window);
    await tester.tap(find.text('Alice'));
    await tester.pumpAndSettle();
    await tester.tap(_inBar(find.byTooltip('Collapse chat list')));
    await tester.pumpAndSettle();
    expect(
        appRouter.routeInformationProvider.value.uri.path, AppRoutes.sessions);
    expect(find.text('Alice'), findsOneWidget);
  });

  testWidgets('narrow desktop retains one bar across chat and settings',
      (tester) async {
    final platform = DesktopWindowPlatform();
    final window = await _window(platform);
    await _app(tester, window);
    expect(find.byType(MoshTitleBar), findsOneWidget);
    expect(find.byTooltip('Close'), findsOneWidget);
    expect(_inBar(find.byTooltip('Connection status')), findsNothing);
    await tester.tap(find.byTooltip('Minimize'));
    await tester.tap(find.byTooltip('Maximize'));
    await tester.pump();
    expect(platform.calls.map((c) => c.method),
        containsAllInOrder(['minimize', 'maximize']));
    await platform.event('maximize');
    await tester.pump();
    await tester.tap(find.byTooltip('Restore'));
    expect(platform.calls.last.method, 'unmaximize');
    appRouter.go(AppRoutes.settings);
    await tester.pumpAndSettle();
    expect(find.byType(MoshTitleBar), findsOneWidget);
    expect(find.byTooltip('Close'), findsOneWidget);
    expect(_inBar(find.byTooltip('Connection status')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'selected chat opens real diagnostics and settings hides its status',
      (tester) async {
    final platform = DesktopWindowPlatform();
    final window = await _window(platform);
    await _app(tester, window, size: const Size(1200, 850));
    await tester.tap(find.text('Alice'));
    await tester.pumpAndSettle();
    expect(_inBar(find.text('Connected')), findsOneWidget);
    await tester.tap(_inBar(find.byTooltip('Connection status')));
    await tester.pumpAndSettle();
    expect(find.byType(PeerStatusDrawer), findsOneWidget);
    await tester.tap(find.byTooltip('Close connection status'));
    await tester.pumpAndSettle();
    expect(find.byType(PeerStatusDrawer), findsNothing);
    appRouter.go(AppRoutes.settings);
    await tester.pumpAndSettle();
    expect(_inBar(find.byTooltip('Connection status')), findsNothing);
    expect(find.byType(MoshTitleBar), findsOneWidget);
  });

  testWidgets('caption supports keyboard, drag, double-click and system menu',
      (tester) async {
    final platform = DesktopWindowPlatform();
    final window = await _window(platform);
    await _app(tester, window);
    final ring = find.descendant(
        of: find.byTooltip('Close'), matching: find.byType(FocusRing));
    Focus.of(tester.element(ring)).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(platform.calls.last.method, 'close');
    final logo = _inBar(find.byType(Image));
    await tester.drag(logo, const Offset(80, 0));
    expect(platform.calls.map((c) => c.method), contains('startDragging'));
    await tester.tap(logo, buttons: kSecondaryMouseButton);
    await tester.pump();
    expect(platform.calls.last.method, 'showMenu');
    await tester.tap(logo);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tap(logo);
    await tester.pump();
    expect(platform.calls.last.method, 'maximize');
    await tester.pump(const Duration(milliseconds: 350));
  });

  testWidgets('Linux respects caption sides and runtime preference changes',
      (tester) async {
    final platform = DesktopWindowPlatform()
      ..configuration = {'layout': 'close:minimize,maximize'};
    final window = await _window(platform, target: TargetPlatform.linux);
    await _app(tester, window);
    expect(tester.getCenter(find.byTooltip('Close')).dx, lessThan(50));
    await platform.send(DesktopWindowController.channel,
        const MethodCall('configuration', {'layout': ':close'}));
    await tester.pump();
    expect(find.byTooltip('Minimize'), findsNothing);
    expect(find.byTooltip('Maximize'), findsNothing);
    expect(tester.getCenter(find.byTooltip('Close')).dx, greaterThan(350));
    expect(tester.takeException(), isNull);
  });

  testWidgets('macOS reserves real traffic lights and uses native double-click',
      (tester) async {
    final platform = DesktopWindowPlatform()
      ..configuration = {'leadingInset': 78.0};
    final window = await _window(platform, target: TargetPlatform.macOS);
    await _app(tester, window);
    expect(find.byTooltip('Close'), findsNothing);
    expect(tester.getTopLeft(_inBar(find.byType(Image))).dx, greaterThan(78));
    await tester.tap(_inBar(find.byType(Image)));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tap(_inBar(find.byType(Image)));
    await tester.pump();
    expect(platform.calls.last.method, 'doubleClick');
    await tester.pump(const Duration(milliseconds: 350));
    await platform.event('enter-full-screen');
    await tester.pump();
    await platform.event('leave-full-screen');
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'setup and setup errors retain window actions without chat status',
      (tester) async {
    final platform = DesktopWindowPlatform();
    final window = await _window(platform);
    final setup = FirstRunHarness(profile: const FirstRunProfile());
    await setup.pump(tester,
        size: const Size(400, 800), windowController: window);
    expect(find.byType(MoshTitleBar), findsOneWidget);
    expect(find.byTooltip('Close'), findsOneWidget);
    expect(_inBar(find.byTooltip('Connection status')), findsNothing);
    final error = FirstRunHarness(profile: const FirstRunProfile());
    error.store.readError = StateError('disk refused');
    await error.pump(tester,
        size: const Size(400, 800), windowController: window);
    expect(find.byType(MoshTitleBar), findsOneWidget);
    expect(find.byTooltip('Close'), findsOneWidget);
    expect(_inBar(find.byTooltip('Connection status')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('DPI and window events update native caption geometry and focus',
      (tester) async {
    final platform = DesktopWindowPlatform();
    final window = await _window(platform);
    await _app(tester, window);
    final first = platform.calls.lastWhere((c) => c.method == 'maximizeRegion');
    expect((first.arguments as Map)['left'], 308.0);
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = const Size(800, 1600);
    await tester.pump();
    await tester.pump();
    final updated =
        platform.calls.lastWhere((c) => c.method == 'maximizeRegion');
    expect((updated.arguments as Map)['pixelRatio'], 2.0);
    await platform.event('blur');
    await tester.pump();
    expect(window.focused, isFalse);
    await platform.event('focus');
    await platform.event('unmaximize');
    await platform.send(DesktopWindowController.channel,
        const MethodCall('maximizeHover', true));
    await tester.pump();
    expect(window.maximizeHovered, isTrue);
    await platform.event('enter-full-screen');
    await tester.pump();
    expect(find.byTooltip('Maximize'), findsNothing);
    final cleared =
        platform.calls.lastWhere((c) => c.method == 'maximizeRegion');
    expect((cleared.arguments as Map)['right'], 0.0);
    expect(tester.takeException(), isNull);
  });
}
