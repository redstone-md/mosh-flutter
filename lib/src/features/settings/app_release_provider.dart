import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_package_info_provider.dart';

/// A published build, with the page a person opens to download it.
class PublishedRelease {
  const PublishedRelease({
    required this.version,
    required this.pageUri,
    this.assets = const [],
  });

  /// The release version, without the `v` prefix of its git tag.
  final String version;

  /// The release page: notes, installers and their checksums.
  final Uri pageUri;

  /// What the release workflow uploaded: installers and their checksums.
  final List<ReleaseAsset> assets;

  /// The uploaded file named [name], or null when the release lacks it.
  ReleaseAsset? assetNamed(String name) {
    for (final asset in assets) {
      if (asset.name == name) return asset;
    }
    return null;
  }
}

/// One uploaded file of a release.
class ReleaseAsset {
  const ReleaseAsset({required this.name, required this.downloadUri});

  final String name;
  final Uri downloadUri;
}

/// Reads the feed body. Injectable, so parsing and comparison are tested
/// without a socket.
typedef ReleaseFeedReader = Future<String> Function(Uri url);

/// Reads the newest published release from the public repository's release
/// feed.
///
/// The request is a plain GET of a fixed URL: no credential, no identifier and
/// no version of the installed build travels with it.
class GitHubReleaseFeed {
  const GitHubReleaseFeed({ReleaseFeedReader? read}) : _read = read;

  final ReleaseFeedReader? _read;

  /// The list endpoint, not `/releases/latest`: that shorthand means "the most
  /// recent non-prerelease, non-draft release", and the release workflow
  /// publishes `-rc` tags as pre-releases, so About would stay silent about one
  /// until the stable build arrived. A public repository needs no credential.
  static final Uri releasesUrl = Uri.parse(
      'https://api.github.com/repos/redstone-md/mosh-flutter/releases?per_page=10');

  /// The newest published build, pre-releases included. Rows are ordered by
  /// creation date, so the highest version wins rather than the top row.
  Future<PublishedRelease> latest() async {
    final decoded = jsonDecode(await (_read ?? _readOverHttp)(releasesUrl));
    if (decoded is! List<Object?>) {
      throw const FormatException('Release feed is not a list');
    }
    final published = <PublishedRelease>[];
    for (final entry in decoded) {
      if (entry is! Map<String, Object?>) continue;
      final release = _release(entry);
      if (release != null) published.add(release);
    }
    if (published.isEmpty) {
      throw const FormatException('Release feed lists no published release');
    }
    return published.reduce((best, next) =>
        isNewerRelease(next.version, best.version) ? next : best);
  }
}

/// One release row, or null when it is a draft, carries no version, or has no
/// absolute page to send anyone to.
PublishedRelease? _release(Map<String, Object?> entry) {
  if (entry['draft'] == true) return null;
  final tag = entry['tag_name'];
  final page = entry['html_url'];
  if (tag is! String || page is! String) return null;
  final uri = Uri.tryParse(page);
  if (uri == null || !uri.isAbsolute || uri.host.isEmpty) return null;
  final version = tag.replaceFirst(RegExp('^v'), '');
  if (version.isEmpty) return null;
  return PublishedRelease(
    version: version,
    pageUri: uri,
    assets: _assets(entry['assets']),
  );
}

/// Uploaded files, skipping anything the feed describes incompletely rather
/// than inventing a URL for it.
List<ReleaseAsset> _assets(Object? raw) {
  if (raw is! List<Object?>) return const [];
  return [
    for (final entry in raw)
      if (entry is Map<String, Object?>)
        if (entry['name'] case final String name)
          if (entry['browser_download_url'] case final String url)
            if (name.isNotEmpty && url.isNotEmpty)
              ReleaseAsset(name: name, downloadUri: Uri.parse(url)),
  ];
}

/// The host whose artifact would be installed.
enum HostPlatform { windows, macOS, other }

/// The artifact for this host and the checksum published beside it. Both are
/// required: an artifact nobody published a digest for is not installed.
class UpdateCandidate {
  const UpdateCandidate({required this.artifact, required this.checksum});

  final ReleaseAsset artifact;
  final ReleaseAsset checksum;
}

/// What this host would install from [release], or null when the release
/// carries nothing for it — a Linux build has no published installer, and a
/// release whose assets were renamed is not guessed at.
UpdateCandidate? updateCandidateFor(
  PublishedRelease release,
  HostPlatform platform,
) {
  final suffix = switch (platform) {
    HostPlatform.windows => '-setup.exe',
    HostPlatform.macOS => '.dmg',
    HostPlatform.other => null,
  };
  if (suffix == null) return null;
  for (final asset in release.assets) {
    if (!asset.name.endsWith(suffix)) continue;
    if (!asset.name.contains(release.version)) continue;
    final checksum = release.assetNamed('${asset.name}.sha256');
    if (checksum == null) return null;
    return UpdateCandidate(artifact: asset, checksum: checksum);
  }
  return null;
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
