import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_icons.dart';
import 'package:mosh/src/app/mosh_theme.dart' show MoshColors;
import 'package:mosh/src/features/shared/conversation_action_error.dart'
    show ConversationActionError;
import 'package:mosh/src/features/sessions/sessions_rail_list.dart';
import 'package:mosh/src/features/sessions/sessions_list_controls.dart';
import 'package:mosh/src/features/sessions/rail_buttons.dart';
import 'package:mosh/src/features/sessions/rail_compact.dart';
import 'package:mosh/src/features/sessions/rail_item.dart';
import 'package:mosh/src/features/sessions/rail_notice.dart';
import 'package:mosh/src/features/sessions/sessions_rail_actions.dart';
import 'package:mosh/src/gateway/conversation_target.dart'
    show ConversationKind;
import 'package:mosh/src/routing/app_router.dart' show AppRoutes;
import 'package:mosh/src/state/conversation_providers.dart'
    show conversationListProvider, sessionsOf;

/// The chat list: the button that starts a conversation, the search and the
/// filters, one row per conversation, and settings under them.
class SessionsScreen extends ConsumerStatefulWidget {
  const SessionsScreen({super.key});

  @override
  ConsumerState<SessionsScreen> createState() => _SessionsScreenState();
}

class _SessionsScreenState extends ConsumerState<SessionsScreen> {
  final _searchText = TextEditingController();
  String _query = '';
  ConversationKind? _kind;

  @override
  void dispose() {
    _searchText.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final compact = RailCompactScope.of(context);
    final column = Padding(
      // Pinned controls inset themselves; the list insets its rows inside
      // the scroller, so its scrollbar runs in the right gutter and both
      // sides of a row stay [kRailPadding] from the edge.
      padding: const EdgeInsets.symmetric(vertical: kRailEdge),
      child: Column(children: _sections(context, compact)),
    );
    // The rail carries NO header of
    // its own; the shell titlebar sits above it.
    return Scaffold(
      backgroundColor: MoshColors.of(context).surfaceContainerLowest,
      // The rail carries no AppBar, so nothing else keeps it clear of the
      // status bar / camera cutout. Desktop gets that clearance from the
      // shell titlebar above it; the mobile shell is a bare IndexedStack, so
      // on Android 15+ (edge-to-edge is mandatory there) the first row drew
      // under the cutout. Inside the Scaffold, so surfaceContainerLowest still paints edge to
      // edge behind the status bar and only the content is inset.
      body: SafeArea(
        // While the pane animates wider than the strip, the strip keeps
        // its place at the start.
        child: compact
            ? Align(
                alignment: AlignmentDirectional.topStart,
                child: SizedBox(width: kRailCompactWidth, child: column))
            : column,
      ),
    );
  }

  List<Widget> _sections(BuildContext context, bool compact) {
    final l = AppLocalizations.of(context)!;
    final async = ref.watch(conversationListProvider(ConversationKind.dm));
    return <Widget>[
      // Starting a conversation is pinned above the list, outside the
      // scroller and independent of whether any conversation exists.
      _inset(RailNewButton(
          label: l.shellNewSession,
          onTap: () => openNewSessionAction(context, ref))),
      const SizedBox(height: kRailPadding),
      _inset(_search(l, compact)),
      // The search and the filters bring their own gap to the rows.
      if (compact) const SizedBox(height: kRailPadding),
      Expanded(
        child: SessionsRailList(
          dmSessions: sessionsOf(async.value),
          query: _query,
          kind: _kind,
          status: _status(async, l, compact),
        ),
      ),
      // Settings are pinned below the scroller, so they never scroll away.
      const SizedBox(height: kRailPadding),
      _inset(RailSettingsButton(
          label: l.settingsGearLabel,
          onTap: () => context.push(AppRoutes.settings))),
    ];
  }

  Widget _search(AppLocalizations l, bool compact) => compact
      ? CompactRailButton(
          icon: MoshIcons.search,
          label: l.chatListSearch,
          onTap: () => expandChatList(ref, focusSearch: true))
      : SessionsListControls(
          focusNode: ref.watch(chatListSearchFocusProvider),
          controller: _searchText,
          kind: _kind,
          onSearch: (value) => setState(() => _query = value),
          onKind: (value) => setState(() => _kind = value),
        );

  Widget? _status(
          AsyncValue<Object?> async, AppLocalizations l, bool compact) =>
      async.when<Widget?>(
        loading: () => SizedBox(
          height: kRailItemHeight,
          child: Center(
            child: CircularProgressIndicator(
              semanticsLabel: l.sessionsLoading,
            ),
          ),
        ),
        error: (e, _) => compact
            // A row of the list is as wide as the list; the button is not.
            ? Center(
                child: CompactRailButton(
                    icon: MoshIcons.error,
                    label: l.sessionsError,
                    ink: MoshColors.of(context).error,
                    onTap: _retry))
            : _failed(e, l),
        data: (_) => null,
      );

  /// The list could not be loaded. Only a bridge failure has a worded
  /// reason; anything else would show raw exception text, so the notice
  /// says what is safe instead.
  Widget _failed(Object error, AppLocalizations l) {
    final reason = ConversationActionError.of(error);
    return RailNotice(
      failed: true,
      title: l.sessionsError,
      detail: reason.kind == null ? l.sessionsErrorBody : reason.describe(l),
      actionLabel: l.sessionsRetry,
      onAction: _retry,
    );
  }

  void _retry() => ref
      .read(conversationListProvider(ConversationKind.dm).notifier)
      .refresh();

  Widget _inset(Widget child) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: kRailPadding),
      child: child);
}
