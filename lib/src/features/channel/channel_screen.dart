// S5-1: ChannelScreen route shell -- the minimal, reachable surface for a
// public channel. Mirrors how DmScreen (S4.7) was built surface-by-surface:
// AppBar (channel name + leave IconButton) + a scrolling message list (own
// vs others by FINGERPRINT, not display name -- channels are multi-party so
// names are not unique) + a composer. SHELL ONLY.
//
// 1-1 with the React channel pane (ActiveChatPanes.tsx ActiveChannelChat):
// AppBar (channel name + leave IconButton) + PublicNotice banner +
// ConversationTools (search/filter) + message list (own vs others by
// FINGERPRINT) + composer + peer-status drawer overlay.
//
// Own-vs-others rule (React MessageLists.tsx ChannelChatList):
// own = message.fromFingerprint == channel.deviceFingerprint. Fingerprint
// comparison (NOT display name) is the key correctness point -- channels
// are multi-party, so two members could share a display name but never a
// device fingerprint. Sender-meta grouping (5-min, same-fingerprint) +
// MultiPartySenderMeta render in channel_message_row.dart.
//
// ConversationTools search/filter is widget-local (`_search` / `_filter`);
// the screen applies `filterChannelMessages` BEFORE `groupChannelMessages`
// (React's filter-then-group order) with the shared `DmSearchEmpty` branch
// when the filter hides every row.
//
// AGENTS.md state separation: the BUSINESS orchestration state (sending /
// offerBusy / offeredFingerprints / chatError / pendingOpen / lastFailedSend
// + the send/retry/attachment/voice/leave/peer-DM/open-attachment methods)
// lives in [ChannelController] (channel_controller.dart), a Riverpod
// Notifier keyed by the channel name. This screen keeps ONLY the UI state
// (`_composer` / `_showPeerStatus` / `_mobileSearchOpen` / `_search` /
// `_filter`) + the lifecycle (initState activeConversationKey set, dispose
// composer, didUpdateWidget mobile-search reset) + navigation (the controller
// returns results -- [ChannelLeaveResult] / [ChannelPeerDmResult] -- and the
// screen does `context.go`) + the composer-clear-on-success (the controller
// returns the sent body via [ChannelSendOutcome]; the screen clears
// `_composer` iff it still equals it -- React parity) + the SnackBar error
// surfaces (`_onVoiceError` / `_onAttachmentPickError`) + the MediaViewer
// open (the controller returns [ChannelOpenResult] / [ChannelPendingResolution]
// intents; the screen calls `showMediaViewer`). The controller never
// navigates and never touches the composer.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/dm/conversation_tools.dart';
import 'package:mosh/src/features/shared/attachment_picker.dart';
import 'package:mosh/src/features/shared/confirm_dialog.dart';
import 'package:mosh/src/features/shared/media_viewer.dart'
    show showMediaViewer;
import 'package:mosh/src/routing/app_router.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart'
    show AttachmentView, AttachmentDescriptor;
import 'package:mosh/src/rust/channel_runtime.dart';
import 'package:mosh/src/state/channel_group_providers.dart';
import 'package:mosh/src/state/active_conversation_key_provider.dart';

import 'package:mosh/src/features/channel/channel_controller.dart';
import 'package:mosh/src/features/channel/channel_screen_body.dart';

/// Channel screen for one public channel. Own vs others is inferred from
/// `ChannelMessage.fromFingerprint` vs the channel's `deviceFingerprint`
/// (React's `from_fingerprint === channel.device_fingerprint` rule -- NOT
/// display name, since channels are multi-party). Business orchestration
/// state + methods are delegated to [ChannelController]; this widget owns
/// UI state + navigation + the composer-clear-on-success.
class ChannelScreen extends ConsumerStatefulWidget {
  const ChannelScreen({super.key, required this.name});

  final String name;

  @override
  ConsumerState<ChannelScreen> createState() => _ChannelScreenState();
}

class _ChannelScreenState extends ConsumerState<ChannelScreen> {
  final TextEditingController _composer = TextEditingController();
  bool _showPeerStatus = false;
  // Mobile search panel open state -- 1-1 with React `useMobileSearchPanel`
  // (ActiveChatHeader.tsx L103-111): `useState(false)` reset on `resetKey`
  // change. For a channel the reset key is the channel name (`widget.name`),
  // the channel's conversation identity; the AppBar toggle flips it and the
  // body renders `MobileConversationSearch` while true. Gated on the mobile
  // breakpoint (the toggle only renders on mobile).
  bool _mobileSearchOpen = false;
  // Ephemeral search + filter (React ConversationTools); widget-local per
  // ADR 0010; drive [filterChannelMessages] before grouping, mirroring
  // DmScreen's `_search` / `_filter` (filter-then-group order).
  String _search = '';
  ConversationFilter _filter = ConversationFilter.all;

  @override
  void initState() {
    super.initState();
    // Mark this channel as the active conversation so the unread lifecycle
    // clears its badge on the next focused poll (mirrors React's
    // `activeConversationKey = conversationKey(active)` on screen open).
    // Deferred via a microtask because Riverpod forbids modifying a
    // provider during a widget lifecycle method (initState/build/dispose)
    // -- the set lands after the current build, matching React's effect
    // running after render.
    Future.microtask(() {
      if (!mounted) return;
      ref
          .read(activeConversationKeyProvider.notifier)
          .set('channel:${widget.name}');
    });
  }

  @override
  void dispose() {
    _composer.dispose();
    super.dispose();
  }

  // Reset the mobile search panel when the channel changes -- 1-1 with React's
  // `useMobileSearchPanel` `resetKey` effect (ActiveChatHeader.tsx L107-109:
  // `useEffect(() => { setOpen(false); }, [resetKey])`). The channel name is
  // the reset key; if it changed (the same widget reused for a different
  // channel), the open search panel closes so the new channel does not inherit
  // a stale open mobile search.
  @override
  void didUpdateWidget(covariant ChannelScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.name != oldWidget.name) {
      _mobileSearchOpen = false;
    }
  }

  // Send a text body -- reads the composer (UI state), delegates the gateway
  // send + business-state mutation to [ChannelController.sendBody], then does
  // the React-parity composer clear on success (clear iff the composer still
  // equals the sent body so in-flight typing survives). The controller never
  // touches the composer; this closure owns that UI mutation.
  Future<void> _send() async {
    final body = _composer.text.trim();
    if (body.isEmpty) return;
    final controller =
        ref.read(channelControllerProvider(widget.name).notifier);
    final outcome = await controller.sendBody(body);
    if (!mounted) return;
    if (outcome.sent && _composer.text.trim() == outcome.body) {
      _composer.clear();
    }
  }

  // Retry the last failed send from the ChatError banner -- delegates to
  // [ChannelController.retryFailedSend] and does the same React-parity
  // composer clear on a successful retry (the composer still holds the failed
  // body, so a successful retry clears it -- 1-1 with React parity).
  Future<void> _retryFailedSend() async {
    final controller =
        ref.read(channelControllerProvider(widget.name).notifier);
    final outcome = await controller.retryFailedSend();
    if (!mounted) return;
    if (outcome.sent && _composer.text.trim() == outcome.body) {
      _composer.clear();
    }
  }

  // Open an attachment -- delegates the pending-open arming + download to
  // [ChannelController.openAttachment]; if the controller returns a `showSrc`
  // (already-downloaded or streamable media), the screen shows the in-app
  // [MediaViewer] (the UI side effect the controller never performs).
  void _openAttachment(AttachmentDescriptor descriptor, AttachmentView? view) {
    final controller =
        ref.read(channelControllerProvider(widget.name).notifier);
    final result = controller.openAttachment(descriptor, view);
    final src = result.showSrc;
    if (src != null) {
      showMediaViewer(
        context: context,
        descriptor: result.descriptor ?? descriptor,
        src: src,
      );
    }
  }

  // Start a 1:1 DM with a channel peer -- delegates the invite create +
  // channel-DM-offer send + offered-tracking + sessionList invalidation to
  // [ChannelController.onPeerMessage]; on a successful offer the controller
  // returns the new session id and the screen navigates to `/dm/<id>` (the
  // controller never navigates). A no-op (already-offered peer) returns
  // `sessionId == null` and the screen does nothing.
  Future<void> _onPeerMessage(String peerFingerprint) async {
    final controller =
        ref.read(channelControllerProvider(widget.name).notifier);
    final result = await controller.onPeerMessage(peerFingerprint);
    if (!mounted) return;
    final sessionId = result.sessionId;
    if (sessionId != null) {
      context.go(AppRoutes.dmFor(sessionId));
    }
  }

  // Surfaces mic-permission / start failures from the VoiceComposer
  // (mirrors React `onVoiceError` -> the screen error SnackBar). UI side
  // effect; stays in the screen.
  void _onVoiceError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  // Surfaces the localized 50 MB limit message when the picker rejects an
  // oversized file (mirrors React's `onError("Attachment exceeds the 50 MB
  // limit")`). A SnackBar is the Material idiom for a transient, non-modal
  // error that does not steal focus from the composer. UI side effect;
  // stays in the screen.
  void _onAttachmentPickError(AttachmentPickError error) {
    if (!mounted) return;
    final l = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l.attachmentTooLargeMessage)),
    );
  }

  // Leave the channel -- the confirm dialog is UI (stays in the screen); on
  // confirm the screen clears the active-conversation key (a global provider
  // the screen owns the lifecycle of) + delegates the gateway close +
  // invalidation + failed-send clear to [ChannelController.leave] + then
  // navigates back to the sessions list (the controller never navigates).
  Future<void> _leave() async {
    ref.read(activeConversationKeyProvider.notifier).clear();
    final controller =
        ref.read(channelControllerProvider(widget.name).notifier);
    await controller.leave();
    if (!mounted) return;
    context.go(AppRoutes.sessions);
  }

  // Close-flow confirmation -- 1-1 with React `useChatCloseFlow` channel
  // branch (use-chat-close-flow.ts L57-65): the leave IconButton opens a
  // ConfirmDialog with `Leave #${label}?` / body / `Leave channel` before
  // the real [_leave] runs. `showConfirmDialog` returns true on confirm,
  // false on cancel/barrier/Esc, so [_leave] only runs on an explicit
  // confirm (mirrors `closeFlow.confirmCloseActive` gating the real close).
  Future<void> _requestLeave() async {
    final l = AppLocalizations.of(context)!;
    final confirmed = await showConfirmDialog(
      context: context,
      title: l.leaveChannelTitle(widget.name),
      body: l.leaveChannelBody,
      confirmLabel: l.leaveChannelConfirm,
      cancelLabel: l.dialogCancel,
    );
    if (confirmed) await _leave();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final async = ref.watch(channelSnapshotProvider(widget.name));
    final controller =
        ref.watch(channelControllerProvider(widget.name).notifier);
    final state = ref.watch(channelControllerProvider(widget.name));
    // Resolve the pending-open descriptor 1-1 with React's `useEffect`
    // (use-chat-orchestration.ts L267-283): when the channel snapshot's
    // attachments update and a pending open is armed, ask the controller to
    // resolve it; on `show` the screen opens the [MediaViewer], on `drop`
    // the pending is cleared (the controller already cleared its state),
    // on `none` there is nothing to do. `ref.listen` is idempotent across
    // rebuilds (Riverpod dedupes the subscription).
    ref.listen<AsyncValue<ChannelSnapshot>>(
      channelSnapshotProvider(widget.name),
      (_, next) {
        final attachments = next.value?.attachments;
        if (attachments == null || attachments.isEmpty) return;
        final resolution = controller.resolvePendingOpen(attachments);
        switch (resolution) {
          case ChannelPendingShow(:final descriptor, :final src):
            showMediaViewer(context: context, descriptor: descriptor, src: src);
          case ChannelPendingDrop():
            break;
          case ChannelPendingNone():
            break;
        }
      },
    );
    final channelForDrawer = async.value;
    final errorForDrawer = async.hasError ? async.error.toString() : null;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.name),
        actions: [
          // Mobile search toggle -- 1-1 with React `MobileSearchToggle`
          // (ActiveChatHeader.tsx L113-131), gated on the mobile
          // breakpoint (React `chat-mobile-only` class). Placed first in
          // the actions so it sits left of the peer-status + leave buttons,
          // mirroring React's beforeSearchActions position.
          if (isMobileBreakpoint(context))
            MobileSearchToggle(
              open: _mobileSearchOpen,
              onToggle: () =>
                  setState(() => _mobileSearchOpen = !_mobileSearchOpen),
              l: l,
            ),
          IconButton(
            icon: const Icon(Icons.electrical_services, size: 18),
            tooltip: l.openPeerStatus,
            onPressed: () => setState(() => _showPeerStatus = true),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: l.channelLeaveLabel,
            onPressed: _requestLeave,
          ),
        ],
      ),
      body: ChannelScreenBody(
        async: async,
        chatError: state.chatError,
        canRetrySend: state.canRetrySend(controller.target),
        onRetry: _retryFailedSend,
        search: _search,
        filter: _filter,
        onSearch: (value) => setState(() => _search = value),
        onFilter: (value) => setState(() => _filter = value),
        mobileSearchOpen: _mobileSearchOpen,
        onCloseMobileSearch: () => setState(() => _mobileSearchOpen = false),
        attachmentCallbacks:
            controller.attachmentCallbacks(_openAttachment),
        onRetryMessage: controller.retryMessage,
        offeredFingerprints: state.offeredFingerprints,
        offerBusy: state.offerBusy,
        onPeerMessage: _onPeerMessage,
        composerController: _composer,
        sending: state.sending,
        onSend: _send,
        onSendAttachment: controller.sendAttachment,
        onAttachmentPickError: _onAttachmentPickError,
        onSendVoice: controller.sendVoice,
        onVoiceError: _onVoiceError,
        showPeerStatus: _showPeerStatus,
        onClosePeerStatus: () => setState(() => _showPeerStatus = false),
        channelForDrawer: channelForDrawer,
        errorForDrawer: errorForDrawer,
        onRefresh: () => ref.invalidate(channelSnapshotProvider(widget.name)),
      ),
    );
  }
}
