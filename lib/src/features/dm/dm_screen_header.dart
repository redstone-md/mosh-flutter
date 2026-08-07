// DmScreen AppBar header -- the 1-в-1 port of React `ActiveChatHeader`
// (ActiveChatPanes.tsx ActiveDmChat ~L300-340), extracted from
// `dm_screen.dart` to restore the 500-line headroom on the screen file.
// PURE REFACTOR: zero behavioral change vs the prior inline AppBar block.
//
// Owns the ENTIRE AppBar (two-line title Column + actions: FingerprintBadge
// + MobileSearchToggle + ChatHeaderMenu + phone + peer-status + close) and
// reads the session snapshot itself via
// `ref.watch(activeSessionProvider(widget.sessionId))`, so the screen no
// longer needs to pass `async`/`mlsState`/`fingerprint`/`confirmed` in.
//
// Unlike [GroupScreenHeader], the DM header owns NO ephemeral state of its
// own -- every piece of state it touches (`_mobileSearchOpen`,
// `_showPeerStatus`, `_confirmedFingerprints`, `_filter`) is shared with
// the screen's body (MobileConversationSearch / PeerStatusDrawer /
// ConversationTools / kebab all read or mutate it), so the screen remains
// the single owner and passes the current value + a callback down. The
// fingerprint-confirm + leave + start-call + peer-status-toggle are
// screen-level concerns; the header calls back via [onConfirmFingerprint]
// / [onLeave] / [onStartCall] / [onOpenPeerStatus].
//
// The title template, FingerprintBadge, MobileSearchToggle gate,
// ChatHeaderMenu action list (filter toggle + confirm + delete), phone
// IconButton, peer-status IconButton, and the desktop-gated close IconButton
// are byte-identical to the pre-refactor AppBar block.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/state/session_providers.dart';
import 'package:mosh/src/features/dm/conversation_tools.dart';
import 'package:mosh/src/features/dm/fingerprint_badge.dart';
import 'package:mosh/src/features/dm/chat_header_menu.dart';
import 'package:mosh/src/features/dm/dm_helpers.dart';
import 'package:mosh/src/features/shared/rail_back_button.dart';
import 'package:mosh/src/features/dm/peer_label.dart';

/// The DmScreen AppBar header: the two-line title Column (peer display name
/// + subtitle) plus the `actions:` row (FingerprintBadge, MobileSearchToggle,
/// ChatHeaderMenu, phone, peer-status, close). Reads the session snapshot
/// itself, so it is self-contained; the screen passes only the `sessionId`
/// + the screen-level callbacks + the shared open/filter/confirmed values.
///
/// ctor:
///   - [sessionId] -- the DM session identity; the title fallback when the
///     snapshot has not resolved yet, and the family arg for the watch.
///   - [onOpenPeerStatus] -- screen toggles `_showPeerStatus = true`.
///   - [onLeave] -- screen's `_requestLeave` (confirm dialog -> `_leave`).
///   - [mobileSearchOpen] + [onToggleMobileSearch] -- the mobile search
///     panel open state, owned by the screen (mirrors React
///     `useMobileSearchPanel` in ActiveChatHeader); the toggle button
///     renders in this header's `actions:` row, so the screen passes the
///     current value + a toggle callback down.
///   - [filter] + [onFilter] -- the conversation filter, owned by the screen
///     (the body's ConversationTools + the kebab's filter toggle both drive
///     it), so the screen passes the current value + a setter down.
///   - [onStartCall] -- screen's startVoiceCall wrapper (needs ref +
///     sessionId + a context SnackBar on error).
///   - [confirmedFingerprints] -- the screen's confirmed-fingerprint set
///     (read-only here); the header only READS it to compute `confirmed`.
///   - [onConfirmFingerprint] -- screen's `_confirmFingerprint`.
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
    required this.confirmedFingerprints,
    required this.onConfirmFingerprint,
  });

  final String sessionId;
  final VoidCallback onOpenPeerStatus;
  final VoidCallback onLeave;
  // Mobile search panel open state + toggle -- owned by the screen (the
  // body's MobileConversationSearch reads the same value), passed down so
  // the toggle button in this header's `actions:` row can render + forward.
  final bool mobileSearchOpen;
  final VoidCallback onToggleMobileSearch;
  // Conversation filter + onFilter -- owned by the screen (the body's
  // ConversationTools + this header's kebab both drive it), passed down
  // mirroring the mobileSearchOpen/onToggleMobileSearch pair.
  final ConversationFilter filter;
  final ValueChanged<ConversationFilter> onFilter;
  // Start-call wrapper -- the screen owns it because it needs ref +
  // sessionId + a context SnackBar on error (mirrors the prior inline
  // `onPressed` that called `startVoiceCall(ref, widget.sessionId)`).
  final VoidCallback onStartCall;
  // Confirmed-fingerprint set (read-only) + confirm callback -- owned by
  // the screen (`_leave` cleanup mutates it; the body does not), passed
  // down so the header can compute `confirmed` + wire the confirm actions.
  final Set<String> confirmedFingerprints;
  final VoidCallback onConfirmFingerprint;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  ConsumerState<DmScreenHeader> createState() => _DmScreenHeaderState();
}

class _DmScreenHeaderState extends ConsumerState<DmScreenHeader> {
  // No header-local ephemeral state: every piece of state this header
  // touches (mobileSearchOpen, showPeerStatus, confirmedFingerprints,
  // filter) is shared with the screen's body, so the screen owns it and
  // passes the current value + a callback down. The DM header therefore
  // has no `_DmScreenHeaderState` fields -- it is a thin render of the
  // AppBar driven by `ref.watch` + the widget callbacks.

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final async = ref.watch(activeSessionProvider(widget.sessionId));
    final s = async.value;
    final mlsState = s?.state ?? '';
    final fingerprint = s?.fingerprint ?? '';
    final confirmed = fingerprint.isNotEmpty &&
        widget.confirmedFingerprints.contains(widget.sessionId);
    return AppBar(
      toolbarHeight: chatHeaderHeight(context),
      titleTextStyle: chatTitleStyle(context),
      leading: railBackButton(context),
      title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
         children: [
            // React `peerLabel` (private-dm-screen.tsx:535-543): peer
            // name -> "peer" -> "invite sent"/"joining", with the Flutter
            // `peerDisplayName` short-circuit. A null snapshot (not loaded
            // yet) keeps the bare sessionId like before.
            Text(s == null ? widget.sessionId : peerLabel(l, s)),
            SizedBox(height: chatSubtitleGap(context)),
            Text(
                confirmed
                    ? l.dmSubtitleConfirmed(mlsState)
                    : l.dmSubtitleUnverified(mlsState),
                style: chatSubtitleStyle(context)),
          ]),
      actions: [
        FingerprintBadge(
            fingerprint: fingerprint,
            confirmed: confirmed,
            onConfirm: widget.onConfirmFingerprint),
        // Mobile search toggle -- 1-1 with React `MobileSearchToggle`
        // (ActiveChatHeader.tsx L113-131): a ghost icon button in the
        // header `actions:` that opens/closes the mobile search panel.
        // Gated on the mobile breakpoint (the CSS `chat-mobile-only`
        // class hides it on desktop); on desktop the toggle is absent and
        // the desktop `ConversationTools` row renders in the body. Placed
        // after the FingerprintBadge (React `beforeSearchActions`) and
        // before the phone/peer-status/close buttons (React
        // `afterSearchActions`), mirroring the React header order.
        if (isMobileBreakpoint(context))
          MobileSearchToggle(
            open: widget.mobileSearchOpen,
            onToggle: widget.onToggleMobileSearch,
            l: l,
          ),
        // Mobile kebab menu -- 1-1 with React `ChatHeaderMenu`
        // (ChatHeaderMenu.tsx) prepended with the filter toggle via
        // `conversationMenuActions` (ActiveChatHeader.tsx ~L155-170).
        // Self-gates to mobile (the widget returns SizedBox.shrink() on
        // desktop); React places it last in `chat-header-actions`, so it
        // sits rightmost on mobile. The DM `menuActions` (ActiveChatPanes
        // ActiveDmChat ~L38-49): confirm/confirmed fingerprint (disabled
        // when confirmed; onSelect -> onConfirm -> _confirmFingerprint)
        // + Delete chat (danger tone; onSelect -> onClose ->
        // _requestLeave). The filter toggle is FIRST: if the current
        // filter is "attachments" the item is "All" (IconMessageCircle ->
        // Icons.chat_bubble_outline) -> onFilter(all); otherwise "Files"
        // (IconPaperclip -> Icons.attach_file) -> onFilter(attachments).
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
              label:
                  confirmed ? l.inviteConfirmedButton : l.inviteConfirmButton,
              icon: Icons.verified_user,
              disabled: confirmed,
              onSelect: widget.onConfirmFingerprint,
            ),
            ChatHeaderMenuAction(
              label: l.deleteChatConfirm,
              icon: Icons.delete_outline,
              danger: true,
              onSelect: widget.onLeave,
            ),
          ],
        ),
        // Start-call button -- 1-в-1 with React's `onStartCall` header
        // action (private-dm-screen.tsx L382 -> useVoiceCallOrchestration
        // startCall). Icons.phone mirrors tabler's IconPhone; the
        // outgoing-call modal opens once the snapshot reflects the
        // `outgoing_call` field (the VoiceCallLayer watches it).
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
        // Leave/close-session button -- 1-в-1 with React's DM leave button
        // in ActiveChatHeader `afterSearchActions` (ActiveChatPanes.tsx
        // L122-130: IconX, aria-label/title = `shellText.closeSession`,
        // onClick = closeFlow.closeActive -> _requestLeave). Placed LAST in
        // AppBar `actions` so it sits rightmost (React's
        // afterSearchActions is right-of-search, so the leave button is
        // the rightmost header button). Icons.close mirrors React's IconX;
        // size 18 matches the peer-status IconButton for header
        // consistency (React uses 16, but the sibling button is 18 here).
        // React marks this `chat-desktop-only`; on mobile the kebab's
        // "Delete chat" item (above) is the close entry point instead.
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
