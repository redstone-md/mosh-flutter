// S5-x: GroupScreen route shell -- the minimal, reachable surface for a
// private group. Mirrors ChannelScreen (S5-1) surface-by-surface: AppBar
// (group label + leave IconButton) + a scrolling message list (own vs
// others by FINGERPRINT, not display name -- groups are multi-party so
// names are not unique) + a composer. SHELL ONLY.
//
// 1-1 with the React group pane (ActiveChatPanes.tsx ActiveGroupChat):
// AppBar (group label + admin-pill + copy-invite + leave via
// [GroupScreenHeader]) + GroupNotice banner + ConversationTools +
// message list (own vs others by FINGERPRINT) + composer + peer-status
// drawer overlay. The admin badge / member-count subtitle / MLS-state
// subtitle render in [GroupScreenHeader] (group_screen_header.dart).
//
// Own-vs-others rule (React MessageLists.tsx GroupChatList, same as
// ChannelScreen): own = message.fromFingerprint == group.deviceFingerprint.
// Fingerprint comparison (NOT display name) is the key correctness point --
// groups are multi-party, so two members could share a display name but
// never a device fingerprint. Sender-meta grouping (5-min,
// same-fingerprint) + MultiPartySenderMeta render in group_message_row.dart.
//
// Key differences from ChannelScreen (groups vs channels):
//   - keyed by `groupId` (the identity), NOT `name`.
//   - title = `group.label ?? l.groupUntitled` (label is nullable; React
//     falls back to `groupText.untitled` = "Private group").
//   - leave via `gateway.closeGroup` (group teardown is frb `close` ->
//     Gateway `closeGroup`; channel used `leaveChannel`).
//   - send via `gateway.sendGroup` (NOT `sendChannel`); then
//     `ref.invalidate(groupSnapshotProvider(widget.groupId))`.
//
// AGENTS.md state separation: the BUSINESS orchestration state (sending /
// offerBusy / offeredFingerprints / chatError / pendingOpen / lastFailedSend
// + the send/retry/attachment/voice/leave/peer-DM/open-attachment/org-invite
// methods) lives in [GroupController] (group_controller.dart), a Riverpod
// Notifier keyed by the group id. This screen keeps ONLY the UI state
// (`_composer` / `_showPeerStatus` / `_mobileSearchOpen` / `_search` /
// `_filter`) + the lifecycle + navigation (the controller returns results --
// [GroupLeaveResult] / [GroupPeerDmResult] -- and the screen does
// `context.go`) + the composer-clear-on-success + the SnackBar error
// surfaces + the MediaViewer open + the leave-confirm dialog (which reads
// the group snapshot for the label -- a UI concern). The controller never
// navigates and never touches the composer.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/dm/conversation_tools.dart';
import 'package:mosh/src/features/group/group_screen_header.dart';
import 'package:mosh/src/features/shared/attachment_picker.dart';
import 'package:mosh/src/features/shared/confirm_dialog.dart';
import 'package:mosh/src/features/shared/media_viewer.dart'
    show showMediaViewer;
import 'package:mosh/src/routing/app_router.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart'
    show AttachmentView, AttachmentDescriptor;
import 'package:mosh/src/rust/private_group_runtime.dart';
import 'package:mosh/src/state/channel_group_providers.dart';
import 'package:mosh/src/state/org_providers.dart' show orgAddPromptProvider;
import 'package:mosh/src/state/active_conversation_key_provider.dart';
import 'package:mosh/src/util/format.dart' show shorten;

import 'package:mosh/src/features/group/group_controller.dart';
import 'package:mosh/src/features/group/group_screen_body.dart';

/// Group screen for one private group. Own vs others is inferred from
/// `GroupMessage.fromFingerprint` vs the group's `deviceFingerprint`
/// (React's `from_fingerprint === group.device_fingerprint` rule -- NOT
/// display name, since groups are multi-party). Keyed by `groupId` (the
/// group identity), not a display name. Business orchestration state +
/// methods are delegated to [GroupController]; this widget owns UI state +
/// navigation + the composer-clear-on-success + the leave-confirm dialog.
class GroupScreen extends ConsumerStatefulWidget {
  const GroupScreen({super.key, required this.groupId});

  final String groupId;

  @override
  ConsumerState<GroupScreen> createState() => _GroupScreenState();
}

class _GroupScreenState extends ConsumerState<GroupScreen> {
  final TextEditingController _composer = TextEditingController();
  bool _showPeerStatus = false;
  // Ephemeral search + filter (React ConversationTools); widget-local per
  // ADR 0010; drive [filterGroupMessages] before grouping, mirroring
  // DmScreen's `_search` / `_filter` (filter-then-group order).
  String _search = '';
  ConversationFilter _filter = ConversationFilter.all;
  // Mobile search panel open state -- 1-1 with React `useMobileSearchPanel`
  // (ActiveChatHeader.tsx L103-111): `useState(false)` reset on `resetKey`
  // change. For a group the reset key is the group id (`widget.groupId`),
  // the group's conversation identity; the header toggle (in
  // [GroupScreenHeader]) flips it and the body renders
  // `MobileConversationSearch` while true. Gated on the mobile breakpoint.
  bool _mobileSearchOpen = false;

  @override
  void initState() {
    super.initState();
    // Mark this group as the active conversation so the unread lifecycle
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
          .set('group:${widget.groupId}');
    });
  }

  @override
  void dispose() {
    _composer.dispose();
    super.dispose();
  }

  // Reset the mobile search panel when the group changes -- 1-1 with React's
  // `useMobileSearchPanel` `resetKey` effect (ActiveChatHeader.tsx L107-109:
  // `useEffect(() => { setOpen(false); }, [resetKey])`). The group id is the
  // reset key; if it changed (the same widget reused for a different group),
  // the open search panel closes so the new group does not inherit a stale
  // open mobile search.
  @override
  void didUpdateWidget(covariant GroupScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.groupId != oldWidget.groupId) {
      _mobileSearchOpen = false;
    }
  }

  // Send a text body -- reads the composer (UI state), delegates the gateway
  // send + business-state mutation to [GroupController.sendBody], then does
  // the React-parity composer clear on success (clear iff the composer still
  // equals the sent body so in-flight typing survives). The controller never
  // touches the composer; this closure owns that UI mutation.
  Future<void> _send() async {
    final body = _composer.text.trim();
    if (body.isEmpty) return;
    final controller =
        ref.read(groupControllerProvider(widget.groupId).notifier);
    final outcome = await controller.sendBody(body);
    if (!mounted) return;
    if (outcome.sent && _composer.text.trim() == outcome.body) {
      _composer.clear();
    }
  }

  // Retry the last failed send from the ChatError banner -- delegates to
  // [GroupController.retryFailedSend] and does the same React-parity
  // composer clear on a successful retry (the composer still holds the
  // failed body, so a successful retry clears it -- 1-1 with React parity).
  Future<void> _retryFailedSend() async {
    final controller =
        ref.read(groupControllerProvider(widget.groupId).notifier);
    final outcome = await controller.retryFailedSend();
    if (!mounted) return;
    if (outcome.sent && _composer.text.trim() == outcome.body) {
      _composer.clear();
    }
  }

  // Open an attachment -- delegates the pending-open arming + download to
  // [GroupController.openAttachment]; if the controller returns a `showSrc`
  // (already-downloaded or streamable media), the screen shows the in-app
  // [MediaViewer] (the UI side effect the controller never performs).
  void _openAttachment(AttachmentDescriptor descriptor, AttachmentView? view) {
    final controller =
        ref.read(groupControllerProvider(widget.groupId).notifier);
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

  // Start a 1:1 DM with a group peer -- delegates the invite create +
  // group-DM-offer send + offered-tracking + sessionList invalidation to
  // [GroupController.onPeerMessage]; on a successful offer the controller
  // returns the new session id and the screen navigates to `/dm/<id>` (the
  // controller never navigates). A no-op (already-offered peer) returns
  // `sessionId == null` and the screen does nothing.
  Future<void> _onPeerMessage(String peerFingerprint) async {
    final controller =
        ref.read(groupControllerProvider(widget.groupId).notifier);
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

  // Leave the group -- the confirm dialog is UI (stays in the screen); on
  // confirm the screen clears the active-conversation key (a global provider
  // the screen owns the lifecycle of) + delegates the gateway close +
  // invalidation + failed-send clear to [GroupController.leave] + then
  // navigates back to the sessions list (the controller never navigates).
  Future<void> _leave() async {
    ref.read(activeConversationKeyProvider.notifier).clear();
    final controller =
        ref.read(groupControllerProvider(widget.groupId).notifier);
    await controller.leave();
    if (!mounted) return;
    context.go(AppRoutes.sessions);
  }

  // Close-flow confirmation -- 1-1 with React `useChatCloseFlow` group
  // branch (use-chat-close-flow.ts L67-77): the leave action opens a
  // ConfirmDialog with `Leave ${label}?` / body / `Leave group` before the
  // real [_leave] runs. React's `label = group?.label ?? (group ?
  // shorten(group.group_id, 6) : "this group")`; the group screen always
  // has a resolved group (it is the active screen), so the fallback is
  // `group.label ?? shorten(group.groupId, 6)`. If the snapshot is still
  // pending when the user taps leave, fall back to `shorten(groupId, 6)`
  // (the widget arg), which mirrors the resolved-group fallback shape.
  Future<void> _requestLeave() async {
    final l = AppLocalizations.of(context)!;
    final group = ref.read(groupSnapshotProvider(widget.groupId)).value;
    final label = group?.label ?? shorten(group?.groupId ?? widget.groupId, 6);
    final confirmed = await showConfirmDialog(
      context: context,
      title: l.leaveGroupTitle(label),
      body: l.leaveGroupBody,
      confirmLabel: l.leaveGroupConfirm,
      cancelLabel: l.dialogCancel,
    );
    if (confirmed) await _leave();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(groupSnapshotProvider(widget.groupId));
    final controller =
        ref.watch(groupControllerProvider(widget.groupId).notifier);
    final state = ref.watch(groupControllerProvider(widget.groupId));
    // Resolve the pending-open descriptor 1-1 with React's `useEffect`
    // (use-chat-orchestration.ts L267-283): when the group snapshot's
    // attachments update and a pending open is armed, ask the controller to
    // resolve it; on `show` the screen opens the [MediaViewer], on `drop`
    // the pending is cleared (the controller already cleared its state),
    // on `none` there is nothing to do. `ref.listen` is idempotent across
    // rebuilds (Riverpod dedupes the subscription).
    ref.listen<AsyncValue<GroupSnapshot>>(
      groupSnapshotProvider(widget.groupId),
      (_, next) {
        final attachments = next.value?.attachments;
        if (attachments == null || attachments.isEmpty) return;
        final resolution = controller.resolvePendingOpen(attachments);
        switch (resolution) {
          case GroupPendingShow(:final descriptor, :final src):
            showMediaViewer(context: context, descriptor: descriptor, src: src);
          case GroupPendingDrop():
            break;
          case GroupPendingNone():
            break;
        }
      },
    );
    final groupForDrawer = async.value;
    final orgAddPrompt = ref.watch(orgAddPromptProvider(widget.groupId));
    final errorForDrawer = async.hasError ? async.error.toString() : null;
    return Scaffold(
      appBar: GroupScreenHeader(
        groupId: widget.groupId,
        onOpenPeerStatus: () => setState(() => _showPeerStatus = true),
        onLeave: _requestLeave,
        mobileSearchOpen: _mobileSearchOpen,
        onToggleMobileSearch: () =>
            setState(() => _mobileSearchOpen = !_mobileSearchOpen),
      ),
      body: GroupScreenBody(
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
        orgAddPrompt: orgAddPrompt,
        onInviteMembers: controller.inviteMembers,
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
        groupForDrawer: groupForDrawer,
        errorForDrawer: errorForDrawer,
        onRefresh: () => ref.invalidate(groupSnapshotProvider(widget.groupId)),
      ),
    );
  }
}
