import 'package:flutter/material.dart';

/// Matches Text's effective font, locale, scale and accessibility overrides.
/// The caller lays out and disposes the temporary painter.
TextPainter conversationTextPainter(
    BuildContext context, String text, TextStyle style,
    {TextWidthBasis widthBasis = TextWidthBasis.parent}) {
  final defaults = DefaultTextStyle.of(context);
  final effective = defaults.style.merge(style).copyWith(
        fontWeight: MediaQuery.boldTextOf(context) ? FontWeight.bold : null,
        height: MediaQuery.maybeLineHeightScaleFactorOverrideOf(context),
        letterSpacing: MediaQuery.maybeLetterSpacingOverrideOf(context),
        wordSpacing: MediaQuery.maybeWordSpacingOverrideOf(context),
      );
  return TextPainter(
    text: TextSpan(text: text, style: effective),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    locale: Localizations.maybeLocaleOf(context),
    textWidthBasis: widthBasis,
    textHeightBehavior: defaults.textHeightBehavior ??
        DefaultTextHeightBehavior.maybeOf(context),
  );
}
