// A live BuildContext + WidgetRef for the rail's action functions
// (`org_actions.dart`, `sessions_rail_actions.dart`), which take both and
// which a test cannot construct by hand.
//
// The frame is the app's localization plus a router that starts on a
// marker screen and knows the DM and group routes, so a test can prove an
// action navigated (or did not: [kActionHarnessStartLabel] still renders).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/gateway/bridge_facade.dart' show BridgeFacade;
import 'package:mosh/src/routing/app_router.dart' show AppRoutes;
import 'package:mosh/src/state/gateway_provider.dart' show bridgeFacadeProvider;

const String kActionHarnessStart = '/start';

/// The text the marker screen renders while no action has navigated away.
const String kActionHarnessStartLabel = 'start';

typedef ActionHarness = ({BuildContext context, WidgetRef ref});

/// Mounts the marker screen over [bridge] (plus any [overrides] a test
/// needs on top, such as the gateway double) and hands back its context
/// and ref.
Future<ActionHarness> mountActionHarness(
  WidgetTester tester, {
  required BridgeFacade bridge,
  List<Override> overrides = const [],
}) async {
  late BuildContext capturedContext;
  late WidgetRef capturedRef;
  final router = GoRouter(
    initialLocation: kActionHarnessStart,
    routes: [
      GoRoute(
        path: kActionHarnessStart,
        builder: (_, __) => _Capture(
          ready: (context, ref) {
            capturedContext = context;
            capturedRef = ref;
          },
        ),
      ),
      for (final path in [AppRoutes.dm, AppRoutes.group])
        GoRoute(
          path: '$path/:id',
          builder: (_, state) => Text(state.uri.path),
        ),
    ],
  );
  final container = ProviderContainer(
    overrides: [bridgeFacadeProvider.overrideWithValue(bridge), ...overrides],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (context: capturedContext, ref: capturedRef);
}

/// Renders the marker the tests look for to prove no action navigated, and
/// hands its own [BuildContext] + [WidgetRef] back through [ready].
class _Capture extends ConsumerStatefulWidget {
  const _Capture({required this.ready});

  final void Function(BuildContext context, WidgetRef ref) ready;

  @override
  ConsumerState<_Capture> createState() => _CaptureState();
}

class _CaptureState extends ConsumerState<_Capture> {
  @override
  Widget build(BuildContext context) {
    widget.ready(context, ref);
    return const Scaffold(body: Text(kActionHarnessStartLabel));
  }
}
