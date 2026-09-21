// Private leaf widgets of [OnboardMenu] (onboard_menu.dart): the
// Start/Join section shells, the identity chip, the action tiles and
// the Advanced-disclosure text field. Part of onboard_menu.dart.
part of 'onboard_menu.dart';

/// A Start/Join section: a labelSmall heading followed by the section's
/// tiles with fixed spacing between them.
class _TileSection extends StatelessWidget {
  const _TileSection({
    required this.label,
    required this.labelStyle,
    required this.tiles,
  });

  final String label;
  final TextStyle? labelStyle;
  final List<Widget> tiles;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: labelStyle),
        const SizedBox(height: 8),
        for (final (i, tile) in tiles.indexed) ...[
          if (i > 0) const SizedBox(height: 8),
          tile,
        ],
      ],
    );
  }
}

class _IdentityChip extends StatelessWidget {
  const _IdentityChip({
    required this.controller,
    required this.label,
    required this.hint,
    required this.identityHint,
    required this.onChanged,
  });
  final TextEditingController controller;
  final String label;
  final String hint;
  final String identityHint;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MoshColors.line),
        color: MoshColors.bg2,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // The identity glyph uses a translucent moss tile like every
          // other icon surface, not a solid moss disc.
          const CircleAvatar(
            radius: 18,
            backgroundColor: MoshColors.mossGlow,
            child: Icon(Icons.person, size: 20, color: MoshColors.moss),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              decoration: InputDecoration(
                labelText: label,
                hintText: hint,
                helperText: identityHint,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

class _OnboardTile extends StatelessWidget {
  const _OnboardTile({
    required this.icon,
    required this.title,
    required this.desc,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String desc;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: MoshColors.bg2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: MoshColors.line),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 13,
        ),
        horizontalTitleGap: 13,
        leading: Container(
          width: 38,
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: MoshColors.mossGlow,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 20, color: MoshColors.moss),
        ),
        title: Text(title,
            style: const TextStyle(fontSize: 13.5, color: MoshColors.fg1)),
        subtitle: Text(
          desc,
          style: const TextStyle(fontSize: 11.5, color: MoshColors.fg3),
          maxLines: 2,
        ),
        trailing:
            const Icon(Icons.chevron_right, size: 18, color: MoshColors.fg4),
        onTap: onTap,
      ),
    );
  }
}

/// A dense Field-wrapped TextField as used by the Advanced disclosure
/// (static peer, listen port). One shape for both so the padding, border
/// and text style stay in sync.
class _AdvancedTextField extends StatelessWidget {
  const _AdvancedTextField({
    required this.label,
    required this.hint,
    required this.controller,
    required this.onChanged,
    this.fieldHint,
    this.keyboardType,
  });

  final String label;
  final String hint;

  /// The TextField's inner placeholder (may differ from [hint], the
  /// Field's caption).
  final String? fieldHint;
  final TextEditingController controller;
  final TextInputType? keyboardType;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Field(
      label: label,
      hint: hint,
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          hintText: fieldHint,
          border: const OutlineInputBorder(),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 11,
            vertical: 9,
          ),
        ),
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontSize: 12.5,
            ),
        onChanged: onChanged,
      ),
    );
  }
}
