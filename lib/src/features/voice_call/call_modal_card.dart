import 'package:flutter/material.dart';
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
  });

  final String label;
  final String peer;
  final String status;
  final VoidCallback onEscape;
  final List<Widget> actions;
  final List<FontFeature>? statusFontFeatures;
  final bool compact;
  final VoidCallback? onOpenConversation;

  @override
  Widget build(BuildContext context) {
    return compact ? _compact(context) : _standalone();
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

  Widget _standalone() {
    return ModalFocusTrap(
      onEscape: onEscape,
      autofocus: true,
      child: Semantics(
        label: label,
        container: true,
        child: Dialog(
          insetPadding: const EdgeInsets.all(24),
          backgroundColor: const Color(0xFF1D1F24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 280),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _peer(),
                  const SizedBox(height: 18),
                  Text(status,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 14,
                          color: const Color(0xBFFFFFFF),
                          fontFeatures: statusFontFeatures)),
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

  Widget _peer() => InkWell(
        onTap: onOpenConversation,
        child: Text(peer,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                fontSize: 18,
                color: Colors.white,
                fontWeight: FontWeight.w700)),
      );
}
