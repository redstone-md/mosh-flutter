// Inline NewSessionPanel -- 1-to-1 with React `NewSessionPanel`
// (src/features/private-dm/NewSessionPanel.tsx:18-67), rendered in the
// desktop chat-pane welcome when no conversation is open: an `OnboardStep`
// enum, the PersistenceWarningBanner, OnboardMenu(onPick -> setStep), and
// the four steps each with onBack: backToMenu. The rail stays mounted.
//
// Flutter parity: an [IndexedStack] keeps all five step widgets MOUNTED
// simultaneously, so each step's controllers/state survive a menu
// round-trip -- mirrors React's lifted per-step state (joinValue /
// channelValue / groupLabelValue) by keeping the widgets alive instead of
// lifting the text values; equivalent UX.
//
// The banner renders inside the scroll (like React's `.onboard-shell`
// placement, NewSessionPanel.tsx:46) so it scrolls with the step body.
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
/// ConstrainedBox(maxWidth: 460)), the same composition OnboardingScreen
/// uses, so the inline panel renders identically to the onboarding menu.
///
/// Per-step state survives a menu round-trip via the [IndexedStack] keep-
/// alive (all five widgets stay mounted: the create step's invite, the join
/// step's pasted link all survive -- React lifts them, Flutter keeps the
/// widgets). Do NOT remove the keep-alive.
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
        if (warning
            case AsyncData(
              :final value,
            ) when value != null) ...<Widget>[
          PersistenceWarningBanner(warning: value),
          const SizedBox(height: 12),
        ],
        // IndexedStack keep-alive: all five step widgets stay mounted, so
        // each step's controllers/state survive a menu round-trip. No
        // Expanded: the wrapping SingleChildScrollView makes this Column
        // unbounded, and an Expanded (non-zero flex) there would throw --
        // the IndexedStack instead sizes to its tallest step and scrolls
        // with the banner.
        IndexedStack(
          index: _step.index,
          children: <Widget>[
            OnboardMenu(
              onPickChat: () => setState(() => _step = OnboardStep.chat),
              onPickGroup: () => setState(() => _step = OnboardStep.group),
              onPickChannel: () => setState(() => _step = OnboardStep.channel),
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
