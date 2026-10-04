import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mosh/src/platform/app_data_dir.dart';

final localePreferenceStoreProvider = Provider<LocalePreferenceStore>((ref) {
  final path = appDataDir();
  return LocalePreferenceStore(path == null ? null : Directory(path));
});

/// UI preference only. Missing or invalid data means System. Atomic replacement
/// preserves the old choice on refusal; writes from one store stay ordered.
class LocalePreferenceStore {
  LocalePreferenceStore(this.directory);
  final Directory? directory;
  Future<void> _writes = Future.value();

  File? get _file =>
      directory == null ? null : File('${directory!.path}/interface-language');

  Locale? read() {
    try {
      return switch (_file?.readAsStringSync().trim()) {
        'en' => const Locale('en'),
        'ru' => const Locale('ru'),
        _ => null,
      };
    } on FileSystemException {
      return null;
    } on FormatException {
      return null;
    }
  }

  Future<void> write(Locale? locale) {
    final value = switch (locale?.languageCode) {
      null => 'system',
      'en' => 'en',
      'ru' => 'ru',
      _ => throw ArgumentError.value(locale, 'locale', 'Unsupported language'),
    };
    final result = _writes.then((_) => _write(value));
    _writes = result.then((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  Future<void> _write(String value) async {
    final file = _file;
    if (file == null) {
      throw StateError('Application data directory is not initialized');
    }
    await directory!.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(value, flush: true);
    await temporary.rename(file.path);
  }
}
