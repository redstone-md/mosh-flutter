// S4.4: slice-one onboarding screen -- now a thin shell over OnboardMenu.
// The full menu body (identity chip -> head -> Start tiles -> Join tiles ->
// Advanced + About disclosures) lives in OnboardMenu (onboard_menu.dart) so
// atomic #3 can embed the same widget inline in the desktop chat-pane. This
// screen keeps only the Scaffold + AppBar(diagnostics action) and decides
// routing for the four tiles via context.go (1:1 with React's NewSessionPanel
// onPick, which the screen maps to route navigation rather than a step switch).
//
// S2-1: the Join tile navigates to /join (InvitePasteScreen); Group/Chat/
// Channel navigate to their create/join steps. Diagnostics is reachable from
// the AppBar action (cable_outlined -> /diagnostics), not a tile, so the four
// React tiles stay 1:1 with the upstream design. Only existing ARB keys are
// reused (diagnosticsDiagnostics for the action tooltip).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:go_router/go_router.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/onboarding/onboard_menu.dart';
import 'package:mosh/src/features/shared/persistence_warning_banner.dart';
import 'package:mosh/src/state/persistence_warning_provider.dart';
import 'package:mosh/src/routing/app_router.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  // S2-1: navigate via go_router. The home route is '/', so these are
  // push-style destinations (back returns here). go_router resolves the
  // declarative route table in app_router.dart; no Navigator.pushNamed hand-
  // rolling, and S2-3 deep-link intake reuses the same paths. The menu's
  // onPick* callbacks route to these; OnboardMenu does NOT context.go itself.
  void _goJoin() => context.go(AppRoutes.join);
  void _goChatCreate() => context.go(AppRoutes.chatCreate);
  void _goChannelJoin() => context.go(AppRoutes.channelJoin);
  void _goDiagnostics() => context.go(AppRoutes.diagnostics);
  void _goGroupCreate() => context.go(AppRoutes.groupCreate);

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    // Banner mirrors NewSessionPanel: renders above the menu (React parity;
    // OnboardMenu itself has no banner so a single surface shows it once).
    final warning = ref.watch(persistenceWarningProvider);
    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            icon: const Icon(Icons.cable_outlined),
            tooltip: l.diagnosticsDiagnostics,
            onPressed: _goDiagnostics,
          ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (warning case AsyncData(:final value) when value != null) ...[
                  PersistenceWarningBanner(warning: value),
                  const SizedBox(height: 12),
                ],
                OnboardMenu(
                  onPickChat: _goChatCreate,
                  onPickGroup: _goGroupCreate,
                  onPickChannel: _goChannelJoin,
                  onPickJoin: _goJoin,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
