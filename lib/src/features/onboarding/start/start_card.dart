import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:mosh/src/app/mosh_theme.dart' show MoshColors;
import 'package:mosh/src/features/shared/focus_ring.dart';
import 'package:mosh/src/features/shared/press_scale.dart';

import 'start_motion.dart';

const _radius = BorderRadius.all(Radius.circular(16));

/// One way to start a conversation: icon, title, description and an arrow.
///
/// Hover and keyboard focus light it the same way: a moss border and wash,
/// and the arrow filling in. A mouse also leans the card toward the
/// pointer under a soft glare. Static under reduced motion.
class StartCard extends StatefulWidget {
  const StartCard({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
    this.compact = false,
  });

  /// One row: icon, text, arrow. For a single column on a phone.
  final bool compact;

  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;

  @override
  State<StartCard> createState() => _StartCardState();
}

class _StartCardState extends State<StartCard> {
  bool _hovered = false;
  bool _focused = false;

  /// The pointer's place on the card, each axis 0..1; null when away.
  Offset? _pointer;

  bool get _lit => _hovered || _focused;

  void _track(PointerEvent event) {
    final size = context.size;
    if (size == null || size.isEmpty) return;
    setState(() => _pointer = Offset(
          (event.localPosition.dx / size.width).clamp(0, 1),
          (event.localPosition.dy / size.height).clamp(0, 1),
        ));
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    // The flat wrapper tracks the pointer, so the leaning card never slips
    // out from under it.
    return MouseRegion(
      onHover: _track,
      onExit: (_) => setState(() => _pointer = null),
      child: _Tilt(
        pointer: still ? null : _pointer,
        child: PressScale(
          enabled: !still,
          targetScale: 0.98,
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: _radius,
              onTap: widget.onTap,
              onHover: (value) => setState(() => _hovered = value),
              onFocusChange: (value) => setState(() => _focused = value),
              splashColor: MoshColors.mossGlow,
              highlightColor: Colors.transparent,
              hoverColor: Colors.transparent,
              child: FocusRing(
                radius: _radius,
                child: _CardFace(
                  card: widget,
                  lit: _lit,
                  glare: still ? null : _pointer,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Leans [child] toward [pointer]: quick to follow, slow to settle.
class _Tilt extends StatelessWidget {
  const _Tilt({required this.pointer, required this.child});

  final Offset? pointer;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = pointer;
    final target = p == null ? Offset.zero : (p - const Offset(0.5, 0.5)) * 2;
    return TweenAnimationBuilder<Offset>(
      tween: Tween(end: target),
      duration: p == null ? StartMotion.tiltReturn : StartMotion.tiltFollow,
      curve: StartMotion.ease,
      child: child,
      builder: (context, lean, child) {
        const max = StartMotion.tiltMax * math.pi / 180;
        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.001)
            ..rotateX(-lean.dy * max)
            ..rotateY(lean.dx * max),
          child: child,
        );
      },
    );
  }
}

class _CardFace extends StatelessWidget {
  const _CardFace({required this.card, required this.lit, this.glare});

  final StartCard card;
  final bool lit;
  final Offset? glare;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return AnimatedContainer(
      duration: StartMotion.glareFade,
      curve: StartMotion.ease,
      decoration: BoxDecoration(
        borderRadius: _radius,
        border: Border.all(
          color:
              lit ? MoshColors.moss.withValues(alpha: 0.55) : MoshColors.line,
        ),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          stops: const [0, 0.7],
          colors: [
            lit ? const Color(0xFF1B2112) : MoshColors.bg1,
            MoshColors.bg1,
          ],
        ),
      ),
      child: Stack(children: [
        if (card.compact)
          _CompactBody(card: card, lit: lit)
        else
          Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _IconPlate(icon: card.icon),
                const SizedBox(height: 20),
                Text(card.title,
                    style: text.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Text(card.description,
                    style: text.bodyMedium
                        ?.copyWith(color: MoshColors.fg3, height: 1.45)),
                const SizedBox(height: 16),
                // Cards in a row share a height; arrows line up at the foot.
                const Spacer(),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: _Arrow(lit: lit),
                ),
              ],
            ),
          ),
        Positioned.fill(child: _Glare(at: glare)),
      ]),
    );
  }
}

class _CompactBody extends StatelessWidget {
  const _CompactBody({required this.card, required this.lit});

  final StartCard card;
  final bool lit;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(children: [
        _IconPlate(icon: card.icon, size: 44),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(card.title,
                  style:
                      text.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(card.description,
                  style: text.bodySmall
                      ?.copyWith(color: MoshColors.fg3, height: 1.4)),
            ],
          ),
        ),
        const SizedBox(width: 12),
        _Arrow(lit: lit, size: 32),
      ]),
    );
  }
}

class _IconPlate extends StatelessWidget {
  const _IconPlate({required this.icon, this.size = 52});

  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: MoshColors.mossGlow,
        borderRadius: BorderRadius.circular(size * 0.27),
        border: Border.all(color: MoshColors.moss.withValues(alpha: 0.18)),
      ),
      child: Icon(icon, size: size / 2, color: MoshColors.moss),
    );
  }
}

/// Fills with moss and nudges forward while the card is lit.
class _Arrow extends StatelessWidget {
  const _Arrow({required this.lit, this.size = 40});

  final bool lit;
  final double size;

  @override
  Widget build(BuildContext context) {
    // Under reduced motion the arrow fills without travelling.
    final still = MediaQuery.disableAnimationsOf(context);
    final duration = still ? Duration.zero : StartMotion.arrow;
    return AnimatedContainer(
      duration: duration,
      curve: StartMotion.ease,
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: lit ? MoshColors.moss : MoshColors.bg3,
      ),
      child: AnimatedSlide(
        duration: duration,
        curve: StartMotion.ease,
        offset: Offset(lit && !still ? StartMotion.arrowShift / 18 : 0, 0),
        child: Icon(
          Icons.arrow_forward,
          size: 18,
          color: lit ? MoshColors.mossInk : MoshColors.fg2,
          textDirection: Directionality.of(context),
        ),
      ),
    );
  }
}

/// A soft light under the pointer.
class _Glare extends StatelessWidget {
  const _Glare({required this.at});

  final Offset? at;

  @override
  Widget build(BuildContext context) {
    final p = at ?? const Offset(0.5, 0.5);
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: at == null ? 0 : StartMotion.glareOpacity,
        duration: StartMotion.glareFade,
        curve: StartMotion.ease,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: _radius,
            gradient: RadialGradient(
              center: Alignment(p.dx * 2 - 1, p.dy * 2 - 1),
              radius: 0.9,
              colors: const [MoshColors.moss300, Color(0x00D4EB7A)],
            ),
          ),
        ),
      ),
    );
  }
}
