import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:mosh/src/features/settings/app_package_info_provider.dart';
import 'package:mosh/src/features/settings/app_release_provider.dart';

const _payload = '[{"tag_name": "v0.22.0", '
    '"html_url": "https://example.test/releases/0.22.0"},'
    '{"tag_name": "v0.21.0", '
    '"html_url": "https://example.test/releases/0.21.0"}]';

ProviderContainer _container({
  required String installed,
  required String body,
  List<int>? reads,
}) {
  final container = ProviderContainer(overrides: [
    appPackageInfoProvider.overrideWith((ref) async => PackageInfo(
          appName: 'Mosh',
          packageName: 'dev.mosh',
          version: installed,
          buildNumber: '',
        )),
    releaseFeedProvider.overrideWithValue(GitHubReleaseFeed(read: (url) async {
      reads?.add(0);
      return body;
    })),
  ]);
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('a feed read names the version and the page, without the tag prefix',
      () async {
    Uri? asked;
    final feed = GitHubReleaseFeed(read: (url) async {
      asked = url;
      return _payload;
    });

    final release = await feed.latest();

    expect(asked, GitHubReleaseFeed.releasesUrl);
    expect(release.version, '0.22.0');
    expect(release.pageUri, Uri.parse('https://example.test/releases/0.22.0'));
  });

  test('a pre-release is a published build, and the highest version wins',
      () async {
    // The rows arrive newest-first by creation date, which is not version
    // order, and a pre-release is still something About must be able to name.
    const body = '[{"tag_name": "v0.22.0-rc.1", '
        '"html_url": "https://example.test/releases/0.22.0-rc.1"},'
        '{"tag_name": "v0.23.0", '
        '"html_url": "https://example.test/releases/0.23.0"}]';

    final release = await GitHubReleaseFeed(read: (_) async => body).latest();

    expect(release.version, '0.23.0');
  });

  test('a feed of only pre-releases still names one', () async {
    const body = '[{"tag_name": "v0.22.0-rc.1", '
        '"html_url": "https://example.test/releases/0.22.0-rc.1"}]';

    final release = await GitHubReleaseFeed(read: (_) async => body).latest();

    expect(release.version, '0.22.0-rc.1');
  });

  test('a body that is not a release is refused, not guessed at', () async {
    for (final body in [
      '{}',
      '[]',
      '[{"html_url": "https://example.test/releases/0.22.0"}]',
      '[{"tag_name": "v0.22.0"}]',
      '[{"tag_name": "v0.22.0", "html_url": ""}]',
      '[{"tag_name": "v0.22.0", "html_url": "not-a-url"}]',
      '[{"tag_name": "v0.22.0", "html_url": "https://example.test/r",'
          ' "draft": true}]',
    ]) {
      await expectLater(GitHubReleaseFeed(read: (_) async => body).latest(),
          throwsA(isA<FormatException>()),
          reason: body);
    }
  });

  test('an unusable row is skipped while a good one still counts', () async {
    const body = '[{"tag_name": "v0.99.0", "html_url": "not-a-url"},'
        '{"tag_name": "v0.22.0", '
        '"html_url": "https://example.test/releases/0.22.0"}]';

    final release = await GitHubReleaseFeed(read: (_) async => body).latest();

    expect(release.version, '0.22.0');
  });

  test('comparison ignores suffixes and never suggests a downgrade', () {
    expect(isNewerRelease('0.22.0', '0.21.0'), isTrue);
    expect(isNewerRelease('1.0.0', '0.99.99'), isTrue);
    expect(isNewerRelease('0.22.0-rc.1', '0.21.0'), isTrue);
    expect(isNewerRelease('0.21.0', '0.21.0'), isFalse);
    expect(isNewerRelease('0.21.0-rc.1', '0.21.0'), isFalse);
    expect(isNewerRelease('0.20.0', '0.21.0'), isFalse);
    expect(isNewerRelease('0.21', '0.21.0'), isFalse);
    expect(isNewerRelease('nightly', '0.21.0'), isFalse);
  });

  test('a newer release reaches the caller', () async {
    final container = _container(installed: '0.21.0', body: _payload);

    final release = await container.read(updateCheckProvider.future);

    expect(release?.version, '0.22.0');
  });

  test('an installation that is current reports nothing to move to', () async {
    final container = _container(installed: '0.22.0', body: _payload);

    expect(await container.read(updateCheckProvider.future), isNull);
  });

  test('a build ahead of the feed is left alone', () async {
    final container = _container(installed: '0.23.0', body: _payload);

    expect(await container.read(updateCheckProvider.future), isNull);
  });

  test('without a resolved check the feed is never read', () async {
    final reads = <int>[];
    final container = _container(
      installed: '0.21.0',
      body: _payload,
      reads: reads,
    );

    // Watching the package read alone must not reach the network: About gates
    // the notice behind a known installed version.
    await container.read(appPackageInfoProvider.future);

    expect(reads, isEmpty);
  });
}
