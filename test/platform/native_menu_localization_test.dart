import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/platform/native_menu_labels.dart';
import 'package:mosh/src/platform/native_menu_localization.dart';
import 'package:mosh/src/state/locale_preference_store.dart';
import 'package:mosh/src/state/locale_provider.dart';

import '../support/locale.dart';

const _channel = MethodChannel('mosh/interface-menu');

Future<ProviderContainer> _pump(WidgetTester tester) async {
  final container = ProviderContainer(overrides: [
    localePreferenceStoreProvider
        .overrideWithValue(MemoryLocalePreferenceStore(const Locale('en'))),
    nativeMenuChannelProvider.overrideWithValue(_channel),
  ]);
  addTearDown(container.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: Consumer(
        builder: (context, ref, _) => MaterialApp(
              locale: ref.watch(localeProvider),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: NativeMenuLocalization(
                  child: Builder(
                      builder: (context) => Text(AppLocalizations.of(context)!
                          .interfaceLanguageTitle))),
            )),
  ));
  await tester.pumpAndSettle();
  return container;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  testWidgets(
      'resolved language updates every existing menu label through the channel',
      (tester) async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(_channel, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(_channel, null));
    final container = await _pump(tester);
    expect(calls.single.method, 'localize');
    expect((calls.single.arguments as Map)['nativeMenuCopy'], 'Copy');
    await container.read(localeProvider.notifier).setLocale(const Locale('ru'));
    await tester.pumpAndSettle();
    expect(calls.length, 2);
    final labels = Map<String, String>.from(calls.last.arguments as Map);
    expect(labels['nativeMenuCopy'], 'Скопировать');
    expect(labels['nativeMenuQuitMosh'], 'Завершить Mosh');
    final xib = File('macos/Runner/Base.lproj/MainMenu.xib').readAsStringSync();
    final ids = RegExp(r'<menuItem identifier="([^"]+)"')
        .allMatches(xib)
        .map((m) => m[1]!)
        .toSet();
    expect(ids.length, 51);
    expect(labels.keys.toSet(), {...ids, 'nativeMenuExitFullScreen'});
    expect(labels.values.every((label) => label.isNotEmpty), isTrue);
  });

  testWidgets('English and Russian payloads cover the same native identifiers',
      (tester) async {
    final labels = <Map<String, String>>[];
    messenger.setMockMethodCallHandler(_channel, (call) async {
      labels.add(Map<String, String>.from(call.arguments as Map));
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(_channel, null));
    final container = await _pump(tester);
    await container.read(localeProvider.notifier).setLocale(const Locale('ru'));
    await tester.pumpAndSettle();
    expect(labels[0].keys.toSet(), labels[1].keys.toSet());
    final context = tester.element(find.byType(Text));
    expect(nativeMenuLabels(AppLocalizations.of(context)!), labels.last);
    expect(find.text('Язык интерфейса'), findsOneWidget);
  });

  testWidgets('a refused native update does not prevent Flutter localization',
      (tester) async {
    messenger.setMockMethodCallHandler(_channel, (_) async {
      throw PlatformException(code: 'menu unavailable');
    });
    addTearDown(() => messenger.setMockMethodCallHandler(_channel, null));
    final container = await _pump(tester);
    await container.read(localeProvider.notifier).setLocale(const Locale('ru'));
    await tester.pumpAndSettle();
    expect(find.text('Язык интерфейса'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'an unavailable native plugin does not prevent Flutter localization',
      (tester) async {
    messenger.setMockMethodCallHandler(_channel, null);
    await _pump(tester);
    expect(find.text('Interface language'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
