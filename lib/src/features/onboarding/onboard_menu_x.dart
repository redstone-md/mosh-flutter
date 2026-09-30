// Private leaf widgets of [OnboardMenu] (onboard_menu.dart): the
// Start/Join section shells, the identity chip and the action tiles.
// Part of onboard_menu.dart.
//
// Radii are concentric (outer = inner + inset): the chip is 18 around a
// radius-8 field at a 10px inset; a tile is 20 around a radius-8 icon
// plate at a 12px inset, the same pairing as PersistenceWarningBanner.
part of 'onboard_menu.dart';

/// A Start/Join section: a labelSmall heading followed by the section's
/// tiles with fixed spacing between them.
/// A Start/Join section: an uppercase heading followed by the section's
/// tiles with fixed spacing between them.
class _TileSection extends StatelessWidget {
  const _TileSection({required this.label, required this.tiles});

  final String label;
  final List<Widget> tiles;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Flutter has no text-transform, so the string itself is
        // uppercased; the Semantics label keeps the natural-case name.
        Semantics(
          label: label,
          excludeSemantics: true,
          child: Text(
            label.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: MoshColors.fg3,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.13 * 10.5,
                ),
          ),
        ),
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
        borderRadius: BorderRadius.circular(18),
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
            child: Icon(Icons.person_outline, size: 20, color: MoshColors.moss),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              decoration: InputDecoration(
                labelText: label,
                hintText: hint,
                helperText: identityHint,
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

/// A menu action: icon plate, title and a description that wraps to as
/// many lines as the locale needs, then a chevron.
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

  static const _radius = BorderRadius.all(Radius.circular(20));

  @override
  Widget build(BuildContext context) {
    return PressScale(
      child: Material(
        color: MoshColors.bg2,
        borderRadius: _radius,
        child: InkWell(
          borderRadius: _radius,
          onTap: onTap,
          child: FocusRing(
            radius: _radius,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: MoshColors.mossGlow,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(icon, size: 20, color: MoshColors.moss),
                  ),
                  const SizedBox(width: 13),
                  Expanded(child: _TileLabels(title: title, desc: desc)),
                  const SizedBox(width: 8),
                  const Icon(Icons.chevron_right,
                      size: 18, color: MoshColors.fg3),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A tile's title over its description; both wrap, nothing clips.
class _TileLabels extends StatelessWidget {
  const _TileLabels({required this.title, required this.desc});
  final String title;
  final String desc;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: text.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
            height: 1.3,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          desc,
          style: text.labelMedium?.copyWith(
            fontWeight: FontWeight.w400,
            color: MoshColors.fg3,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}
