import 'package:flutter/material.dart';
import 'package:mosh/src/app/mosh_theme.dart';
import 'package:mosh/src/features/shared/modal_focus_trap.dart';

/// Shared presentation and keyboard behavior for all call phases.
class CallModalCard extends StatelessWidget {
  const CallModalCard({
    super.key,
    required this.label,
    required this.peer,
    required this.status,
    required this.onEscape,
    required this.actions,
    this.statusFontFeatures,
    this.compact = false,
    this.onOpenConversation,
    this.notice,
  });

  final String label;
  final String peer;
  final String status;
  final VoidCallback onEscape;
  final List<Widget> actions;
  final List<FontFeature>? statusFontFeatures;
  final bool compact;
  final VoidCallback? onOpenConversation;
  final String? notice;

  @override
  Widget build(BuildContext context) {
    return compact ? _compact(context) : _standalone(context);
  }

  Widget _compact(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainer,
      child: Semantics(
        label: label,
        container: true,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(spacing: 12, children: [
            Expanded(
              child: InkWell(
                onTap: onOpenConversation,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(peer, maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text(status,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontFeatures: statusFontFeatures)),
                    if (notice != null) _notice(),
                  ],
                ),
              ),
            ),
            ...actions,
          ]),
        ),
      ),
    );
  }

  Widget _standalone(BuildContext context) {
    return ModalFocusTrap(
      onEscape: onEscape,
      autofocus: true,
      child: Semantics(
        label: label,
        container: true,
        child: Dialog(
          insetPadding: const EdgeInsets.all(24),
          backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 280),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _peer(context),
                  const SizedBox(height: 18),
                  Text(status,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 14,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontFeatures: statusFontFeatures)),
                  if (notice != null)
                    Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: _notice()),
                  const SizedBox(height: 18),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    spacing: 16,
                    children: actions,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _notice() => Text(notice!,
      style: const TextStyle(color: MoshColors.warn), softWrap: true);

  Widget _peer(BuildContext context) => InkWell(
        onTap: onOpenConversation,
        child: Text(peer,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: 18,
                color: Theme.of(context).colorScheme.onSurface,
                fontWeight: FontWeight.w700)),
      );
}
