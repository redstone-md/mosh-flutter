import 'package:flutter/material.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_theme.dart' show MoshColors;

import 'start_motion.dart';
import 'start_reveal.dart';

/// The start menu's welcome: an eyebrow, the title, what Mosh protects and
/// how, and, when [illustrated], the hero illustration drifting after the
/// pointer.
class StartHero extends StatefulWidget {
  const StartHero({super.key, required this.illustrated});

  final bool illustrated;

  @override
  State<StartHero> createState() => _StartHeroState();
}

class _StartHeroState extends State<StartHero> {
  /// The pointer's place over the hero, each axis -1..1.
  Offset _drift = Offset.zero;

  void _track(PointerEvent event) {
    final size = context.size;
    if (size == null || size.isEmpty) return;
    setState(() => _drift = Offset(
          (event.localPosition.dx / size.width * 2 - 1).clamp(-1, 1),
          (event.localPosition.dy / size.height * 2 - 1).clamp(-1, 1),
        ));
  }

  @override
  Widget build(BuildContext context) {
    final copy = _HeroCopy(l: AppLocalizations.of(context)!);
    if (!widget.illustrated) return copy;
    final still = MediaQuery.disableAnimationsOf(context);
    return MouseRegion(
      onHover: still ? null : _track,
      onExit: (_) => setState(() => _drift = Offset.zero),
      child: Row(children: [
        Expanded(flex: 5, child: copy),
        const SizedBox(width: 24),
        Expanded(
          flex: 6,
          child: StartReveal(
            delay: StartMotion.lineStagger * 3,
            child: _Illustration(drift: still ? Offset.zero : _drift),
          ),
        ),
      ]),
    );
  }
}

class _HeroCopy extends StatelessWidget {
  const _HeroCopy({required this.l});

  final AppLocalizations l;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final compact = MediaQuery.sizeOf(context).width < 600;
    final lines = <Widget>[
      Text(
        l.startEyebrow.toUpperCase(),
        semanticsLabel: l.startEyebrow,
        style: text.labelMedium
            ?.copyWith(color: MoshColors.fg3, letterSpacing: 3.2, fontSize: 12),
      ),
      Semantics(
        header: true,
        child: Text.rich(
          TextSpan(children: [
            TextSpan(text: '${l.startTitleLead} '),
            TextSpan(
              text: l.startTitleAccent,
              style: const TextStyle(color: MoshColors.moss),
            ),
          ]),
          style: text.displaySmall?.copyWith(
              fontSize: compact ? 34 : 48,
              fontWeight: FontWeight.w700,
              height: 1.1,
              letterSpacing: -0.5),
        ),
      ),
      ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Text(
          l.startSubtitle,
          style: text.bodyLarge?.copyWith(color: MoshColors.fg2, height: 1.5),
        ),
      ),
      _Facts(l: l),
    ];
    const gaps = [14.0, 16.0, 24.0];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (i, line) in lines.indexed) ...[
          if (i > 0) SizedBox(height: gaps[i - 1]),
          StartReveal(delay: StartMotion.lineStagger * i, child: line),
        ],
      ],
    );
  }
}

/// What Mosh does for the conversations started here, as the runtime
/// does it: MLS for chats and groups, the Moss mesh, encrypted storage.
class _Facts extends StatelessWidget {
  const _Facts({required this.l});

  final AppLocalizations l;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context)
        .textTheme
        .bodySmall
        ?.copyWith(color: MoshColors.fg2, height: 1.35);
    final facts = [
      (Icons.lock_outline, l.startFactMls),
      (Icons.hub_outlined, l.startFactMesh),
      (Icons.shield_outlined, l.startFactHistory),
    ];
    // Side by side, two lines each, where there is room; one per line on
    // a phone.
    return LayoutBuilder(builder: (context, constraints) {
      const gap = 20.0;
      final row = constraints.maxWidth >= 420;
      final width = row ? (constraints.maxWidth - gap * 2) / 3 : null;
      return Wrap(
        spacing: gap,
        runSpacing: 12,
        children: [
          for (final (icon, label) in facts)
            SizedBox(
              width: width,
              child: Row(
                  mainAxisSize: row ? MainAxisSize.max : MainAxisSize.min,
                  children: [
                    Icon(icon, size: 22, color: MoshColors.moss),
                    const SizedBox(width: 10),
                    Flexible(child: Text(label, style: style)),
                  ]),
            ),
        ],
      );
    });
  }
}

class _Illustration extends StatelessWidget {
  const _Illustration({required this.drift});

  final Offset drift;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: TweenAnimationBuilder<Offset>(
        tween: Tween(end: drift * StartMotion.parallax),
        duration: drift == Offset.zero
            ? StartMotion.tiltReturn
            : StartMotion.tiltFollow,
        curve: StartMotion.ease,
        builder: (context, offset, child) =>
            Transform.translate(offset: offset, child: child),
        child: Image.asset(
          'assets/start/hero.png',
          fit: BoxFit.contain,
          filterQuality: FilterQuality.medium,
        ),
      ),
    );
  }
}
