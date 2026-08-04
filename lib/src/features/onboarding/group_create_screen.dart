// Group-create step route wrapper -- thin Scaffold-free shell over
// [GroupCreateStep]. The step CONTENT (body paragraph, OPTIONAL label
// input, Create/Recreate button, InlineError, InviteResult + the label
// controller and busy/copied/error/_created state and the create/copy
// handlers) was extracted to [GroupCreateStep] so atomic #8 can compose
// the SAME content inline in the desktop chat-pane. This screen now owns
// only the routing decision (Back -> AppRoutes.onboarding) and wraps the
// content in [OnboardStepFrame] (full-screen: Scaffold + SafeArea +
// Center + Back + title). One step content, two frames -- DRY, matching
// atomic #1/#2 (OnboardStepBody/OnboardMenu) and atomic #4
// (ChatCreateStep/ChatCreateScreen).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/onboarding/group_create_step.dart';
import 'package:mosh/src/features/onboarding/onboard_step_frame.dart';
import 'package:mosh/src/routing/app_router.dart';

/// The group-create step screen -- thin route wrapper over [GroupCreateStep].
///
/// Reached from the onboarding Group tile (`context.go(AppRoutes.groupCreate)`).
/// Owns only the routing decision (Back -> `AppRoutes.onboarding`): it wraps
/// [OnboardStepFrame] (full-screen frame: Scaffold + SafeArea + Center + Back
/// + title) around [GroupCreateStep] (the embeddable step CONTENT). The step
/// body, label controller, busy/copied/error/_created state, and create/copy
// handlers all live in [GroupCreateStep] so atomic #8 can compose the SAME
// content inline in the desktop chat-pane (wrapped in OnboardStepBody
// instead of a route).
class GroupCreateScreen extends ConsumerWidget {
  const GroupCreateScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    return OnboardStepFrame(
      title: l.onboardTileGroupTitle,
      onBack: () => context.go(AppRoutes.onboarding),
      child: GroupCreateStep(
        onBack: () => context.go(AppRoutes.onboarding),
      ),
    );
  }
}
