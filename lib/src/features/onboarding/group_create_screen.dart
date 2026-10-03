import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/onboarding/group_create_step.dart';
import 'package:mosh/src/features/onboarding/onboard_step_frame.dart';
import 'package:mosh/src/routing/app_router.dart';

/// The group-create step screen -- thin route wrapper over [GroupCreateStep].
/// Reached from the onboarding Group tile; wraps the step content in
/// [OnboardStepFrame] (full-screen frame) and owns Back routing. All step
/// state + create/copy handlers live in [GroupCreateStep].
class GroupCreateScreen extends StatelessWidget {
  const GroupCreateScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return OnboardStepFrame(
      title: l.onboardTileGroupTitle,
      onBack: () => context.go(AppRoutes.onboarding),
      child: const GroupCreateStep(),
    );
  }
}
