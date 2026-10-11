import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_package_info_provider.dart';

/// A published build, with the page a person opens to download it.
class PublishedRelease {
  const PublishedRelease({required this.version, required this.pageUri});

  /// The release version, without the `v` prefix of its git tag.
  final String version;

  /// The release page: notes, installers and their checksums.
  final Uri pageUri;
}

/// Reads the feed body. Injectable, so parsing and comparison are tested
/// without a socket.
typedef ReleaseFeedReader = Future<String> Function(Uri url);

/// Reads the newest release from the public repository's release feed.
///
/// Mosh ships unsigned artifacts, so nothing here downloads or installs a
/// build: the feed only answers "is there something newer", and the page it
/// returns is where the platform's own download flow starts.
class GitHubReleaseFeed {
  const GitHubReleaseFeed({ReleaseFeedReader? read}) : _read = read;

  final ReleaseFeedReader? _read;

  /// A public repository with a public feed: no credentials, no proxy, and
  /// nothing about the installation beyond the version it asks about.
  static final Uri latestUrl = Uri.parse(
      'https://api.github.com/repos/redstone-md/mosh-flutter/releases/latest');

  Future<PublishedRelease> latest() async {
    final decoded = jsonDecode(await (_read ?? _readOverHttp)(latestUrl));
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Release feed is not an object');
    }
    final tag = decoded['tag_name'];
    final page = decoded['html_url'];
    if (tag is! String || page is! String || page.isEmpty) {
      throw const FormatException('Release feed lacks a tag or a page');
    }
    return PublishedRelease(
      version: tag.replaceFirst(RegExp('^v'), ''),
      pageUri: Uri.parse(page),
    );
  }
}

const _kFeedTimeout = Duration(seconds: 10);

Future<String> _readOverHttp(Uri url) async {
  final client = HttpClient()..connectionTimeout = _kFeedTimeout;
  try {
    final request = await client.getUrl(url);
    request.headers
      ..set(HttpHeaders.acceptHeader, 'application/vnd.github+json')
      ..set(HttpHeaders.userAgentHeader, 'mosh');
    final response = await request.close().timeout(_kFeedTimeout);
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException('Release feed answered ${response.statusCode}',
          uri: url);
    }
    return await response.transform(utf8.decoder).join().timeout(_kFeedTimeout);
  } finally {
    client.close(force: true);
  }
}

/// True when [candidate] names a newer build than [installed]. Pre-release and
/// build suffixes are ignored, and a build ahead of the feed is not a
/// downgrade prompt.
bool isNewerRelease(String candidate, String installed) {
  final published = _versionNumbers(candidate);
  final current = _versionNumbers(installed);
  for (var part = 0;
      part < math.max(published.length, current.length);
      part++) {
    final left = part < published.length ? published[part] : 0;
    final right = part < current.length ? current[part] : 0;
    if (left != right) return left > right;
  }
  return false;
}

/// Numeric parts of a version; anything unparseable counts as zero, so a
/// surprising tag degrades to "not newer" instead of throwing in a card.
List<int> _versionNumbers(String version) => version
    .split(RegExp('[-+]'))
    .first
    .split('.')
    .map((part) => int.tryParse(part) ?? 0)
    .toList();

/// Injectable, so a test scripts the feed instead of reaching the network.
final releaseFeedProvider =
    Provider<GitHubReleaseFeed>((ref) => const GitHubReleaseFeed());

/// The release the installed build should move to, or null when it is the
/// newest one.
///
/// Mosh is a peer-to-peer app: this provider is only read where a person is
/// already looking at About, it never polls in the background, and leaving
/// the card disposes it. A failed read is not retried on its own.
final updateCheckProvider = FutureProvider.autoDispose<PublishedRelease?>(
  (ref) async {
    final installed = (await ref.watch(appPackageInfoProvider.future)).version;
    final release = await ref.watch(releaseFeedProvider).latest();
    return isNewerRelease(release.version, installed) ? release : null;
  },
  retry: (count, error) => null,
);
