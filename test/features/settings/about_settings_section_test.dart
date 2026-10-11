import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_theme.dart';
import 'package:mosh/src/features/settings/about_update_notice.dart';
import 'package:mosh/src/features/settings/app_package_info_provider.dart';
import 'package:mosh/src/features/settings/app_release_provider.dart';
import 'package:mosh/src/features/settings/app_update_apply.dart';
import 'package:mosh/src/features/settings/app_update_download.dart';
import 'package:mosh/src/features/settings/app_update_install.dart';
import 'package:mosh/src/features/settings/settings_content.dart';
import 'package:mosh/src/features/settings/settings_navigation.dart';
import 'package:mosh/src/features/settings/settings_screen.dart';
import 'package:mosh/src/features/shared/mosh_progress_bar.dart';

import '../../support/pump.dart';
import '../../support/settings.dart';
import '../../support/update_assets.dart';

PackageInfo _package({String version = '9.8.7-dev', String build = '42'}) =>
    PackageInfo(
      appName: 'Mosh',
      packageName: 'dev.mosh',
      version: version,
      buildNumber: build,
    );

/// Reports scripted progress and finishes when the test says so: the widget
/// test drives the card, the downloader's own I/O is covered where it lives.
class _ScriptedDownloader implements ReleaseDownloader {
  final Completer<File> finished = Completer<File>();
  final List<UpdateCandidate> asked = [];

  @override
  Future<File> download(
    UpdateCandidate candidate, {
    void Function(int received, int? total)? onProgress,
  }) async {
    asked.add(candidate);
    onProgress?.call(512, 1024);
    return finished.future;
  }
}

/// Fails the first attempt, then behaves: the retry the card offers.
class _FlakyDownloader implements ReleaseDownloader {
  _FlakyDownloader(this._delegate);

  final ReleaseDownloader _delegate;
  int attempts = 0;

  @override
  Future<File> download(
    UpdateCandidate candidate, {
    void Function(int received, int? total)? onProgress,
  }) {
    attempts++;
    if (attempts == 1) {
      return Future<File>.error(
          const UpdateDownloadException('connection lost'));
    }
    return _delegate.download(candidate, onProgress: onProgress);
  }
}

Future<void> _pump(
  WidgetTester tester, {
  Future<PackageInfo> Function()? load,
  List<Override> overrides = const [],
  Size size = const Size(1200, 800),
  double scale = 1,
  Locale locale = const Locale('en'),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await pumpScreen(
    tester,
    Theme(
      data: buildMoshTheme(),
      child: Builder(
        builder: (context) => Localizations.override(
          context: context,
          locale: locale,
          child: MediaQuery(
            data: MediaQueryData(
              size: size,
              textScaler: TextScaler.linear(scale),
            ),
            child: const Scaffold(
              body:
                  SettingsContent(section: SettingsSection.about, wide: false),
            ),
          ),
        ),
      ),
    ),
    overrides: [
      if (load != null) appPackageInfoProvider.overrideWith((ref) => load()),
      ...overrides,
    ],
  );
}

void main() {
  testWidgets('a failed package read keeps About usable with unavailable text',
      (tester) async {
    await _pump(tester,
        load: () async => throw StateError('package unavailable'));
    expect(find.text('Version unavailable'), findsOneWidget);
    expect(find.text('Mosh'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the installed version includes platform build overrides',
      (tester) async {
    PackageInfo.setMockInitialValues(
      appName: 'Mosh',
      packageName: 'dev.mosh',
      version: '9.8.7-dev',
      buildNumber: '42',
      buildSignature: '',
    );
    await _pump(tester);
    expect(find.text('Version 9.8.7-dev · build 42'), findsOneWidget);
  });

  testWidgets('pending metadata keeps protection visible and completes safely',
      (tester) async {
    final pending = Completer<PackageInfo>();
    await _pump(tester, load: () => pending.future);
    expect(find.text('Reading version…'), findsOneWidget);
    final l = lookupAppLocalizations(const Locale('en'));
    expect(find.text(l.cryptoNoticeBody), findsOneWidget);
    pending.complete(_package(build: ''));
    await tester.pumpAndSettle();
    expect(find.text('Version 9.8.7-dev'), findsOneWidget);
    expect(find.text('Reading version…'), findsNothing);
  });

  testWidgets('missing version is unavailable rather than an invented build',
      (tester) async {
    await _pump(tester, load: () async => _package(version: ''));
    expect(find.text('Version unavailable'), findsOneWidget);
    expect(find.textContaining('build 42'), findsNothing);
  });

  testWidgets('late metadata after leaving the screen causes no UI update',
      (tester) async {
    final pending = Completer<PackageInfo>();
    await _pump(tester, load: () => pending.future);
    await tester.pumpWidget(const SizedBox.shrink());
    pending.complete(_package());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  for (final (width, scale) in [(390.0, 1.0), (320.0, 2.0)]) {
    testWidgets('Russian About at $width and scale $scale wraps and scrolls',
        (tester) async {
      await _pump(tester,
          load: () async => _package(),
          // The unanswered feed is the widest notice: a message and an action.
          overrides: [
            updateCheckProvider.overrideWith(
                (ref) async => throw StateError('feed unavailable')),
          ],
          size: Size(width, 844),
          scale: scale,
          locale: const Locale('ru'));
      final ru = lookupAppLocalizations(const Locale('ru'));
      final body = find.text(ru.settingsAboutNetworkBody);
      await tester.ensureVisible(body);
      expect(body, findsOneWidget);
      expect(find.textContaining('Версия 9.8.7-dev'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('returning to About retries failed metadata in the same scope',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var reads = 0;
    final container = ProviderContainer(overrides: [
      ...settingsAudioOverrides(),
      appPackageInfoProvider.overrideWith((ref) async {
        reads++;
        if (reads == 1) throw StateError('package unavailable');
        return _package();
      }),
    ]);
    addTearDown(container.dispose);
    container
        .read(settingsSectionProvider.notifier)
        .select(SettingsSection.about);
    await pumpScreen(
        tester, Theme(data: buildMoshTheme(), child: const SettingsScreen()),
        container: container);
    expect(find.text('Version unavailable'), findsOneWidget);
    await tester.tap(find.text('Sound'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('About'));
    await tester.pumpAndSettle();
    expect(find.text('Version 9.8.7-dev · build 42'), findsOneWidget);
    expect(reads, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an available release names its version and opens its page',
      (tester) async {
    final opened = <Uri>[];
    await _pump(tester, load: () async => _package(), overrides: [
      updateCheckProvider.overrideWith((ref) async => PublishedRelease(
          version: '0.22.0',
          pageUri: Uri.parse('https://example.test/releases/0.22.0'))),
      releasePageOpenerProvider.overrideWithValue((page) async {
        opened.add(page);
        return true;
      }),
    ]);

    expect(find.text('Version 0.22.0 is available.'), findsOneWidget);
    await tester.tap(find.text('Open release page'));
    await tester.pumpAndSettle();

    expect(opened, [Uri.parse('https://example.test/releases/0.22.0')]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a current installation promises nothing to download',
      (tester) async {
    await _pump(tester, load: () async => _package(), overrides: [
      updateCheckProvider.overrideWith((ref) async => null),
    ]);

    expect(find.text('This is the newest release.'), findsOneWidget);
    expect(find.byType(TextButton), findsNothing);
  });

  testWidgets('a refused page reports itself instead of failing silently',
      (tester) async {
    await _pump(tester, load: () async => _package(), overrides: [
      updateCheckProvider.overrideWith((ref) async => PublishedRelease(
          version: '0.22.0',
          pageUri: Uri.parse('https://example.test/releases/0.22.0'))),
      releasePageOpenerProvider.overrideWithValue((page) async => false),
    ]);

    await tester.tap(find.text('Open release page'));
    await tester.pumpAndSettle();

    expect(find.text('Could not open the release page.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a page the platform throws on reports itself, not an exception',
      (tester) async {
    await _pump(tester, load: () async => _package(), overrides: [
      updateCheckProvider.overrideWith((ref) async => PublishedRelease(
            version: '0.22.0',
            pageUri: Uri.parse('https://example.test/releases/0.22.0'),
          )),
      releasePageOpenerProvider
          .overrideWithValue((page) async => throw StateError('no handler')),
    ]);

    await tester.tap(find.text('Open release page'));
    await tester.pumpAndSettle();

    expect(find.text('Could not open the release page.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a failed check explains itself and retries on demand',
      (tester) async {
    var reads = 0;
    await _pump(tester, load: () async => _package(), overrides: [
      updateCheckProvider.overrideWith((ref) async {
        reads++;
        if (reads == 1) throw StateError('feed unavailable');
        return null;
      }),
    ]);

    expect(find.text('Could not check for updates.'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    expect(find.text('This is the newest release.'), findsOneWidget);
    expect(reads, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an unknown installed version never asks the feed',
      (tester) async {
    var reads = 0;
    await _pump(tester, load: () async => _package(version: ''), overrides: [
      updateCheckProvider.overrideWith((ref) async {
        reads++;
        return null;
      }),
    ]);

    expect(find.text('Version unavailable'), findsOneWidget);
    expect(find.text('This is the newest release.'), findsNothing);
    expect(find.text('Checking for updates…'), findsNothing);
    expect(reads, 0);
  });

  testWidgets('Update downloads the artifact, then hands it to the installer',
      (tester) async {
    final downloader = _ScriptedDownloader();
    final applied = <String>[];
    final terminated = <int>[];
    await _pump(tester, load: () async => _package(), overrides: [
      updateCheckProvider.overrideWith((ref) async => releaseWithAssets()),
      hostPlatformProvider.overrideWithValue(HostPlatform.windows),
      releaseDownloaderProvider.overrideWithValue(downloader),
      updateApplierProvider.overrideWithValue(WindowsUpdateApplier(
        start: (executable, arguments, mode) async => applied.add(executable),
        terminate: terminated.add,
      )),
    ]);

    expect(find.text('Version 0.22.0 is available.'), findsOneWidget);
    await tester.tap(find.text('Update'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Downloading the update… 50%'), findsOneWidget);
    expect(
      tester.widget<MoshProgressBar>(find.byType(MoshProgressBar)).fraction,
      moreOrLessEquals(0.5, epsilon: 0.01),
    );
    expect(downloader.asked.single.artifact.name, 'mosh-0.22.0-setup.exe');

    downloader.finished.complete(File('/updates/mosh-0.22.0-setup.exe'));
    await tester.pumpAndSettle();

    expect(find.text('Installing and restarting…'), findsOneWidget);
    expect(applied, ['/updates/mosh-0.22.0-setup.exe']);
    expect(terminated, [0]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a sandboxed macOS build offers the release page, not a button',
      (tester) async {
    await _pump(tester, load: () async => _package(), overrides: [
      updateCheckProvider.overrideWith((ref) async => releaseWithAssets(
            assetNames: const [
              'Mosh_0.22.0_universal.dmg',
              'Mosh_0.22.0_universal.dmg.sha256',
            ],
          )),
      hostPlatformProvider.overrideWithValue(HostPlatform.macOS),
    ]);

    expect(find.text('Version 0.22.0 is available.'), findsOneWidget);
    expect(find.text('Open release page'), findsOneWidget);
    expect(find.text('Update'), findsNothing);
  });

  testWidgets('a failed update explains itself and retries on demand',
      (tester) async {
    final downloader = _ScriptedDownloader()
      ..finished.complete(File('/updates/mosh-0.22.0-setup.exe'));
    final flaky = _FlakyDownloader(downloader);
    await _pump(tester, load: () async => _package(), overrides: [
      updateCheckProvider.overrideWith((ref) async => releaseWithAssets()),
      hostPlatformProvider.overrideWithValue(HostPlatform.windows),
      releaseDownloaderProvider.overrideWithValue(flaky),
      updateApplierProvider.overrideWithValue(WindowsUpdateApplier(
        start: (executable, arguments, mode) async {},
        terminate: (_) {},
      )),
    ]);

    await tester.tap(find.text('Update'));
    await tester.pumpAndSettle();

    expect(find.text('Could not update.'), findsOneWidget);
    expect(flaky.attempts, 1);

    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    expect(flaky.attempts, 2);
    expect(find.text('Installing and restarting…'), findsOneWidget);
  });
}
