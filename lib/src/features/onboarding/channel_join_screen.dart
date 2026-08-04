// Channel-join step route wrapper -- thin Scaffold-free shell over
// [ChannelJoinStep]. The step CONTENT (body paragraph, `.step-channel-input`
// box, Join button, InlineError + the name/canJoin/busy/error state and the
// onNameChanged/onJoin handlers + the success navigation) was extracted to
// [ChannelJoinStep] so atomic #8 can compose the SAME content inline in the
// desktop chat-pane. This screen now owns only the routing decision (Back ->
// AppRoutes.onboarding) and wraps the content in [OnboardStepFrame]
// (full-screen: Scaffold + SafeArea + Center + Back + title). One step
// content, two frames -- DRY, matching atomic #1/#2 (OnboardStepBody/
// OnboardMenu).
//
// Navigation split (differs from atomic #4/#5): the SUCCESS navigation
// (`context.go(AppRoutes.channelFor(name))`) stays inside [ChannelJoinStep]
// because both the route screen and the inline panel land on the same
// channel destination. Only Back routing is delegated here.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/onboarding/channel_join_step.dart';
import 'package:mosh/src/features/onboarding/onboard_step_frame.dart';
import 'package:mosh/src/routing/app_router.dart';

/// The channel-join step screen -- thin route wrapper over [ChannelJoinStep].
///
/// Reached from the onboarding Channel tile (`context.go(AppRoutes.channelJoin)`).
/// Owns only the routing decision (Back -> `AppRoutes.onboarding`): it wraps
/// [OnboardStepFrame] (full-screen frame: Scaffold + SafeArea + Center + Back
/// + title) around [ChannelJoinStep] (the embeddable step CONTENT). The step
/// body, name/canJoin/busy/error state, onNameChanged/onJoin handlers, and the
/// success navigation (`context.go(AppRoutes.channelFor(name))`) all live in
/// [ChannelJoinStep] so atomic #8 can compose the SAME content inline in the
/// desktop chat-pane (wrapped in OnboardStepBody instead of a route).
class ChannelJoinScreen extends ConsumerWidget {
  const ChannelJoinScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    return OnboardStepFrame(
      title: l.onboardTileChannelTitle,
      onBack: () => context.go(AppRoutes.onboarding),
      child: ChannelJoinStep(
        onBack: () => context.go(AppRoutes.onboarding),
      ),
    );
  }
}


