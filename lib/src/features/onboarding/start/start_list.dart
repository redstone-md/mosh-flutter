import 'package:flutter/material.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_icons.dart';
import 'package:mosh/src/app/mosh_theme.dart' show MoshColors;
import 'package:mosh/src/features/shared/focus_ring.dart';

import 'start_motion.dart';

/// One way to start a conversation.
class StartAction {
  const StartAction({
    required this.icon,
    required this.accent,
    required this.title,
    required this.description,
    required this.onTap,
    this.encrypted = true,
  });

  final IconData icon;

  /// The conversation type's accent, as the rail shows it.
  final Color accent;
  final String title;
  final String description;
  final VoidCallback onTap;

  /// Whether what it opens is end-to-end encrypted. Every invite link
  /// opens a DM, group or organization, all admitted through MLS; only a
  /// public channel is open.
  final bool encrypted;
}

/// The actions as rows, grouped by whether what they open is encrypted.
class StartActionList extends StatelessWidget {
  const StartActionList({super.key, required this.actions});

  final List<StartAction> actions;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Section(
          icon: MoshIcons.lock,
          label: l.startGroupEncrypted,
          actions: [...actions.where((a) => a.encrypted)],
        ),
        const SizedBox(height: 20),
        _Section(
          icon: MoshIcons.language,
          label: l.startGroupOpen,
          actions: [...actions.where((a) => !a.encrypted)],
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(
      {required this.icon, required this.label, required this.actions});

  final IconData icon;
  final String label;
  final List<StartAction> actions;

  static const _radius = BorderRadius.all(Radius.circular(12));

  @override
  Widget build(BuildContext context) {
    final colors = MoshColors.of(context);
    final style = Theme.of(context)
        .textTheme
        .bodySmall
        ?.copyWith(color: colors.onSurfaceMuted, fontSize: 13);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 4, bottom: 8),
          child: Row(children: [
            Icon(icon, size: 14, color: colors.onSurfaceMuted),
            const SizedBox(width: 6),
            Flexible(
              child: Semantics(header: true, child: Text(label, style: style)),
            ),
          ]),
        ),
        DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            borderRadius: _radius,
            border: Border.all(color: colors.outlineVariant),
          ),
          child: ClipRRect(
            borderRadius: _radius,
            child: ColoredBox(
              color: colors.surface,
              child: Column(children: [
                for (final (i, action) in actions.indexed) ...[
                  // Inset to the text, as in a settings list.
                  if (i > 0)
                    Divider(
                        height: 1, indent: 52, color: colors.outlineVariant),
                  StartRow(action: action),
                ],
              ]),
            ),
          ),
        ),
      ],
    );
  }
}

/// A row: accent icon, title, description and a chevron. Hover and
/// keyboard focus raise it a step and brighten the chevron.
class StartRow extends StatefulWidget {
  const StartRow({super.key, required this.action});

  final StartAction action;

  @override
  State<StartRow> createState() => _StartRowState();
}

class _StartRowState extends State<StartRow> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final colors = MoshColors.of(context);
    final lit = _hovered || _focused;
    final action = widget.action;
    final text = Theme.of(context).textTheme;
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : StartMotion.hover;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: action.onTap,
        onHover: (value) => setState(() => _hovered = value),
        onFocusChange: (value) => setState(() => _focused = value),
        hoverColor: Colors.transparent,
        highlightColor: colors.surfaceContainerHighest,
        splashFactory: NoSplash.splashFactory,
        child: FocusRing(
          radius: BorderRadius.zero,
          child: AnimatedContainer(
            duration: duration,
            curve: StartMotion.ease,
            color: lit ? colors.surfaceContainerHigh : colors.surface,
            padding: const EdgeInsetsDirectional.fromSTEB(16, 14, 14, 14),
            child: Row(children: [
              Icon(action.icon, size: 20, color: action.accent),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(action.title,
                        style: text.titleSmall?.copyWith(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: colors.onSurface)),
                    const SizedBox(height: 2),
                    Text(action.description,
                        style: text.bodySmall?.copyWith(
                            fontSize: 13,
                            height: 1.4,
                            color: colors.onSurfaceMuted)),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              AnimatedSlide(
                duration: duration,
                curve: StartMotion.ease,
                offset: Offset(lit && duration > Duration.zero ? 0.15 : 0, 0),
                child: Icon(
                  MoshIcons.chevronRight,
                  size: 20,
                  color: lit ? colors.onSurfaceVariant : colors.outline,
                  textDirection: Directionality.of(context),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
