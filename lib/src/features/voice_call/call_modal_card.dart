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
  });

  final String label;
  final String peer;
  final String status;
  final VoidCallback onEscape;
  final List<Widget> actions;
  final List<FontFeature>? statusFontFeatures;

  @override
  Widget build(BuildContext context) => ModalFocusTrap(
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 36, vertical: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(peer,
                        style: const TextStyle(
                            fontSize: 18,
                            color: Colors.white,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 18),
                    Text(status,
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
