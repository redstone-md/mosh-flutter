import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/state/locale_preference_store.dart';
import 'package:mosh/src/state/locale_provider.dart';

import '../support/locale.dart';

void main() {
  Future<Directory> directory() async {
    final dir = await Directory.systemTemp.createTemp('mosh-language-test-');
    addTearDown(() => dir.delete(recursive: true));
    return dir;
  }

  ProviderContainer containerFor(LocalePreferenceStore store) {
    final container = ProviderContainer(overrides: [
      localePreferenceStoreProvider.overrideWithValue(store),
    ]);
    addTearDown(container.dispose);
    return container;
  }

  test('missing, unknown and malformed data select System', () async {
    expect(LocalePreferenceStore(null).read(), isNull);
    final dir = await directory();
    final store = LocalePreferenceStore(dir);
    final file = File('${dir.path}/interface-language');
    expect(store.read(), isNull);
    await file.writeAsString('unsupported');
    expect(store.read(), isNull);
    await file.writeAsBytes([0xff]);
    expect(store.read(), isNull);
  });

  test('manual choices and System survive fresh stores and provider lifetimes',
      () async {
    final dir = await directory();
    for (final locale in [const Locale('ru'), const Locale('en'), null]) {
      final container = containerFor(LocalePreferenceStore(dir));
      await container.read(localeProvider.notifier).setLocale(locale);
      final restarted = containerFor(LocalePreferenceStore(dir));
      expect(restarted.read(localeProvider), locale);
    }
  });

  test('concurrent writes retain selection order', () async {
    final store = LocalePreferenceStore(await directory());
    await Future.wait([
      store.write(const Locale('en')),
      store.write(const Locale('ru')),
      store.write(null),
    ]);
    expect(store.read(), isNull);
  });

  test('a refused atomic write preserves the old choice and permits retry',
      () async {
    final dir = await directory();
    final store = LocalePreferenceStore(dir);
    await store.write(const Locale('en'));
    final obstacle = Directory('${dir.path}/interface-language.tmp');
    await obstacle.create();
    await expectLater(
        store.write(const Locale('ru')), throwsA(isA<FileSystemException>()));
    expect(store.read(), const Locale('en'));
    await obstacle.delete();
    await store.write(const Locale('ru'));
    expect(store.read(), const Locale('ru'));
  });

  test('uninitialized storage and unsupported explicit languages are refused',
      () async {
    final store = LocalePreferenceStore(null);
    await expectLater(store.write(null), throwsStateError);
    expect(() => store.write(const Locale('fr')), throwsArgumentError);
  });

  test('selection publishes after persistence and remains unchanged on refusal',
      () async {
    final pending = Completer<void>();
    final store = MemoryLocalePreferenceStore(const Locale('en'))
      ..pendingWrite = pending.future;
    final container = containerFor(store);
    final saving =
        container.read(localeProvider.notifier).setLocale(const Locale('ru'));
    expect(container.read(localeProvider), const Locale('en'));
    pending.complete();
    await saving;
    expect(container.read(localeProvider), const Locale('ru'));
    store.writeError = Exception('disk refused');
    await expectLater(container.read(localeProvider.notifier).setLocale(null),
        throwsException);
    expect(container.read(localeProvider), const Locale('ru'));
  });

  test('disposing during a save preserves disk intent without publishing state',
      () async {
    final pending = Completer<void>();
    final store = MemoryLocalePreferenceStore()..pendingWrite = pending.future;
    final container = ProviderContainer(overrides: [
      localePreferenceStoreProvider.overrideWithValue(store),
    ]);
    final saving =
        container.read(localeProvider.notifier).setLocale(const Locale('ru'));
    container.dispose();
    pending.complete();
    await saving;
    expect(store.locale, const Locale('ru'));
  });
}
