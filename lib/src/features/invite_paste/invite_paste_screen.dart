// S4.5: Invite Paste screen route wrapper -- thin Scaffold + SafeArea over
// [OnboardStepFrame], which composes the embeddable [OnboardJoinStep]. The
// step CONTENT (body text, invite `Semantics+TextField` with live 3-state
// detection badge, Connect button, accepted-session text, error text + the
// controller + detection/busy/acceptedSessionId/error state + the
// _onChanged/_connect/_detectLabel handlers + the success navigation) was
// extracted to [OnboardJoinStep] so atomic #8 can compose the SAME content
// inline in the desktop chat-pane. This screen now owns only the routing
// decision (Back -> AppRoutes.onboarding) and wraps the content in
// [OnboardStepFrame]. One step content, two frames -- DRY, matching atomic
// #1/#2 (OnboardStepBody/OnboardMenu) and atomic #4/#5/#6
// (ChatCreateStep/GroupCreateStep/ChannelJoinStep).
//
// Visual shell: a thin Scaffold wraps the frame only for SafeArea + theming;
// the AppBar is gone (the frame's Back button replaces it), 1-to-1 with
// React OnboardJoinStep's `OnboardStepFrame`.
//
// Navigation split (mirrors atomic #6 ChannelJoinStep): the SUCCESS
// navigation (group -> groupFor, org -> sessions, dm -> inline
// acceptedSessionId) stays INSIDE [OnboardJoinStep] because both the route
// screen and the inline panel land on the same destinations. Only Back
// routing is delegated here (-> AppRoutes.onboarding).
//
// Server/async state lives behind the gatewayProvider seam (ADR 0013);
// cross-screen form state (displayName/listenPort/staticPeer) comes from
// inviteFlowProvider (ADR 0010), both read inside [OnboardJoinStep].
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/onboarding/onboard_join_step.dart';
import 'package:mosh/src/features/onboarding/onboard_step_frame.dart';
import 'package:mosh/src/routing/app_router.dart';

/// Screen where a user pastes a mosh:// invite and connects to it.
///
/// Thin route wrapper over [OnboardJoinStep]: a [Scaffold] + [SafeArea] +
/// [OnboardStepFrame] (title `l.onboardTileJoinTitle`, Back ->
/// `AppRoutes.onboarding`) around the embeddable step CONTENT. All step
/// state (controller, live detection, busy, acceptedSessionId, error) and
/// the success navigation (acceptInvite/joinGroup/joinOrg + context.go)
/// live in [OnboardJoinStep]; this screen only decides Back routing and
/// forwards the deep-link seed.
///
/// S2-3: an optional [initialInviteUri] seeds the field on first build so a
/// `mosh://` deep link that landed on /join arrives pre-pasted. The /join
/// route builder reads `state.extra` (the raw URI string) and passes it
/// here, which forwards it to [OnboardJoinStep.initialInviteUri]. Null by
/// default, so the existing no-arg widget test and in-app navigation (which
/// construct `InvitePasteScreen()`) keep working unchanged.
class InvitePasteScreen extends ConsumerWidget {
  const InvitePasteScreen({super.key, this.initialInviteUri});

  /// Optional URI string to pre-fill into the invite field. The S2-3
  /// deep-link intake passes the incoming `mosh://` URI here via the /join
  /// route's `extra`. Null for in-app navigation (manual paste).
  final String? initialInviteUri;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    return Scaffold(
      body: SafeArea(
        child: OnboardStepFrame(
          title: l.onboardTileJoinTitle,
          onBack: () => context.go(AppRoutes.onboarding),
          child: OnboardJoinStep(
            onBack: () => context.go(AppRoutes.onboarding),
            initialInviteUri: initialInviteUri,
          ),
        ),
      ),
    );
  }
}