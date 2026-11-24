part of 'mosh_theme.dart';

// The control themes of the Components page in Figma: one function per card
// of `scripts/figma-design/cards/`. Colours, radii, spacing and state layers
// come from Foundations; [platform] picks the desktop or the phone size.

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
        backgroundColor: MoshState.unlessDisabled(c.primary,
            MoshState.tint(c.onSurface, MoshState.disabledContainer)),
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
      backgroundColor: MoshState.unlessDisabled(c.surfaceContainerHighest,
          MoshState.tint(c.onSurface, MoshState.disabledContainer)),
    );

/// The well of the Text field and Select cards. The label stands above it
/// in a [MoshField].
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

/// The Switch card: a saffron track when on, an outlined one when off.
SwitchThemeData _switchTheme(MoshColors c) {
  T pick<T>(Set<WidgetState> states,
      {required T on, required T off, required T disabled}) {
    if (states.contains(WidgetState.disabled)) return disabled;
    return states.contains(WidgetState.selected) ? on : off;
  }

  return SwitchThemeData(
    thumbColor: WidgetStateProperty.resolveWith((states) => pick(states,
        on: c.onPrimary, off: c.outline, disabled: _disabledInk(c))),
    trackColor: WidgetStateProperty.resolveWith((states) => pick(states,
        on: c.primary,
        off: c.surfaceContainerHighest,
        disabled: states.contains(WidgetState.selected)
            ? MoshState.tint(c.onSurface, MoshState.disabledContainer)
            : Colors.transparent)),
    trackOutlineColor: WidgetStateProperty.resolveWith((states) =>
        states.contains(WidgetState.selected)
            ? Colors.transparent
            : pick(states,
                on: c.outline, off: c.outline, disabled: c.outlineVariant)),
    trackOutlineWidth: const WidgetStatePropertyAll(MoshBorder.thin),
    overlayColor: WidgetStateProperty.resolveWith((states) => MoshState.layer(
            states.contains(WidgetState.selected) ? c.onPrimary : c.onSurface)
        .resolve(states)),
  );
}

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
    side: WidgetStateBorderSide.resolveWith((states) =>
        states.contains(WidgetState.selected)
            ? BorderSide.none
            : BorderSide(color: c.outlineVariant)),
    color: WidgetStateProperty.resolveWith((states) {
      if (!states.contains(WidgetState.selected)) return Colors.transparent;
      return states.contains(WidgetState.disabled)
          ? MoshState.tint(c.onSurface, MoshState.disabledContainer)
          : c.secondaryContainer;
    }),
    showCheckmark: false,
    elevation: 0,
    pressElevation: 0,
    padding: const EdgeInsets.symmetric(horizontal: MoshSpace.s2),
    labelPadding: const EdgeInsets.symmetric(horizontal: MoshSpace.s1),
    labelStyle:
        text.labelLarge!.copyWith(color: WidgetStateColor.resolveWith(ink)),
    iconTheme: IconThemeData(
        color: WidgetStateColor.resolveWith(ink), size: MoshSpace.s4),
  );
}

/// The Progress card: a spinner and a 4 px bar in saffron.
ProgressIndicatorThemeData _progressTheme(MoshColors c) =>
    ProgressIndicatorThemeData(
      color: c.primary,
      linearTrackColor: c.surfaceContainerHighest,
      linearMinHeight: MoshSpace.s1,
      borderRadius: const BorderRadius.all(Radius.circular(MoshRadius.full)),
      circularTrackColor: Colors.transparent,
      stopIndicatorColor: Colors.transparent,
      trackGap: 0,
    );

/// The Slider card: the played part is saffron; the thumb grows under the
/// pointer, the finger and the keyboard focus.
SliderThemeData _sliderTheme(MoshColors c) => SliderThemeData(
      trackHeight: MoshSpace.s1,
      activeTrackColor: c.primary,
      inactiveTrackColor: c.surfaceContainerHighest,
      disabledActiveTrackColor: _disabledInk(c),
      disabledInactiveTrackColor: c.surfaceContainerHighest,
      thumbColor: c.primary,
      disabledThumbColor: _disabledInk(c),
      thumbShape: const _GrowingThumb(),
      overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
      overlayColor: c.primary,
    );

/// The slider's thumb: 16 px at rest and 24 px while it is dragged. The
/// overlay behind it makes the 20 px of a hover or a focus.
class _GrowingThumb extends SliderComponentShape {
  const _GrowingThumb();

  static const _rest = MoshSpace.s2, _pressed = MoshSpace.s3;

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) =>
      const Size.fromRadius(_pressed);

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
    context.canvas.drawCircle(
        center,
        _rest + (_pressed - _rest) * activationAnimation.value,
        Paint()..color = color);
  }
}
