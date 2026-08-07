// Group-create route wrapper -- thin shell over [GroupCreateStep]. The step
// CONTENT (body, optional label input, Create/Recreate button, InviteResult,
// label controller + busy/copied/error/_created state) was extracted to
// [GroupCreateStep] so atomic #8 can compose the same content inline in the
// desktop chat-pane; this screen owns only the routing decision (Back ->
// AppRoutes.onboarding) and wraps the content in [OnboardStepFrame].
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/onboarding/group_create_step.dart';
import 'package:mosh/src/features/onboarding/onboard_step_frame.dart';
import 'package:mosh/src/routing/app_router.dart';

/// The group-create step screen -- thin route wrapper over [GroupCreateStep].
/// Reached from the onboarding Group tile; wraps the step content in
/// [OnboardStepFrame] (full-screen frame) and owns Back routing. All step
/// state + create/copy handlers live in [GroupCreateStep].
class GroupCreateScreen extends ConsumerWidget {
  const GroupCreateScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    return OnboardStepFrame(
      title: l.onboardTileGroupTitle,
      onBack: () => context.go(AppRoutes.onboarding),
      child: GroupCreateStep(onBack: () => context.go(AppRoutes.onboarding)),
    );
  }
}
