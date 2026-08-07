// Chat-create route wrapper -- thin shell over [ChatCreateStep]. The step
// CONTENT (body, Create/Recreate button, InlineError, InviteResult +
// busy/copied/error state + create/copy handlers) was extracted to
// [ChatCreateStep] so atomic #8 can compose the same content inline in the
// desktop chat-pane; this screen owns only the routing decision (Back ->
// AppRoutes.onboarding) and wraps the content in [OnboardStepFrame].
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/onboarding/chat_create_step.dart';
import 'package:mosh/src/features/onboarding/onboard_step_frame.dart';
import 'package:mosh/src/routing/app_router.dart';

/// The chat-create step screen -- thin route wrapper over [ChatCreateStep].
/// Reached from the onboarding Chat tile; wraps the step content in
/// [OnboardStepFrame] (full-screen frame) and owns Back routing. All step
/// state + create/copy handlers live in [ChatCreateStep].
class ChatCreateScreen extends ConsumerWidget {
  const ChatCreateScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    return OnboardStepFrame(
      title: l.onboardTileChatTitle,
      onBack: () => context.go(AppRoutes.onboarding),
      child: ChatCreateStep(onBack: () => context.go(AppRoutes.onboarding)),
    );
  }
}
