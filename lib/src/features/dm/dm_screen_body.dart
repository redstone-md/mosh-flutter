// DmScreen Scaffold body + overlays -- the 1-в-1 port of the React DM
// chat-pane body (private-dm-screen.tsx ~L337-513), extracted from
// `dm_screen.dart` to restore the 500-line headroom on the screen file.
// PURE REFACTOR: zero behavioral change vs the prior inline body block.
//
// Owns the ENTIRE `Scaffold.body` interior (SafeArea > Stack > Column
// [ChatErrorBanner, desktop ConversationTools | mobile
// MobileConversationSearch + MobileConversationFilterNotice, Expanded >
// ChatDropZone > async.when (loading/error/empty/DmSearchEmpty/
// DmMessageListView), ConversationComposer, crypto footer] + the
// `if (showPeerStatus) Positioned.fill(PeerStatusDrawer)` overlay + the
// `Positioned.fill(VoiceCallLayer)` overlay) and reads the session
// snapshot itself via `ref.watch(activeSessionProvider(widget.sessionId))`,
// so the screen no longer needs to pass `async`/`sessionForDrawer`/
// `errorForDrawer` in.
//
// Like [DmScreenHeader], the DM body owns NO ephemeral state of its own
// -- every piece of state it touches (search, filter, mobileSearchOpen,
// sending, composer, showPeerStatus) is shared with the screen (the
// AppBar toggle, the kebab, the header close), so the screen remains the
// single owner and passes the current value + a callback down. The
// send/attach/voice/retry/refresh/peer-status-close are screen-level
// concerns; the body calls back via [onAttach]/[onSend]/[onSendVoice]/
// [onVoiceError]/[onRetrySend]/[onRetryMessage]/[onRefreshSession]/
// [onClosePeerStatus]/[onCloseMobileSearch].
//
// The widget tree, comments (React file:line references), and gates are
// byte-identical to the pre-refactor body block. The [_Empty] helper
// (React DmChatList empty branch) moved here verbatim from
// `dm_screen.dart`.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/state/session_providers.dart';
import 'package:mosh/src/features/dm/conversation_tools.dart';
import 'package:mosh/src/features/dm/dm_message_list.dart';
import 'package:mosh/src/features/dm/peer_status_drawer.dart';
import 'package:mosh/src/features/dm/conversation_composer.dart';
import 'package:mosh/src/features/dm/voice_call_layer.dart' show VoiceCallLayer;
import 'package:mosh/src/state/voice_call_orchestrator_provider.dart'
    show ringtonePlayerProvider;
import 'package:mosh/src/features/shared/attachment_picker.dart';
import 'package:mosh/src/features/shared/chat_error_banner.dart';
import 'package:mosh/src/features/shared/chat_drop_zone.dart' show ChatDropZone;
import 'package:mosh/src/features/shared/voice_composer.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart'
    show AttachmentView;

/// The DmScreen `Scaffold.body` interior: the `SafeArea > Stack` block
/// (Column of error banner + desktop/mobile search/filter + Expanded
/// ChatDropZone > async.when message list + ConversationComposer + crypto
/// footer, plus the peer-status overlay and the VoiceCallLayer overlay).
/// Reads the session snapshot itself, so it is self-contained; the screen
/// passes only the `sessionId` + the shared state values + the
/// screen-level callbacks.
///
/// ctor:
///   - [sessionId] -- the DM session identity; the family arg for the
///     watch + the `sessionId` forwarded to [VoiceCallLayer] +
///     [onRefreshSession].
///   - [chatError] -- the screen's `_chatError`; non-null gates the
///     [ChatErrorBanner].
///   - [canRetrySend] + [onRetrySend] -- the banner's Retry button is
///     active iff [canRetrySend]; the screen precomputes
///     `_canRetrySend ? _retryFailedSend : null` so the body just forwards
///     the nullable callback (mirrors React
///     `canRetrySend ? retryFailedSend : undefined`).
///   - [search] + [onSearch] -- the search box value, owned by the screen
///     (the AppBar's desktop ConversationTools + mobile
///     MobileConversationSearch both drive it), passed down.
///   - [filter] + [onFilter] -- the conversation filter, owned by the
///     screen (the desktop ConversationTools + the mobile
///     MobileConversationFilterNotice + the kebab's filter toggle all
///     drive it), passed down.
///   - [mobileSearchOpen] + [onCloseMobileSearch] -- the mobile search
///     panel open state, owned by the screen (the AppBar's
///     MobileSearchToggle opens it; the body only CLOSES it via
///     MobileConversationSearch.onClose), passed down.
///   - [sending] -- the in-flight send flag; gates the ChatDropZone +
///     ConversationComposer busy state.
///   - [onAttach] -- the screen's `_sendAttachment` (a
///     [PickedAttachment] -> Gateway DM send seam), reused by both the
///     composer's paperclip and the ChatDropZone's drop handler.
///   - [onAttachmentPickError] -- the screen's `_onAttachmentPickError`
///     (surfaces the localized 50 MB limit via a SnackBar); reused by the
///     composer + the drop zone.
///   - [composer] -- the screen's `_composer` [TextEditingController].
///   - [onSend] -- the screen's `_send` (reads the composer then sends).
///   - [onSendVoice] -- the screen's `_sendVoice` (records + sends a voice
///     message).
///   - [onVoiceError] -- the screen's `_onVoiceError` (mic-permission /
///     start failures -> SnackBar).
///   - [showPeerStatus] + [onClosePeerStatus] -- the peer-status drawer
///     open state, owned by the screen (the AppBar's peer-status IconButton
///     opens it), passed down so this body can render the overlay + close
///     it.
///   - [onRefreshSession] -- the screen's refresh wrapper
///     (`ref.invalidate(activeSessionProvider(...))`); forwarded to
///     PeerStatusDrawer.onRefresh.
///   - [attachmentCallbacks] -- the screen's `_attachmentCallbacks` getter
///     (builds the per-row download/cancel/open callbacks); forwarded to
///     DmMessageListView.
///   - [onRetryMessage] -- the screen's `_retryMessage` (retries a failed
///     outbound DM message); forwarded to DmMessageListView.
class DmScreenBody extends ConsumerStatefulWidget {
  const DmScreenBody({
    super.key,
    required this.sessionId,
    required this.chatError,
    required this.canRetrySend,
    required this.onRetrySend,
    required this.search,
    required this.onSearch,
    required this.filter,
    required this.onFilter,
    required this.mobileSearchOpen,
    required this.onCloseMobileSearch,
    required this.sending,
    required this.onAttach,
    required this.onAttachmentPickError,
    required this.composer,
    required this.onSend,
    required this.onSendVoice,
    required this.onVoiceError,
    required this.showPeerStatus,
    required this.onClosePeerStatus,
    required this.onRefreshSession,
    required this.attachmentCallbacks,
    required this.onRetryMessage,
  });

  final String sessionId;
  final String? chatError;
  final bool canRetrySend;
  final VoidCallback? onRetrySend;
  final String search;
  final ValueChanged<String> onSearch;
  final ConversationFilter filter;
  final ValueChanged<ConversationFilter> onFilter;
  final bool mobileSearchOpen;
  final VoidCallback onCloseMobileSearch;
  final bool sending;
  final AttachmentPickedCallback onAttach;
  final AttachmentPickErrorCallback onAttachmentPickError;
  final TextEditingController composer;
  final VoidCallback onSend;
  final void Function(VoiceSend voice) onSendVoice;
  final ValueChanged<String> onVoiceError;
  final bool showPeerStatus;
  final VoidCallback onClosePeerStatus;
  final VoidCallback onRefreshSession;
  final DmAttachmentCallbacks Function(AttachmentView? view)
      attachmentCallbacks;
  final ValueChanged<String> onRetryMessage;

  @override
  ConsumerState<DmScreenBody> createState() => _DmScreenBodyState();
}

class _DmScreenBodyState extends ConsumerState<DmScreenBody> {
  // No body-local ephemeral state: every piece of state this body touches
  // (search, filter, mobileSearchOpen, sending, composer, showPeerStatus)
  // is shared with the screen (the AppBar toggle / kebab / header close),
  // so the screen owns it and passes the current value + a callback down.
  // The DM body therefore has no `_DmScreenBodyState` fields -- it is a
  // thin render of the body driven by `ref.watch` + the widget callbacks.

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final async = ref.watch(activeSessionProvider(widget.sessionId));
    final s = async.value;
    final sessionForDrawer = s;
    final errorForDrawer = async.hasError ? async.error.toString() : null;
    return SafeArea(
      child: Stack(
        children: [
          Column(
            children: [
              // Inline error banner (Gap 3) -- 1-1 with React
              // private-dm-screen.tsx L337-341
              // `{!showWelcome && error ? <ChatError message={error}
              // onRetry={canRetrySend ? retryFailedSend : undefined} /> :
              // null}`. The DM screen is never on the welcome state (it
              // always has a session), so the gate is just `chatError !=
              // null`. The Retry button is active iff [canRetrySend].
              if (widget.chatError != null)
                ChatErrorBanner(
                  message: widget.chatError!,
                  onRetry: widget.canRetrySend ? widget.onRetrySend : null,
                ),
              // Desktop search/filter row -- gated on the desktop
              // breakpoint (React hides `.conversation-tools-desktop` at
              // `max-width: 580px`). On desktop the row renders exactly as
              // before (byte-identical); on mobile the compact trio below
              // replaces it.
              if (!isMobileBreakpoint(context))
                ConversationTools(
                  search: widget.search,
                  filter: widget.filter,
                  onSearch: widget.onSearch,
                  onFilter: widget.onFilter,
                  l: l,
                ),
              // Mobile search/filter trio -- 1-1 with React
              // ActiveChatHeader `mobileSearchOpen ? <MobileConversation
              // Search/> : null` + the always-rendered
              // `MobileConversationFilterNotice` (null-collapses when
              // filter == all). Only on mobile (the toggle is gated in
              // the AppBar on the same breakpoint).
              if (isMobileBreakpoint(context)) ...[
                if (widget.mobileSearchOpen)
                  MobileConversationSearch(
                    search: widget.search,
                    onSearch: widget.onSearch,
                    onClose: widget.onCloseMobileSearch,
                    l: l,
                  ),
                MobileConversationFilterNotice(
                  filter: widget.filter,
                  onFilter: widget.onFilter,
                  l: l,
                ),
              ],
              // ChatDropZone wraps the message list so a desktop file drop
              // reuses the SAME onAttach/onError pair the paperclip uses
              // (ChatComposer.tsx:8-43 React parity). DM has no separate
              // ready flag -- async.when's data branch gates the list render.
              // Expanded stays the Column's direct child (Flex parent data);
              // ChatDropZone sits inside it wrapping the list content.
              Expanded(
                child: ChatDropZone(
                  disabled: widget.sending,
                  onAttach: widget.onAttach,
                  onError: widget.onAttachmentPickError,
                  child: async.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (e, _) => Center(child: Text(e.toString())),
                    data: (s) {
                      if (s.messages.isEmpty) return _Empty(l: l);
                      final filtered = filterDmMessages(
                          s.messages, widget.search, widget.filter);
                      if (filtered.isEmpty) {
                        return DmSearchEmpty(filter: widget.filter, l: l);
                      }
                      return DmMessageListView(
                        ownDeviceName: s.displayName,
                        grouped: groupDmMessages(filtered).reversed.toList(),
                        attachments: s.attachments,
                        attachmentCallbacks: widget.attachmentCallbacks,
                        onRetryMessage: widget.onRetryMessage,
                      );
                    },
                  ),
                ),
              ),
              ConversationComposer(
                controller: widget.composer,
                sending: widget.sending,
                placeholder: l.chatComposerPlaceholder,
                sendLabel: l.chatSendLabel,
                onSend: widget.onSend,
                attachLabel: l.chatAttachLabel,
                onAttach: widget.onAttach,
                onAttachmentPickError: widget.onAttachmentPickError,
                voiceRecordLabel: l.voiceRecordLabel,
                voiceDiscardLabel: l.voiceDiscardLabel,
                voiceStopLabel: l.voiceStopLabel,
                voicePlayLabel: l.voicePlayLabel,
                voiceSendLabel: l.voiceSendLabel,
                onSendVoice: widget.onSendVoice,
                onVoiceError: widget.onVoiceError,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Text(
                  l.chatCryptoFooter,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
          if (widget.showPeerStatus)
            Positioned.fill(
              child: PeerStatusDrawer(
                session: sessionForDrawer,
                error: errorForDrawer,
                refreshing: false,
                onRefresh: widget.onRefreshSession,
                onClose: widget.onClosePeerStatus,
              ),
            ),
          // Voice-call modals/overlay -- watches the per-session snapshot
          // and routes IncomingCallModal/OutgoingCallModal/CallOverlay
          // through showDialog based on pendingCall/outgoingCall/activeCall
          // (1-в-1 with React private-dm-screen.tsx L459-513). The layer
          // renders nothing itself; it only shows dialogs.
          Positioned.fill(
            child: VoiceCallLayer(
              sessionId: widget.sessionId,
              l: l,
              ringtone: ref.read(ringtonePlayerProvider),
            ),
          ),
        ],
      ),
    );
  }
}

/// Empty-state for a chat with no messages yet (React DmChatList empty
/// branch; chatEmptyTitle + chatEmptyBody).
class _Empty extends StatelessWidget {
  const _Empty({required this.l});
  final AppLocalizations l;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l.chatEmptyTitle,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(l.chatEmptyBody,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}
