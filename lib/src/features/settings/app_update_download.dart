import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:path_provider/path_provider.dart';

import 'app_release_provider.dart';

/// A download that cannot be trusted: no usable published checksum, bytes that
/// do not match it, or a server that answered with something other than the
/// artifact.
class UpdateDownloadException implements Exception {
  const UpdateDownloadException(this.message);

  final String message;

  @override
  String toString() => 'UpdateDownloadException: $message';
}

/// One asset opened as a byte stream, with the length the server declared.
class AssetStream {
  const AssetStream({required this.bytes, required this.dispose, this.length});

  final Stream<List<int>> bytes;

  /// Releases the connection; the downloader calls it once, success or not.
  final void Function() dispose;

  /// The declared size, or null when the server does not know it: a progress
  /// bar that cannot be honest stays indeterminate.
  final int? length;
}

/// Opens one asset. Injectable, so tests script progress and failures.
typedef AssetStreamOpener = Future<AssetStream> Function(Uri url);

/// Downloads the artifact of [UpdateCandidate] and refuses anything the
/// published SHA-256 does not account for.
///
/// The checksum is read from the release's own sidecar asset, so the integrity
/// statement is the one published beside the installer rather than a second
/// source that could drift from it.
class ReleaseDownloader {
  const ReleaseDownloader(
      {AssetStreamOpener? open, Future<Directory> Function()? staging})
      : _open = open,
        _staging = staging;

  final AssetStreamOpener? _open;
  final Future<Directory> Function()? _staging;

  /// The verified file. A short, failed or mismatched download is deleted
  /// before the error leaves this method.
  Future<File> download(
    UpdateCandidate candidate, {
    void Function(int received, int? total)? onProgress,
  }) async {
    final expected = parseSha256Sidecar(
      await _readText(candidate.checksum.downloadUri),
      candidate.artifact.name,
    );
    final file = await _stagingFile(candidate.artifact.name);
    final stream =
        await (_open ?? _openOverHttp)(candidate.artifact.downloadUri);
    try {
      final digest = await _write(stream, file,
          onLength: (chunk) => onProgress?.call(chunk, stream.length));
      if (digest != expected) {
        throw const UpdateDownloadException(
            'The download does not match its published checksum.');
      }
      return file;
    } catch (_) {
      await _deleteQuietly(file);
      rethrow;
    } finally {
      stream.dispose();
    }
  }

  /// Streams [stream] into [file] and returns the SHA-256 of what was written.
  Future<String> _write(
    AssetStream stream,
    File file, {
    required void Function(int chunk) onLength,
  }) async {
    final sink = file.openWrite();
    final digest = Sha256().newHashSink();
    try {
      await for (final chunk in stream.bytes) {
        sink.add(chunk);
        digest.add(chunk);
        onLength(chunk.length);
      }
    } finally {
      await sink.close();
    }
    digest.close();
    final hash = await digest.hash();
    return hash.bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  Future<String> _readText(Uri url) async {
    final stream = await (_open ?? _openOverHttp)(url);
    try {
      return await stream.bytes.transform(utf8.decoder).join();
    } finally {
      stream.dispose();
    }
  }

  Future<File> _stagingFile(String name) async {
    final directory = await (_staging ?? _defaultStaging)();
    await directory.create(recursive: true);
    return File('${directory.path}/$name');
  }

  static Future<Directory> _defaultStaging() async =>
      Directory('${(await getApplicationCacheDirectory()).path}/mosh-update');
}

/// Reads one published `hash  filename` line.
///
/// A body without a 64-character digest, or one naming another file, is
/// refused instead of trusted.
String parseSha256Sidecar(String body, String fileName) {
  final line = body
      .split('\n')
      .map((candidate) => candidate.trim())
      .firstWhere((candidate) => candidate.isNotEmpty, orElse: () => '');
  final parts = line.split(RegExp(r'\s+'));
  final digest = parts.isEmpty ? '' : parts.first.toLowerCase();
  if (!RegExp('^[0-9a-f]{64}\$').hasMatch(digest)) {
    throw const UpdateDownloadException(
        'The release publishes no usable checksum.');
  }
  if (parts.length > 1 && parts[1] != fileName) {
    throw UpdateDownloadException(
        'The published checksum names ${parts[1]}, not $fileName.');
  }
  return digest;
}

const _kAssetTimeout = Duration(seconds: 30);

Future<AssetStream> _openOverHttp(Uri url) async {
  final client = HttpClient()..connectionTimeout = _kAssetTimeout;
  try {
    final request = await client.getUrl(url);
    request.headers.set(HttpHeaders.acceptHeader, 'application/octet-stream');
    final response = await request.close().timeout(_kAssetTimeout);
    if (response.statusCode != HttpStatus.ok) {
      throw UpdateDownloadException(
          'The release asset answered ${response.statusCode}.');
    }
    return AssetStream(
      bytes: response.timeout(_kAssetTimeout),
      length: response.contentLength < 0 ? null : response.contentLength,
      dispose: () => client.close(force: true),
    );
  } catch (_) {
    client.close(force: true);
    rethrow;
  }
}

Future<void> _deleteQuietly(File file) async {
  try {
    await file.delete();
  } on FileSystemException {
    // A download that never started has nothing to remove.
  }
}
