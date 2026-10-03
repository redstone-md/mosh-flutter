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
