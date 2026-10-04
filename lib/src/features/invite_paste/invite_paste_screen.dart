import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/onboarding/onboard_join_step.dart';
import 'package:mosh/src/features/onboarding/onboard_step_frame.dart';
import 'package:mosh/src/routing/app_router.dart';

/// Route frame for manual or deep-link invite intake.
class InvitePasteScreen extends StatelessWidget {
  const InvitePasteScreen({super.key, this.initialInviteUri});

  /// Optional URI string to pre-fill into the invite field. The S2-3
  /// deep-link intake passes the incoming `mosh://` URI here via the /join
  /// route's `extra`. Null for in-app navigation (manual paste).
  final String? initialInviteUri;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return OnboardStepFrame(
      title: l.onboardTileJoinTitle,
      onBack: () => context.go(AppRoutes.onboarding),
      child: OnboardJoinStep(initialInviteUri: initialInviteUri),
    );
  }
}
