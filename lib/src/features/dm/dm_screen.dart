// S4.7: DM screen for slice-one. App bar (peer display name) + scrolling
// message list (own vs peer by alignment/color; own = `fromDevice ==
// snapshot.displayName`, the React `from_device === ownDeviceName` rule) +
// composer + crypto footer. Mirrors the React ActiveDmChat
// (ActiveChatPanes.tsx + MessageLists.tsx + ChatComposer.tsx).
//
// Grouping: React `DmMessageRow` rule -- a 5-min window groups consecutive
// same-`fromDevice` rows (only the first renders an avatar + sender-meta;
// grouped rows render a spacer). Chronological, then reversed (newest at
// bottom). MLS badge in the sender meta ([SenderMeta]).
//
// Search + filter: React `filterMessages` BEFORE grouping, then reverses
// (matching `DmChatList`/`MessageLists`). ConversationTools sits above the
// list; `DmSearchEmpty` renders when the filter hid every row.
//
// Attachments (Gap 2): each row wires an `AttachmentCard` via
// `_attachmentCallbacks` -- download/cancel hit the Gateway seam (Gap 4),
// open routes through the in-app `MediaViewer` (1-1 with React
// `openAttachment`): already-downloaded opens show the local file,
// streamable media streams `moshmedia.localhost` while downloading, and
// image/other arms a pending-open resolved by the `ref.listen` once the
// download finishes. Deferred: call events, the full poll loop.
//
// Server state: activeSessionProvider (ADR 0010); send calls
// gateway.sendMessage via gatewayProvider (ADR 0013) and invalidates the
// family entry. Composer + search/filter + peer-status drawer are widget-
// local (ConsumerStatefulWidget). Slice-one: refresh on init + after send.
library;

import 'dart:async';
import 'dart:io';
import 'dart:convert' show base64Encode;

import 'package:mosh/src/features/shared/voice_composer.dart';
import 'package:mosh/src/rust/attachment_runtime.dart' show VoiceMeta;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/dm/dm_message_list.dart';
import 'package:mosh/src/features/dm/dm_screen_header.dart';
import 'package:mosh/src/features/dm/dm_screen_body.dart';
import 'package:mosh/src/features/dm/voice_call_layer.dart' show startVoiceCall;
import 'package:mosh/src/features/shared/attachment_picker.dart';
import 'package:mosh/src/features/shared/attachment_launcher.dart';
import 'package:mosh/src/features/shared/attachment_open.dart';
import 'package:mosh/src/features/shared/confirm_dialog.dart';
import 'package:mosh/src/features/shared/attachment_media_src.dart';
import 'package:mosh/src/features/shared/media_viewer.dart'
    show showMediaViewer;
import 'package:mosh/src/gateway/gateway.dart' show Gateway;
import 'package:mosh/src/features/shared/chat_actions.dart';
import 'package:mosh/src/features/dm/conversation_tools.dart';
import 'package:mosh/src/routing/app_router.dart' show AppRoutes;
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart'
    show AttachmentView, AttachmentDescriptor, AttachmentState, SessionSnapshot;
import 'package:mosh/src/state/gateway_provider.dart';
import 'package:mosh/src/state/session_providers.dart';
import 'package:mosh/src/state/active_conversation_key_provider.dart';
import 'package:mosh/src/util/format.dart' show readableError;

part 'dm_screen_actions.dart';

/// Direct-message screen for one session. Own vs peer is inferred from
/// `ChatMessage.fromDevice` vs the session's `displayName` (React's
/// `from_device === ownDeviceName` rule).
class DmScreen extends ConsumerStatefulWidget {
  const DmScreen({super.key, required this.sessionId});

  final String sessionId;

  @override
  ConsumerState<DmScreen> createState() => _DmScreenState();
}

class _DmScreenState extends ConsumerState<DmScreen> with DmScreenActions {
  // Ephemeral search + filter (React ConversationTools); widget-local per
  // ADR 0010; drive `filterDmMessages` before grouping.
  String _search = '';
  ConversationFilter _filter = ConversationFilter.all;
  bool _showPeerStatus = false;
  // Mobile search panel open state -- 1-1 with React `useMobileSearchPanel`
  // (ActiveChatHeader.tsx L103-111): a `useState(false)` reset to false on
  // `resetKey` (sessionId) change. The AppBar `MobileSearchToggle` flips it;
  // the body renders `MobileConversationSearch` while true. Gated on the
  // mobile breakpoint (the toggle only renders on mobile), so on desktop this
  // stays false and the desktop `ConversationTools` row renders instead.
  bool _mobileSearchOpen = false;

  @override
  void initState() {
    super.initState();
    // Mark this DM as the active conversation so the unread lifecycle clears
    // its badge on the next focused poll (mirrors React's
    // `activeConversationKey = conversationKey(active)` on screen open).
    // Deferred via a microtask because Riverpod forbids modifying a
    // provider during a widget lifecycle method (initState/build/dispose)
    // -- the set lands after the current build, matching React's effect
    // running after render.
    Future.microtask(() {
      if (!mounted) return;
      ref
          .read(activeConversationKeyProvider.notifier)
          .set('dm:${widget.sessionId}');
    });
  }

  @override
  void dispose() {
    _composer.dispose();
    super.dispose();
  }

  // Reset the mobile search panel when the session changes -- 1-1 with React's
  // `useMobileSearchPanel` `resetKey` effect (ActiveChatHeader.tsx L107-109:
  // `useEffect(() => { setOpen(false); }, [resetKey])`). The session id is
  // the reset key; if it changed (the same widget is reused for a different
  // DM), the open search panel closes so the new conversation does not inherit
  // a stale open mobile search.
  @override
  void didUpdateWidget(covariant DmScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.sessionId != oldWidget.sessionId) {
      _mobileSearchOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Resolve the pending-open descriptor 1-1 with React's `useEffect`
    // (use-chat-orchestration.ts L267-283): when the session snapshot's
    // attachments update and a pending open is armed, find the matching
    // view; if its `localPath` appeared, show the viewer + clear the
    // pending; if it went failed/cancelled, drop the pending. `ref.listen`
    // is idempotent across rebuilds (Riverpod dedupes the subscription).
    ref.listen<AsyncValue<SessionSnapshot>>(
      activeSessionProvider(widget.sessionId),
      (_, next) {
        final attachments = next.value?.attachments;
        if (attachments == null || attachments.isEmpty) return;
        _resolvePendingOpen(attachments);
      },
    );
    return Scaffold(
      appBar: DmScreenHeader(
        sessionId: widget.sessionId,
        onOpenPeerStatus: () => setState(() => _showPeerStatus = true),
        onLeave: _requestLeave,
        mobileSearchOpen: _mobileSearchOpen,
        onToggleMobileSearch: () =>
            setState(() => _mobileSearchOpen = !_mobileSearchOpen),
        filter: _filter,
        onFilter: (value) => setState(() => _filter = value),
        onStartCall: () async {
          final err = await startVoiceCall(ref, widget.sessionId);
          if (!context.mounted) return;
          if (err != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(readableError(err))),
            );
          }
        },
        confirmedFingerprints: _confirmedFingerprints,
        onConfirmFingerprint: _confirmFingerprint,
      ),
      body: DmScreenBody(
        sessionId: widget.sessionId,
        chatError: _chatError,
        canRetrySend: _canRetrySend,
        onRetrySend: _canRetrySend ? _retryFailedSend : null,
        search: _search,
        onSearch: (value) => setState(() => _search = value),
        filter: _filter,
        onFilter: (value) => setState(() => _filter = value),
        mobileSearchOpen: _mobileSearchOpen,
        onCloseMobileSearch: () => setState(() => _mobileSearchOpen = false),
        sending: _sending,
        onAttach: _sendAttachment,
        onAttachmentPickError: _onAttachmentPickError,
        composer: _composer,
        onSend: _send,
        onSendVoice: _sendVoice,
        onVoiceError: _onVoiceError,
        showPeerStatus: _showPeerStatus,
        onClosePeerStatus: () => setState(() => _showPeerStatus = false),
        onRefreshSession: () =>
            ref.invalidate(activeSessionProvider(widget.sessionId)),
        attachmentCallbacks: _attachmentCallbacks,
        onRetryMessage: _retryMessage,
      ),
    );
  }
}

/// One DM message row (React `DmMessageRow`): avatar (or a spacer when
/// grouped) + body column; non-grouped rows open with a sender-meta row.
/// Bubble (own/peer color + maxWidth 360), delivery ticks on own rows, and
/// the per-message AttachmentCard are in scope. Deferred: CallLogEntry, the
/// failed-message retry row (MlsBadge in the sender meta, [SenderMeta]).
