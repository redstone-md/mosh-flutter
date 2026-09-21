// DmScreen AppBar header: the two-line title (peer name + fingerprint
// lock + status subtitle) and the `actions:` row (mobile search, kebab,
// phone, peer-status, close).
//
// The fingerprint is a VALUE both sides share (the creator's), so the
// header shows a small lock next to the name; tapping it opens the
// shared fingerprint dialog (emoji quartet + hex + compare hint). There
// is no confirm state anywhere: a local confirm would change nothing,
// so the surface stays read-only.
//
// The header owns no ephemeral state; screen-level concerns arrive as
// callbacks (onLeave, onStartCall, onOpenPeerStatus).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/state/session_providers.dart';
import 'package:mosh/src/features/conversation/conversation_tools.dart';
import 'package:mosh/src/features/fingerprint/fingerprint_lock.dart';
import 'package:mosh/src/features/conversation/chat_header_menu.dart';
import 'package:mosh/src/features/conversation/conversation_helpers.dart';
import 'package:mosh/src/features/shared/rail_back_button.dart';
import 'package:mosh/src/features/conversation/dm_state.dart';
import 'package:mosh/src/features/conversation/peer_label.dart';

/// The DmScreen AppBar header: peer display name (+ fingerprint lock),
/// the connection status subtitle, and the `actions:` row.
///
/// ctor:
///   - [sessionId] -- the DM session identity; the title fallback when
///     the snapshot has not resolved yet, and the family arg for the
///     watch.
///   - [onOpenPeerStatus] -- screen toggles `_showPeerStatus = true`.
///   - [onLeave] -- screen's `_requestLeave` (confirm dialog -> `_leave`).
///   - [mobileSearchOpen] + [onToggleMobileSearch] -- the mobile search
///     panel open state, owned by the screen (the body's
///     MobileConversationSearch reads the same value), passed down so
///     the toggle button in this header's `actions:` row can render +
///     forward.
///   - [filter] + [onFilter] -- the conversation filter, owned by the
///     screen (the body's ConversationTools + the kebab's filter toggle
///     both drive it), so the screen passes the current value + a
///     setter down.
///   - [onStartCall] -- screen's startVoiceCall wrapper (needs ref +
///     sessionId + a context SnackBar on error).
class DmScreenHeader extends ConsumerStatefulWidget
    implements PreferredSizeWidget {
  const DmScreenHeader({
    super.key,
    required this.sessionId,
    required this.onOpenPeerStatus,
    required this.onLeave,
    required this.mobileSearchOpen,
    required this.onToggleMobileSearch,
    required this.filter,
    required this.onFilter,
    required this.onStartCall,
  });

  final String sessionId;
  final VoidCallback onOpenPeerStatus;
  final VoidCallback onLeave;
  final bool mobileSearchOpen;
  final VoidCallback onToggleMobileSearch;
  final ConversationFilter filter;
  final ValueChanged<ConversationFilter> onFilter;
  final VoidCallback onStartCall;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  ConsumerState<DmScreenHeader> createState() => _DmScreenHeaderState();
}

class _DmScreenHeaderState extends ConsumerState<DmScreenHeader> {
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final async = ref.watch(activeSessionProvider(widget.sessionId));
    final s = async.value;
    // What the runtime has proven about the contact, in one sentence.
    final status = s == null ? '' : dmStateSentence(l, s.state, s.transport);
    final fingerprint = s?.fingerprint ?? '';
    return AppBar(
      toolbarHeight: chatHeaderHeight(context),
      titleTextStyle: chatTitleStyle(context),
      leading: railBackButton(context),
      title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Peer name with the fingerprint lock beside it (the lock
            // renders nothing while the fingerprint is empty). A null
            // snapshot (not loaded yet) keeps the bare sessionId.
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(s == null ? widget.sessionId : peerLabel(l, s)),
                ),
                FingerprintLock(
                  fingerprint: fingerprint,
                  hint: l.inviteFingerprintHint,
                ),
              ],
            ),
            SizedBox(height: chatSubtitleGap(context)),
            Text(status, style: chatSubtitleStyle(context)),
          ]),
      actions: [
        // Mobile search toggle -- gated on the mobile breakpoint; on
        // desktop the toggle is absent and the desktop
        // ConversationTools row renders in the body.
        if (isMobileBreakpoint(context))
          MobileSearchToggle(
            open: widget.mobileSearchOpen,
            onToggle: widget.onToggleMobileSearch,
            l: l,
          ),
        // Mobile kebab menu: the filter toggle + Delete chat (danger).
        ChatHeaderMenu(
          l: l,
          actions: [
            if (widget.filter == ConversationFilter.attachments)
              ChatHeaderMenuAction(
                label: l.chatFilterAll,
                icon: Icons.chat_bubble_outline,
                onSelect: () => widget.onFilter(ConversationFilter.all),
              )
            else
              ChatHeaderMenuAction(
                label: l.chatFilterAttachments,
                icon: Icons.attach_file,
                onSelect: () => widget.onFilter(ConversationFilter.attachments),
              ),
            ChatHeaderMenuAction(
              label: l.deleteChatConfirm,
              icon: Icons.delete_outline,
              danger: true,
              onSelect: widget.onLeave,
            ),
          ],
        ),
        // Start-call button.
        IconButton(
          icon: const Icon(Icons.phone, size: 18),
          tooltip: l.callStart,
          onPressed: widget.onStartCall,
        ),
        IconButton(
          icon: const Icon(Icons.electrical_services, size: 18),
          tooltip: l.openPeerStatus,
          onPressed: widget.onOpenPeerStatus,
        ),
        // Leave/close-session button, desktop only; on mobile the
        // kebab's "Delete chat" item is the close entry point instead.
        if (!isMobileBreakpoint(context))
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            tooltip: l.shellCloseSession,
            onPressed: widget.onLeave,
          ),
      ],
    );
  }
}
