// Inline NewSessionPanel -- 1-to-1 with React `NewSessionPanel`
// (src/features/private-dm/NewSessionPanel.tsx:18-67). React renders this
// INLINE in the desktop chat-pane when no conversation is open: a local
// `step` state enum, the PersistenceWarningBanner, OnboardMenu(onPick ->
// setStep), and the four steps each with onBack: backToMenu. The rail stays
// mounted throughout (menu -> pick chat -> step inline -> back to menu).
//
// Flutter parity: a single `OnboardStep` enum + an [IndexedStack] that keeps
// all five step widgets MOUNTED simultaneously. The stack swaps the visible
// child via `index`, so each step's own controllers/state survive a menu
// round-trip (e.g. the chat step's created invite is still there after a
// menu -> chat -> menu detour). This mirrors React's lifted per-step state
// (joinValue / channelValue / groupLabelValue) -- Flutter keeps the widgets
// alive instead of lifting the text values; equivalent UX.
//
// The PersistenceWarningBanner renders INSIDE the scroll (React renders it
// inside `.onboard-shell` before the step branch, NewSessionPanel.tsx:46),
// so it scrolls with the step body. The success navigation
// (ChannelJoinStep's context.go channelFor, OnboardJoinStep's context.go
// groupFor/sessions) fires from within the step -- it leaves the welcome
// pane entirely (opens the chat in branch B), which is correct.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/onboarding/channel_join_step.dart';
import 'package:mosh/src/features/onboarding/chat_create_step.dart';
import 'package:mosh/src/features/onboarding/group_create_step.dart';
import 'package:mosh/src/features/onboarding/onboard_join_step.dart';
import 'package:mosh/src/features/onboarding/onboard_menu.dart';
import 'package:mosh/src/features/onboarding/onboard_step_frame.dart';
import 'package:mosh/src/features/shared/persistence_warning_banner.dart';
import 'package:mosh/src/state/persistence_warning_provider.dart';

/// The inline NewSessionPanel step enum (1-to-1 with React's `OnboardStep`,
/// NewSessionPanel.types.ts). The active step drives the [IndexedStack]
/// index; switching is local (no route navigation -- the rail stays).
enum OnboardStep { menu, chat, group, join, channel }

/// Inline NewSessionPanel -- the desktop chat-pane welcome body when no
/// conversation is open. Mirrors React `NewSessionPanel`
/// (NewSessionPanel.tsx:18-67): owns the active [OnboardStep], renders the
/// PersistenceWarningBanner at the top of the scroll, then the active step.
///
/// The caller composes the outer body (Center > SingleChildScrollView >
/// ConstrainedBox(maxWidth: 460)) -- the same composition the
/// OnboardingScreen uses -- so the inline panel renders identically to the
/// onboarding screen's menu. The banner sits inside the scroll above the
/// IndexedStack (React puts it inside `.onboard-shell` before the step
/// branch).
///
/// Per-step state survives a menu round-trip via the [IndexedStack] keep-
/// alive: all five step widgets stay mounted (the chat step's created
/// invite, the join step's pasted link, the channel step's name all
/// survive). React lifts those text values; Flutter keeps the widgets alive
/// -- equivalent UX. Document this here so the keep-alive is not removed.
class NewSessionPanel extends ConsumerStatefulWidget {
  const NewSessionPanel({super.key});

  @override
  ConsumerState<NewSessionPanel> createState() => _NewSessionPanelState();
}

class _NewSessionPanelState extends ConsumerState<NewSessionPanel> {
  OnboardStep _step = OnboardStep.menu;

  void _backToMenu() => setState(() => _step = OnboardStep.menu);

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    // React renders the banner INSIDE onboard-shell before the step branch
    // (NewSessionPanel.tsx:46). It scrolls with the step body (no fixed
    // header). OnboardMenu also renders its own banner via the provider,
    // but the step screens do NOT, so this banner covers the steps too.
    final warning = ref.watch(persistenceWarningProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (warning case AsyncData(:final value) when value != null) ...<Widget>[
          PersistenceWarningBanner(warning: value),
          const SizedBox(height: 12),
        ],
        // IndexedStack keep-alive: all five step widgets stay mounted, so
        // each step's controllers/state survive a menu round-trip (React
        // lifts the text values; Flutter keeps the widgets -- equivalent).
        // No Expanded: the desktop ChatPaneWelcome wraps this panel in a
        // SingleChildScrollView, so the Column height is unbounded. An
        // Expanded (non-zero flex) in an unbounded column throws -- the
        // IndexedStack instead sizes to its tallest step and scrolls with
        // the banner. Keep-alive is inherent to IndexedStack (all children
        // stay mounted), not Expanded, so the round-trip guarantee holds.
        IndexedStack(
          index: _step.index,
          children: <Widget>[
            OnboardMenu(
              onPickChat: () => setState(() => _step = OnboardStep.chat),
              onPickGroup: () => setState(() => _step = OnboardStep.group),
              onPickChannel: () =>
                  setState(() => _step = OnboardStep.channel),
              onPickJoin: () => setState(() => _step = OnboardStep.join),
            ),
            OnboardStepBody(
              title: l.onboardTileChatTitle,
              onBack: _backToMenu,
              child: ChatCreateStep(onBack: _backToMenu),
            ),
            OnboardStepBody(
              title: l.onboardTileGroupTitle,
              onBack: _backToMenu,
              child: GroupCreateStep(onBack: _backToMenu),
            ),
            OnboardStepBody(
              title: l.onboardTileJoinTitle,
              onBack: _backToMenu,
              // Inline join has no deep-link seed; the deep-link path
              // still routes to /join full-screen (InvitePasteScreen).
              child: OnboardJoinStep(onBack: _backToMenu),
            ),
            OnboardStepBody(
              title: l.onboardTileChannelTitle,
              onBack: _backToMenu,
              child: ChannelJoinStep(onBack: _backToMenu),
            ),
          ],
        ),
      ],
    );
  }
}
