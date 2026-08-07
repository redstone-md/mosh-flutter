// Channel-join route wrapper -- thin shell over [ChannelJoinStep]. The step
// CONTENT was extracted to [ChannelJoinStep] so atomic #8 can compose the
// same content inline in the desktop chat-pane; this screen owns only the
// routing decision (Back -> `AppRoutes.onboarding`) and wraps the content
// in [OnboardStepFrame]. The SUCCESS navigation stays inside
// [ChannelJoinStep] (both the route and the inline panel land on the same
// channel destination); only Back routing is delegated here.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/onboarding/channel_join_step.dart';
import 'package:mosh/src/features/onboarding/onboard_step_frame.dart';
import 'package:mosh/src/routing/app_router.dart';

/// The channel-join step screen -- thin route wrapper over [ChannelJoinStep].
/// Reached from the onboarding Channel tile; wraps the step content in
/// [OnboardStepFrame] (full-screen frame) and owns Back routing. All step
/// state + the success navigation live in [ChannelJoinStep].
class ChannelJoinScreen extends ConsumerWidget {
  const ChannelJoinScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    return OnboardStepFrame(
      title: l.onboardTileChannelTitle,
      onBack: () => context.go(AppRoutes.onboarding),
      child: ChannelJoinStep(onBack: () => context.go(AppRoutes.onboarding)),
    );
  }
}
