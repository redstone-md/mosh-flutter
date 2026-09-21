// Onboarding screen -- a thin shell over OnboardMenu. The full menu body
// (identity chip, Start tiles, Join tiles, Advanced + About disclosures)
// lives in OnboardMenu (onboard_menu.dart) so atomic #3 can embed the same
// widget inline in the desktop chat-pane. This screen keeps only the
// Scaffold + a bare AppBar and decides routing for the four tiles via
// context.go. The Join tile goes to /join (InvitePasteScreen);
// Group/Chat/Channel go to their create/join steps.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:go_router/go_router.dart';
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
  // go_router push-style destinations (back returns here); the menu's
  // onPick* callbacks route to these -- OnboardMenu does NOT context.go
  // itself.
  void _goJoin() => context.go(AppRoutes.join);
  void _goChatCreate() => context.go(AppRoutes.chatCreate);
  void _goChannelJoin() => context.go(AppRoutes.channelJoin);
  void _goGroupCreate() => context.go(AppRoutes.groupCreate);

  @override
  Widget build(BuildContext context) {
    // Banner above the menu (OnboardMenu has no banner, so a single
    // surface shows it once).
    final warning = ref.watch(persistenceWarningProvider);
    return Scaffold(
      // No AppBar actions: peer status lives in the shell titlebar
      // (MoshTitleBar's "Peer status" button).
      appBar: AppBar(),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (warning
                    case AsyncData(
                      :final value,
                    ) when value != null) ...[
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
