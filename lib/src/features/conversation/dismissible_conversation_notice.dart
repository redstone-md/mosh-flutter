import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mosh/src/features/shared/toasts/toaster.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/shared/mosh_notice.dart';

import 'conversation_banners.dart' show FeedBanner;
import 'conversation_notice_preferences.dart';

/// Hides the informational notice throughout this installation after saving.
class DismissibleConversationNotice extends ConsumerStatefulWidget {
  const DismissibleConversationNotice({
    super.key,
    required this.kind,
    required this.icon,
    required this.title,
    required this.body,
    required this.tone,
  });

  final ConversationNoticeKind kind;
  final IconData icon;
  final String title;
  final String body;
  final MoshNoticeTone tone;

  @override
  ConsumerState<DismissibleConversationNotice> createState() =>
      _DismissibleConversationNoticeState();
}

class _DismissibleConversationNoticeState
    extends ConsumerState<DismissibleConversationNotice> {
  bool _saving = false;

  Future<void> _dismiss() async {
    if (_saving) return;
    setState(() => _saving = true);
    final toaster = context.toaster;
    final failed = AppLocalizations.of(context)!.noticeDismissFailed;
    try {
      await ref
          .read(dismissedConversationNoticesProvider.notifier)
          .dismiss(widget.kind);
    } catch (_) {
      toaster.show(failed, kind: ToastKind.error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dismissed = ref.watch(dismissedConversationNoticesProvider
        .select((kinds) => kinds.contains(widget.kind)));
    if (dismissed) return const SizedBox.shrink();
    return FeedBanner(MoshNotice(
      tone: widget.tone,
      icon: widget.icon,
      title: widget.title,
      detail: widget.body,
      onClose: _dismiss,
      busy: _saving,
    ));
  }
}
