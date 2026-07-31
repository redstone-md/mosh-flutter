// ADR 0014 seam: holds the app Locale so the (deferred) manual-switch widget can
// flip ru<->en via setLocale without touching MaterialApp. Default derives from
// the device locale; MaterialApp resolution clamps to {en, ru}.
//
// Riverpod v3 idiom: class-based Notifier (StateProvider is legacy/deprecated
// in v3.4.x, so we avoid it). Exposing setLocale now means the switch UI lands as
// one widget later, per ADR 0014's "provider plumbing laid now".
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final localeProvider =
    NotifierProvider<LocaleNotifier, Locale>(LocaleNotifier.new);

class LocaleNotifier extends Notifier<Locale> {
  @override
  Locale build() {
    final device = WidgetsBinding.instance.platformDispatcher.locale;
    return device.languageCode.isEmpty ? const Locale('en') : device;
  }

  void setLocale(Locale locale) => state = locale;
}
