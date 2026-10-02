import 'package:flutter/material.dart';
import 'package:mosh/src/app/mosh_shapes.dart';
import 'package:mosh/src/app/mosh_theme.dart';

/// A setting and its explanation share a surface; controls keep theme geometry.
class SettingsCard extends StatelessWidget {
  const SettingsCard({
    super.key,
    required this.icon,
    required this.title,
    required this.hint,
    required this.child,
  });

  final IconData icon;
  final String title;
  final String hint;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: MoshColors.bg1,
        border: Border.all(color: MoshColors.line),
        borderRadius: MoshShapes.composer,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(
              color: MoshColors.mossGlow,
              borderRadius: MoshShapes.conversationRow,
            ),
            child: Icon(icon, color: MoshColors.moss, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(child: _content(context)),
        ],
      ),
    );
  }

  Widget _content(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
              header: true,
              child:
                  Text(title, style: Theme.of(context).textTheme.titleMedium)),
          const SizedBox(height: 12),
          child,
          const SizedBox(height: 12),
          Text(hint, style: Theme.of(context).textTheme.bodySmall),
        ],
      );
}
