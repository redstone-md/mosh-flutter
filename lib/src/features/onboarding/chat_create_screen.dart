import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/onboarding/chat_create_step.dart';
import 'package:mosh/src/features/onboarding/onboard_step_frame.dart';
import 'package:mosh/src/routing/app_router.dart';

/// The chat-create step screen -- thin route wrapper over [ChatCreateStep].
/// Reached from the onboarding Chat tile; wraps the step content in
/// [OnboardStepFrame] (full-screen frame) and owns Back routing. All step
/// state + create/copy handlers live in [ChatCreateStep].
class ChatCreateScreen extends StatelessWidget {
  const ChatCreateScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return OnboardStepFrame(
      title: l.onboardTileChatTitle,
      onBack: () => context.go(AppRoutes.onboarding),
      child: const ChatCreateStep(),
    );
  }
}
