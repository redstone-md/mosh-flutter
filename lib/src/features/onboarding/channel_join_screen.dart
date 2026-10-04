import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/onboarding/channel_join_step.dart';
import 'package:mosh/src/features/onboarding/onboard_step_frame.dart';
import 'package:mosh/src/routing/app_router.dart';

/// The channel-join step screen -- thin route wrapper over [ChannelJoinStep].
/// Reached from the onboarding Channel tile; wraps the step content in
/// [OnboardStepFrame] (full-screen frame) and owns Back routing. All step
/// state + the success navigation live in [ChannelJoinStep].
class ChannelJoinScreen extends StatelessWidget {
  const ChannelJoinScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return OnboardStepFrame(
      title: l.onboardTileChannelTitle,
      onBack: () => context.go(AppRoutes.onboarding),
      child: const ChannelJoinStep(),
    );
  }
}
