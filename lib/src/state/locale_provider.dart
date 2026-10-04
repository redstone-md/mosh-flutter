import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mosh/src/state/locale_preference_store.dart';

final localeProvider =
    NotifierProvider<LocaleNotifier, Locale?>(LocaleNotifier.new);

class LocaleNotifier extends Notifier<Locale?> {
  @override
  Locale? build() => ref.watch(localePreferenceStoreProvider).read();

  /// Null delegates system resolution and live OS changes to Flutter.
  Future<void> setLocale(Locale? locale) async {
    final owner = ref;
    await owner.read(localePreferenceStoreProvider).write(locale);
    if (owner.mounted) state = locale;
  }
}
