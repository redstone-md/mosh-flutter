import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_dimensions.dart';
import 'package:mosh/src/features/conversation/conversation_tools.dart'
    show isMobileBreakpoint;
import 'package:mosh/src/features/onboarding/channel_join_step.dart';
import 'package:mosh/src/features/onboarding/chat_create_step.dart';
import 'package:mosh/src/features/onboarding/group_create_step.dart';
import 'package:mosh/src/features/onboarding/onboard_join_step.dart';
import 'package:mosh/src/features/onboarding/start/start_menu.dart';
import 'package:mosh/src/features/onboarding/start/start_pages.dart';
import 'package:mosh/src/features/onboarding/start/start_step.dart';
import 'package:mosh/src/features/shared/persistence_warning_banner.dart';
import 'package:mosh/src/routing/app_router.dart' show AppRoutes;
import 'package:mosh/src/state/persistence_warning_provider.dart';

/// The start menu's pages, in [StartPages] order.
enum OnboardStep { menu, chat, group, join, channel }

/// The chat pane's body when no conversation is open: the start menu and
/// its four steps, switched in place (the rail stays).
///
/// Every step stays mounted, so its typed text and created invite survive
/// a trip back to the menu. The storage warning, when there is one, heads
/// every page.
class NewSessionPanel extends ConsumerStatefulWidget {
  const NewSessionPanel({super.key, this.minHeight = 0});

  /// The pane height pages centre in, so switching pages keeps the menu
  /// and a step in one frame. The storage warning adds to it.
  final double minHeight;

  @override
  ConsumerState<NewSessionPanel> createState() => _NewSessionPanelState();
}

class _NewSessionPanelState extends ConsumerState<NewSessionPanel> {
  OnboardStep _step = OnboardStep.menu;

  void _go(OnboardStep step) => setState(() => _step = step);

  void _backToMenu() => _go(OnboardStep.menu);

  void _openChat(String sessionId) {
    if (!mounted || _step != OnboardStep.chat) return;
    if (ModalRoute.of(context)?.isCurrent == false) return;
    context.go(AppRoutes.dmFor(sessionId));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final warning = ref.watch(persistenceWarningProvider);
    // On a phone the menu's header stands close under the screen's top; a
    // step keeps the padding of the Wizard step card over its Back.
    final stepTop = isMobileBreakpoint(context) ? MoshSpace.s3 : 0.0;
    final steps = _steps(l);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (warning case AsyncData(:final value) when value != null) ...[
          PersistenceWarningBanner(warning: value),
          const SizedBox(height: 24),
        ],
        StartPages(
          index: _step.index,
          minHeight: widget.minHeight,
          pages: <Widget>[
            StartMenu(
              onPickChat: () => _go(OnboardStep.chat),
              onPickGroup: () => _go(OnboardStep.group),
              onPickJoin: () => _go(OnboardStep.join),
              onPickChannel: () => _go(OnboardStep.channel),
            ),
            for (final step in steps)
              Padding(padding: EdgeInsets.only(top: stepTop), child: step),
          ],
        ),
      ],
    );
  }

  /// The four steps the menu leads to, in the order of [OnboardStep].
  List<Widget> _steps(AppLocalizations l) => [
        StartStep(
          title: l.onboardTileChatTitle,
          subtitle: l.onboardChatStepBody,
          onBack: _backToMenu,
          child: ChatCreateStep(onOpened: _openChat),
        ),
        StartStep(
          title: l.onboardTileGroupTitle,
          subtitle: l.onboardGroupStepBody,
          onBack: _backToMenu,
          child: const GroupCreateStep(),
        ),
        StartStep(
          title: l.onboardTileJoinTitle,
          subtitle: l.onboardJoinStepBody,
          onBack: _backToMenu,
          // Deep links still open /join full-screen.
          child: const OnboardJoinStep(),
        ),
        StartStep(
          title: l.onboardTileChannelTitle,
          subtitle: l.onboardChannelStepLead,
          onBack: _backToMenu,
          child: const ChannelJoinStep(),
        ),
      ];
}
