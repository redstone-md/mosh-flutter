part of 'mosh_theme.dart';

// The control themes of the Components page in Figma: one function per card
// of `scripts/figma-design/cards/`. Colours, radii, spacing and state layers
// come from Foundations; [platform] picks the desktop or the phone size.

/// The plate that stands in for a disabled control's fill.
Color _disabledPlate(MoshColors c) =>
    MoshState.tint(c.onSurface, MoshState.disabledContainer);

/// A control's content while it is disabled.
Color _disabledInk(MoshColors c) =>
    MoshState.tint(c.onSurface, MoshState.disabledContent);

/// The keyboard focus ring: 2px outside the control, in place of its edge.
WidgetStateProperty<BorderSide?> _edge(MoshColors c,
        {BorderSide? rest, BorderSide? disabled}) =>
    WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.focused)) {
        return BorderSide(
            color: c.focusRing,
            width: MoshBorder.thick,
            strokeAlign: BorderSide.strokeAlignOutside);
      }
      return states.contains(WidgetState.disabled) ? disabled ?? rest : rest;
    });

/// What the three kinds of the Button card share: a pill 40 px tall on the
/// desktop and 48 px on the phone, its label in [ink].
ButtonStyle _buttonStyle(MoshColors c, TextTheme text, TargetPlatform platform,
        {required Color ink, double inset = MoshSpace.s6}) =>
    ButtonStyle(
      visualDensity: VisualDensity.standard,
      minimumSize: WidgetStatePropertyAll(Size(
          MoshControl.touch(platform) ? MoshSpace.s12 : 0,
          MoshControl.height(platform))),
      padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: inset)),
      shape: const WidgetStatePropertyAll(MoshShapes.pill),
      textStyle: WidgetStatePropertyAll(text.labelLarge),
      iconSize: const WidgetStatePropertyAll(MoshSpace.s5),
      foregroundColor: MoshState.unlessDisabled(ink, _disabledInk(c)),
      iconColor: MoshState.unlessDisabled(ink, _disabledInk(c)),
      overlayColor: MoshState.layer(ink),
      elevation: const WidgetStatePropertyAll(0),
      side: _edge(c),
    );

FilledButtonThemeData _filledButtonTheme(
        MoshColors c, TextTheme text, TargetPlatform platform) =>
    FilledButtonThemeData(
      style: _buttonStyle(c, text, platform, ink: c.onPrimary).copyWith(
        backgroundColor: MoshState.unlessDisabled(c.primary, _disabledPlate(c)),
      ),
    );

OutlinedButtonThemeData _outlinedButtonTheme(
        MoshColors c, TextTheme text, TargetPlatform platform) =>
    OutlinedButtonThemeData(
      style: _buttonStyle(c, text, platform, ink: c.primary).copyWith(
        side: _edge(c,
            rest: BorderSide(color: c.outline),
            disabled: BorderSide(color: c.outlineVariant)),
      ),
    );

TextButtonThemeData _textButtonTheme(
        MoshColors c, TextTheme text, TargetPlatform platform) =>
    TextButtonThemeData(
      style:
          _buttonStyle(c, text, platform, ink: c.primary, inset: MoshSpace.s4),
    );

/// The Standard kind of the Icon button card; [moshTonalIconButtonStyle] is
/// the Tonal one.
IconButtonThemeData _iconButtonTheme(MoshColors c, TargetPlatform platform) {
  final touch = MoshControl.touch(platform);
  return IconButtonThemeData(
    style: ButtonStyle(
      visualDensity: VisualDensity.standard,
      fixedSize:
          WidgetStatePropertyAll(Size.square(MoshControl.height(platform))),
      padding: const WidgetStatePropertyAll(EdgeInsets.zero),
      iconSize: WidgetStatePropertyAll(touch ? MoshSpace.s6 : MoshSpace.s5),
      shape: const WidgetStatePropertyAll(MoshShapes.pill),
      foregroundColor:
          MoshState.unlessDisabled(c.onSurfaceVariant, _disabledInk(c)),
      overlayColor: MoshState.layer(c.onSurface),
      side: _edge(c),
    ),
  );
}

/// The Tonal kind of the Icon button card: an action with a plate of its
/// own, for the top of media and file cards.
ButtonStyle moshTonalIconButtonStyle(MoshColors c) => ButtonStyle(
      foregroundColor: MoshState.unlessDisabled(c.onSurface, _disabledInk(c)),
      backgroundColor: MoshState.unlessDisabled(
          c.surfaceContainerHighest, _disabledPlate(c)),
    );

/// The well of the Text field and Select cards. A text field's label stands
/// above it in a [MoshField].
InputDecorationTheme _inputDecorationTheme(
    MoshColors c, TextTheme text, TargetPlatform platform) {
  final height = MoshControl.height(platform);
  final line = text.bodyMedium!.fontSize! * text.bodyMedium!.height!;
  final affix = BoxConstraints(minWidth: MoshSpace.s10, minHeight: height);
  return InputDecorationTheme(
    filled: true,
    fillColor: WidgetStateColor.resolveWith((states) =>
        states.contains(WidgetState.disabled)
            ? Colors.transparent
            : c.surfaceContainerLowest),
    hoverColor: MoshState.tint(c.onSurface, MoshState.hover),
    // The app theme is compact; a well keeps the height of its card.
    visualDensity: VisualDensity.standard,
    isDense: true,
    contentPadding: EdgeInsets.symmetric(
        horizontal: MoshSpace.s4, vertical: (height - line) / 2),
    prefixIconConstraints: affix,
    suffixIconConstraints: affix,
    prefixIconColor: c.onSurfaceVariant,
    suffixIconColor: c.onSurfaceVariant,
    hintStyle: text.bodyMedium!.copyWith(color: c.onSurfaceMuted),
    helperStyle: text.bodySmall,
    errorStyle: text.bodySmall!.copyWith(color: c.error),
    border: _fieldBorder(c.outline),
    enabledBorder: _fieldBorder(c.outline),
    disabledBorder: _fieldBorder(c.outlineVariant),
    focusedBorder: _fieldBorder(c.primary, width: MoshBorder.thick),
    errorBorder: _fieldBorder(c.error),
    focusedErrorBorder: _fieldBorder(c.error, width: MoshBorder.thick),
  );
}

/// The well of the Select card as a button; it keeps the thick saffron edge
/// while its choices are [open] and a red one when they [failed] to load.
ButtonStyle moshSelectWellStyle(ThemeData theme,
    {required bool open, bool failed = false}) {
  final c = MoshColors.from(theme);
  return ButtonStyle(
    visualDensity: VisualDensity.standard,
    textStyle: WidgetStatePropertyAll(theme.textTheme.bodyMedium),
    minimumSize:
        WidgetStatePropertyAll(Size(0, MoshControl.height(theme.platform))),
    padding: const WidgetStatePropertyAll(
        EdgeInsetsDirectional.only(start: MoshSpace.s4, end: MoshSpace.s3)),
    shape: const WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: MoshShapes.field)),
    backgroundColor:
        MoshState.unlessDisabled(c.surfaceContainerLowest, Colors.transparent),
    foregroundColor: MoshState.unlessDisabled(c.onSurface, _disabledInk(c)),
    iconColor: MoshState.unlessDisabled(c.onSurfaceVariant, _disabledInk(c)),
    overlayColor: MoshState.layer(c.onSurface),
    side: open
        ? WidgetStatePropertyAll(
            BorderSide(color: c.primary, width: MoshBorder.thick))
        : _edge(c,
            rest: BorderSide(color: failed ? c.error : c.outline),
            disabled: BorderSide(color: c.outlineVariant)),
  );
}

/// The edge of a well; the focused one is thick.
OutlineInputBorder _fieldBorder(Color color,
        {double width = MoshBorder.thin}) =>
    OutlineInputBorder(
      borderRadius: MoshShapes.field,
      borderSide: BorderSide(color: color, width: width),
    );

/// The Suggestion chip of the Chip and segment card, for a [ChipTheme]
/// around such chips: a plate of its own and no edge.
ChipThemeData moshSuggestionChipTheme(ThemeData theme, MoshColors c) =>
    theme.chipTheme.copyWith(
      side: _chipEdge(c, (_) => BorderSide.none),
      color: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.disabled)
              ? _disabledPlate(c)
              : _hovered(states, c.surfaceContainerHigh, c.onSurface)),
      labelStyle: theme.textTheme.labelLarge!.copyWith(
          color: WidgetStateColor.resolveWith((states) =>
              states.contains(WidgetState.disabled)
                  ? _disabledInk(c)
                  : c.onSurface)),
    );

/// A chip's edge by state, with the focus ring in its place under the keyboard.
WidgetStateBorderSide _chipEdge(
        MoshColors c, BorderSide Function(Set<WidgetState> states) rest) =>
    WidgetStateBorderSide.resolveWith(
        (states) => _edge(c, rest: rest(states)).resolve(states));

/// A chip's [fill] under the hover layer of its [ink]. A chip with a fill
/// of its own draws no hover layer; focus and press come from the theme.
Color _hovered(Set<WidgetState> states, Color fill, Color ink) =>
    states.contains(WidgetState.hovered)
        ? Color.alphaBlend(MoshState.tint(ink, MoshState.hover), fill)
        : fill;

/// The Filter chip of the Chip and segment card: lit while it applies.
ChipThemeData _chipTheme(MoshColors c, TextTheme text) {
  Color ink(Set<WidgetState> states) {
    if (states.contains(WidgetState.disabled)) return _disabledInk(c);
    return states.contains(WidgetState.selected)
        ? c.onSecondaryContainer
        : c.onSurfaceVariant;
  }

  return ChipThemeData(
    shape: MoshShapes.pill,
    side: _chipEdge(
        c,
        (states) => states.contains(WidgetState.selected)
            ? BorderSide.none
            : BorderSide(color: c.outlineVariant)),
    color: WidgetStateProperty.resolveWith((states) {
      final lit = states.contains(WidgetState.selected);
      if (states.contains(WidgetState.disabled)) {
        return lit ? _disabledPlate(c) : Colors.transparent;
      }
      return _hovered(
          states, lit ? c.secondaryContainer : Colors.transparent, ink(states));
    }),
    showCheckmark: false,
    elevation: 0,
    pressElevation: 0,
    padding: const EdgeInsets.symmetric(horizontal: MoshSpace.s2),
    labelPadding: const EdgeInsets.symmetric(horizontal: MoshSpace.s1),
    labelStyle:
        text.labelLarge!.copyWith(color: WidgetStateColor.resolveWith(ink)),
  );
}

/// The Progress card: a 24 px spinner and a 4 px bar in saffron.
ProgressIndicatorThemeData _progressTheme(MoshColors c) =>
    ProgressIndicatorThemeData(
      color: c.primary,
      linearTrackColor: c.surfaceContainerHighest,
      linearMinHeight: MoshSpace.s1,
      borderRadius: const BorderRadius.all(Radius.circular(MoshRadius.full)),
      circularTrackColor: Colors.transparent,
      // The Medium spinner; a wait that fills a screen sizes its own.
      strokeWidth: MoshBorder.thick,
      constraints:
          const BoxConstraints(minWidth: MoshSpace.s6, minHeight: MoshSpace.s6),
      stopIndicatorColor: Colors.transparent,
      trackGap: 0,
    );

/// The Slider card: the played part is saffron; the thumb grows under the
/// pointer, the finger and the keyboard focus.
SliderThemeData _sliderTheme(MoshColors c) => SliderThemeData(
      trackHeight: MoshSpace.s1,
      trackShape: const _EvenTrack(),
      activeTrackColor: c.primary,
      inactiveTrackColor: c.surfaceContainerHighest,
      disabledActiveTrackColor: _disabledInk(c),
      disabledInactiveTrackColor: c.surfaceContainerHighest,
      thumbColor: c.primary,
      disabledThumbColor: _disabledInk(c),
      thumbShape: const _Thumb(),
      // The slider hands the thumb its pressed size only beside a track gap.
      trackGap: 0,
      thumbSize: WidgetStateProperty.resolveWith((states) => Size.square(
          states.contains(WidgetState.pressed) ? _Thumb.dragged : _Thumb.rest)),
      overlayShape: _ThumbHalo(ring: c.focusRing),
      // The slider resolves this by state and hands the halo the result.
      overlayColor: WidgetStateColor.resolveWith((states) =>
          states.contains(WidgetState.focused) ? c.focusRing : c.primary),
    );

/// The slider's track: the played part as thick as the rest.
class _EvenTrack extends RoundedRectSliderTrackShape {
  const _EvenTrack();

  @override
  void paint(PaintingContext context, Offset offset,
          {required RenderBox parentBox,
          required SliderThemeData sliderTheme,
          required Animation<double> enableAnimation,
          required TextDirection textDirection,
          required Offset thumbCenter,
          Offset? secondaryOffset,
          bool isDiscrete = false,
          bool isEnabled = false,
          double additionalActiveTrackHeight = 0}) =>
      super.paint(context, offset,
          parentBox: parentBox,
          sliderTheme: sliderTheme,
          enableAnimation: enableAnimation,
          textDirection: textDirection,
          thumbCenter: thumbCenter,
          secondaryOffset: secondaryOffset,
          isDiscrete: isDiscrete,
          isEnabled: isEnabled,
          additionalActiveTrackHeight: 0);
}

/// The slider's thumb, a disc of the size the theme resolves: 16 px at rest
/// and 24 px while it is dragged.
class _Thumb extends SliderComponentShape {
  const _Thumb();

  static const rest = MoshSpace.s4, dragged = MoshSpace.s6;

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) =>
      const Size.square(dragged);

  @override
  void paint(PaintingContext context, Offset center,
      {required Animation<double> activationAnimation,
      required Animation<double> enableAnimation,
      required bool isDiscrete,
      required TextPainter labelPainter,
      required RenderBox parentBox,
      required SliderThemeData sliderTheme,
      required TextDirection textDirection,
      required double value,
      required double textScaleFactor,
      required Size sizeWithOverflow}) {
    final color = Color.lerp(sliderTheme.disabledThumbColor,
        sliderTheme.thumbColor, enableAnimation.value)!;
    context.canvas.drawCircle(center,
        sliderTheme.thumbSize!.resolve({})!.width / 2, Paint()..color = color);
  }
}

/// What stands behind the slider's thumb: the 20 px it grows to under the
/// pointer, or the focus ring 2 px outside it under the keyboard.
class _ThumbHalo extends SliderComponentShape {
  const _ThumbHalo({required this.ring});

  /// The colour the theme resolves under focus, which asks for the ring.
  final Color ring;

  static const _grown = MoshSpace.s5 / 2;

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) =>
      const Size.fromRadius(_grown);

  @override
  void paint(PaintingContext context, Offset center,
      {required Animation<double> activationAnimation,
      required Animation<double> enableAnimation,
      required bool isDiscrete,
      required TextPainter labelPainter,
      required RenderBox parentBox,
      required SliderThemeData sliderTheme,
      required TextDirection textDirection,
      required double value,
      required double textScaleFactor,
      required Size sizeWithOverflow}) {
    final color = sliderTheme.overlayColor!;
    final shown = activationAnimation.value;
    if (color != ring) {
      context.canvas.drawCircle(center, _grown * shown, Paint()..color = color);
      return;
    }
    context.canvas.drawCircle(
        center,
        (_Thumb.rest + MoshBorder.thick) / 2,
        Paint()
          ..color = color.withValues(alpha: color.a * shown)
          ..style = PaintingStyle.stroke
          ..strokeWidth = MoshBorder.thick);
  }
}
