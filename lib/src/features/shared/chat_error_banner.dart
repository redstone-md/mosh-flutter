import 'package:flutter/material.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_icons.dart';
import 'package:mosh/src/features/shared/mosh_notice.dart';

/// The Chat error kind of the Banner card: what went wrong in this
/// conversation, on the error plate. It ends with Retry where [onRetry]
/// can put it right, otherwise with the close button of [onClose]; with
/// neither it stays until it stops being true. The caller decides when it
/// appears.
class ChatErrorBanner extends StatelessWidget {
  const ChatErrorBanner({
    super.key,
    required this.message,
    this.onRetry,
    this.onClose,
  });

  final String message;
  final VoidCallback? onRetry;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) => MoshNotice(
        tone: MoshNoticeTone.error,
        icon: MoshIcons.error,
        title: message,
        actionLabel: onRetry == null
            ? null
            : AppLocalizations.of(context)!.chatErrorRetry,
        onAction: onRetry,
        onClose: onRetry == null ? onClose : null,
      );
}
