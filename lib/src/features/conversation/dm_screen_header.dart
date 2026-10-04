import 'package:flutter/material.dart';
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
    show DmSessionState;

class DmScreenHeader extends ConsumerWidget implements PreferredSizeWidget {
  const DmScreenHeader({
    super.key,
    required this.chrome,
    required this.sessionId,
    required this.onStartCall,
  });

  final String sessionId;
  final VoidCallback onStartCall;

  final ConversationChrome chrome;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final async = ref.watch(activeSessionProvider(sessionId));
    final s = async.value;
    // What the runtime has proven about the contact, in one sentence.
    final status = s == null ? '' : dmStateSentence(l, s.state, s.transport);
    final fingerprint = s?.fingerprint ?? '';
    return ConversationAppBar(
      chrome: chrome,
      peerOnline: s?.state == DmSessionState.connected,
      avatarName: s == null ? sessionId : peerLabel(l, s),
      title: ConversationHeaderTitle(
        name: s == null ? sessionId : peerLabel(l, s),
        subtitle: status,
        onOpenDetails: chrome.onOpenPeerStatus,
        nameAction: FingerprintLock(
            fingerprint: fingerprint,
            hint: l.inviteFingerprintHint,
            besideName: true),
      ),
      leaveMenuLabel: l.deleteChatConfirm,
      leaveMenuIcon: Icons.delete_outline,
      inlineActions: [
        // Primary action precedes search and the menu in every header.
        IconButton(
          icon: const Icon(Icons.phone_outlined, size: 20),
          tooltip: l.callStart,
          onPressed: onStartCall,
        ),
      ],
    );
  }
}
