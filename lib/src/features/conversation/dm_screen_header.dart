import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mosh/src/features/shared/conversation_action_error.dart';
import 'package:mosh/src/features/shared/toasts/toaster.dart';
import 'package:mosh/src/state/pending_invites_provider.dart';
import 'package:mosh/src/gateway/conversation_target.dart';
import 'package:mosh/src/state/chat_names_provider.dart';
import 'package:mosh/src/features/conversation/rename_chat_dialog.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/state/session_providers.dart';
import 'package:mosh/src/features/conversation/conversation_chrome.dart';
import 'package:mosh/src/features/fingerprint/fingerprint_lock.dart';
import 'package:mosh/src/features/conversation/conversation_app_bar.dart';
import 'package:mosh/src/features/conversation/conversation_header_title.dart';
import 'package:mosh/src/features/conversation/dm_state.dart';
import 'package:mosh/src/features/conversation/peer_label.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart'
    show DmSessionState, SessionSnapshot;

class DmScreenHeader extends ConsumerStatefulWidget
    implements PreferredSizeWidget {
  const DmScreenHeader({
    super.key,
    required this.chrome,
    required this.sessionId,
    required this.onStartCall,
    this.onStartVideoCall,
  });

  final String sessionId;
  final VoidCallback onStartCall;
  final VoidCallback? onStartVideoCall;

  final ConversationChrome chrome;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  ConsumerState<DmScreenHeader> createState() => _DmScreenHeaderState();
}

class _DmScreenHeaderState extends ConsumerState<DmScreenHeader> {
  bool _busy = false;

  @override
  void didUpdateWidget(covariant DmScreenHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sessionId != widget.sessionId) _busy = false;
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    final sessionId = widget.sessionId;
    final report = actionErrorReporter(context);
    setState(() => _busy = true);
    try {
      await action();
    } catch (error) {
      report(error);
    } finally {
      if (mounted && widget.sessionId == sessionId) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _copy(String uri) {
    final toaster = context.toaster;
    final copied = AppLocalizations.of(context)!.onboardCopied;
    return _run(() async {
      await Clipboard.setData(ClipboardData(text: uri));
      toaster.show(copied, kind: ToastKind.success);
    });
  }

  Future<void> _replace() {
    final sessionId = widget.sessionId;
    final invitations = ref.read(pendingInvitesProvider.notifier);
    return _run(() async {
      await invitations.replace(sessionId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final async = ref.watch(activeSessionProvider(widget.sessionId));
    final s = async.value;
    // What the runtime has proven about the contact, in one sentence.
    final status = s == null ? '' : dmStateSentence(l, s.state, s.transport);
    final fingerprint = s?.fingerprint ?? '';
    final target = DmTarget(widget.sessionId);
    final original = s == null ? widget.sessionId : peerLabel(l, s);
    final personal = ref.watch(personalChatNameProvider(target.ref));
    final name = chatDisplayName(original, personal);
    return ConversationAppBar(
      chrome: widget.chrome,
      peerOnline: s?.state == DmSessionState.connected,
      avatarName: name,
      title: ConversationHeaderTitle(
        name: name,
        subtitle: status,
        onOpenDetails: widget.chrome.onOpenPeerStatus,
        nameAction: FingerprintLock(
            fingerprint: fingerprint,
            hint: l.inviteFingerprintHint,
            besideName: true),
      ),
      leaveMenuLabel: l.deleteChatConfirm,
      leaveMenuIcon: Icons.delete_outline,
      menuActions: [
        ..._invitationActions(s, l),
        _renameAction(l, target, name, original, personal),
      ],
      inlineActions: [
        if (widget.onStartVideoCall != null)
          IconButton(
              icon: const Icon(Icons.videocam_outlined, size: 20),
              tooltip: l.callStartVideo,
              onPressed: widget.onStartVideoCall),
        // Primary action precedes search and the menu in every header.
        IconButton(
          icon: const Icon(Icons.phone_outlined, size: 20),
          tooltip: l.callStart,
          onPressed: widget.onStartCall,
        ),
      ],
    );
  }

  List<ChatHeaderMenuAction> _invitationActions(
      SessionSnapshot? session, AppLocalizations l) {
    if (session
        case SessionSnapshot(inviteAvailable: true, inviteUri: final uri?)) {
      return [
        ChatHeaderMenuAction(
            label: l.onboardCopyLink,
            icon: Icons.copy_outlined,
            disabled: _busy,
            onSelect: () => _copy(uri)),
        ChatHeaderMenuAction(
            label: l.onboardChatRecreate,
            icon: Icons.refresh,
            disabled: _busy,
            onSelect: _replace),
      ];
    }
    return const [];
  }

  ChatHeaderMenuAction _renameAction(AppLocalizations l, DmTarget target,
          String name, String original, String? personal) =>
      ChatHeaderMenuAction(
          label: l.chatRename,
          icon: Icons.edit_outlined,
          disabled: !ref.watch(personalChatRenameAvailableProvider),
          onSelect: () => showRenameChatDialog(context, target,
              name: name,
              originalName: original,
              hasPersonalName: personal != null));
}
