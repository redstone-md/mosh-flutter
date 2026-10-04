import 'package:flutter/widgets.dart';
import 'package:mosh/src/state/locale_preference_store.dart';

class MemoryLocalePreferenceStore extends LocalePreferenceStore {
  MemoryLocalePreferenceStore([this.locale]) : super(null);
  Locale? locale;
  Object? writeError;
  Future<void>? pendingWrite;

  @override
  Locale? read() => locale;

  @override
  Future<void> write(Locale? locale) async {
    if (pendingWrite != null) await pendingWrite;
    if (writeError != null) throw writeError!;
    this.locale = locale;
  }
}
