// Chat-create step route wrapper -- thin Scaffold-free shell over
// [ChatCreateStep]. The step CONTENT (body paragraph, Create/Recreate
// button, InlineError, InviteResult + the busy/copied/error state and
// the create/copy handlers) was extracted to [ChatCreateStep] so atomic
// #8 can compose the SAME content inline in the desktop chat-pane. This
// screen now owns only the routing decision (Back -> AppRoutes.onboarding)
// and wraps the content in [OnboardStepFrame] (full-screen: Scaffold +
// SafeArea + Center + Back + title). One step content, two frames -- DRY,
// matching atomic #1/#2 (OnboardStepBody/OnboardMenu).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/onboarding/chat_create_step.dart';
import 'package:mosh/src/features/onboarding/onboard_step_frame.dart';
import 'package:mosh/src/routing/app_router.dart';

/// The chat-create step screen -- thin route wrapper over [ChatCreateStep].
///
/// Reached from the onboarding Chat tile (`context.go(AppRoutes.chatCreate)`).
/// Owns only the routing decision (Back -> `AppRoutes.onboarding`): it wraps
/// [OnboardStepFrame] (full-screen frame: Scaffold + SafeArea + Center + Back
/// + title) around [ChatCreateStep] (the embeddable step CONTENT). The step
/// body, busy/copied/error state, and create/copy handlers all live in
/// [ChatCreateStep] so atomic #8 can compose the SAME content inline in the
/// desktop chat-pane (wrapped in OnboardStepBody instead of a route).
class ChatCreateScreen extends ConsumerWidget {
  const ChatCreateScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    return OnboardStepFrame(
      title: l.onboardTileChatTitle,
      onBack: () => context.go(AppRoutes.onboarding),
      child: ChatCreateStep(
        onBack: () => context.go(AppRoutes.onboarding),
      ),
    );
  }
}
