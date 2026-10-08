import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/onboarding/invite_result.dart';
import 'package:mosh/src/features/shared/toasts/toaster.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';

/// Per-invitation clipboard feedback follows the URI, not its position in a list.
class PendingInvitationCard extends StatefulWidget {
  const PendingInvitationCard({
    super.key,
    required this.invite,
    required this.busy,
    required this.onReplace,
    required this.onOpen,
    required this.onError,
  });

  final InviteCreated invite;
  final bool busy;
  final VoidCallback onReplace;
  final VoidCallback onOpen;
  final ValueChanged<Object> onError;

  @override
  State<PendingInvitationCard> createState() => _PendingInvitationCardState();
}

class _PendingInvitationCardState extends State<PendingInvitationCard> {
  bool _copied = false;
  bool _copying = false;

  @override
  void didUpdateWidget(covariant PendingInvitationCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.invite.inviteUri != widget.invite.inviteUri) _copied = false;
  }

  Future<void> _copy() async {
    if (_copying || widget.busy) return;
    final uri = widget.invite.inviteUri;
    final toaster = context.toaster;
    final copied = AppLocalizations.of(context)!.messageCopied;
    setState(() => _copying = true);
    try {
      await Clipboard.setData(ClipboardData(text: uri));
      if (mounted && widget.invite.inviteUri == uri) {
        setState(() => _copied = true);
        toaster.show(copied, kind: ToastKind.success);
      }
    } catch (error) {
      if (mounted) widget.onError(error);
    } finally {
      if (mounted) setState(() => _copying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return InviteResult(
      note: '',
      uri: widget.invite.inviteUri,
      copied: _copied,
      busy: widget.busy || _copying,
      onCopy: _copy,
      onReplace: widget.onReplace,
      openLabel: l.onboardOpenChat,
      onOpen: widget.onOpen,
    );
  }
}
