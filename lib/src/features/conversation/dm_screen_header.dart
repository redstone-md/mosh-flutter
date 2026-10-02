// DmScreen AppBar header: the two-line title (peer name + fingerprint
// lock + status subtitle) and the DM-specific action (the call button).
// The AppBar skeleton lives in the shared ConversationAppBar.
//
// The fingerprint is a VALUE both sides share (the creator's), so the
// header shows a small lock next to the name; tapping it opens the
// shared fingerprint dialog (emoji quartet + hex + compare hint).
//
// The header owns no ephemeral state; screen-level concerns arrive as
// callbacks (onLeave, onStartCall, onOpenPeerStatus).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/state/session_providers.dart';
import 'package:mosh/src/features/conversation/conversation_tools.dart';
import 'package:mosh/src/features/fingerprint/fingerprint_lock.dart';
import 'package:mosh/src/features/conversation/conversation_app_bar.dart';
import 'package:mosh/src/features/conversation/conversation_header_title.dart';
import 'package:mosh/src/features/conversation/dm_state.dart';
import 'package:mosh/src/features/conversation/peer_label.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart'
    show DmSessionState;

/// The DmScreen AppBar header: peer display name (+ fingerprint lock),
/// the connection status subtitle, and the call button.
///
/// ctor:
///   - [sessionId] -- the DM session identity; the title fallback when
///     the snapshot has not resolved yet, and the family arg for the
///     watch.
///   - [onOpenPeerStatus] -- screen toggles `_showPeerStatus = true`.
///   - [onLeave] -- screen's `_requestLeave` (confirm dialog -> `_leave`).
///   - [mobileSearchOpen] + [onToggleMobileSearch] -- the mobile search
///     panel open state, owned by the screen; forwarded to the shared
///     ConversationAppBar.
///   - [filter] + [onFilter] -- the conversation filter, owned by the
///     screen; forwarded to the shared kebab's filter toggle.
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
    return ConversationAppBar(
      peerOnline: s?.state == DmSessionState.connected,
      avatarName: s == null ? widget.sessionId : peerLabel(l, s),
      title: ConversationHeaderTitle(
        name: s == null ? widget.sessionId : peerLabel(l, s),
        subtitle: status,
        onOpenDetails: widget.onOpenPeerStatus,
        nameAction: FingerprintLock(
            fingerprint: fingerprint,
            hint: l.inviteFingerprintHint,
            besideName: true),
      ),
      onOpenPeerStatus: widget.onOpenPeerStatus,
      onRequestLeave: widget.onLeave,
      filter: widget.filter,
      onFilter: widget.onFilter,
      mobileSearchOpen: widget.mobileSearchOpen,
      onToggleMobileSearch: widget.onToggleMobileSearch,
      leaveMenuLabel: l.deleteChatConfirm,
      leaveMenuIcon: Icons.delete_outline,
      inlineActions: [
        // Primary action precedes search and the menu in every header.
        IconButton(
          icon: const Icon(Icons.phone_outlined, size: 20),
          tooltip: l.callStart,
          onPressed: widget.onStartCall,
        ),
      ],
    );
  }
}
