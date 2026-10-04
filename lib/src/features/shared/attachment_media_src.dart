import 'package:mosh/src/features/shared/media_stream_server.dart';

enum AttachmentMediaKind { image, video, audio, file }

/// Classifies the MIME prefix once for cards, opening and the viewer.
AttachmentMediaKind attachmentMediaKind(String mime) =>
    switch (mime.split('/')) {
      ['image', _, ...] => AttachmentMediaKind.image,
      ['video', _, ...] => AttachmentMediaKind.video,
      ['audio', _, ...] => AttachmentMediaKind.audio,
      _ => AttachmentMediaKind.file,
    };

bool isViewableMedia(String mime) =>
    attachmentMediaKind(mime) != AttachmentMediaKind.file;

/// video/audio. These stream while downloading.
bool isStreamableMedia(String mime) => switch (attachmentMediaKind(mime)) {
      AttachmentMediaKind.video || AttachmentMediaKind.audio => true,
      _ => false,
    };

/// Matches a Windows path shape: a drive letter with a separator
/// (`C:\...`, `C:/...`) or a UNC share (`\\server\share`). Such paths can sit
/// in the database on any platform (written by a Windows install), so
/// [localFileSrc] must parse them as Windows paths everywhere, not only on
/// Windows where `Uri.file` defaults to it.
final _windowsPath = RegExp(r'^([A-Za-z]:[\\/]|\\\\)');

/// Resolves a downloaded attachment's on-disk path to a `file://` URL. A
/// downloaded attachment lives on disk, so it is served via `file://` + the
/// absolute path. `Uri.file` normalizes Windows backslashes to forward
/// slashes and percent-encodes as needed. A path that already starts with a
/// known URL scheme (`http://`, `https://`, `file://` -- e.g. the
/// local streaming URL) is returned verbatim. A Windows
/// drive-letter path (`C:\...`) is NOT treated as a URL (its `C:` would
/// otherwise parse as a scheme), so it is wrapped in `file://`; such paths
/// are parsed as Windows paths on every platform (see [_windowsPath]).
String localFileSrc(String path) {
  if (path.isEmpty) return path;
  // Already a URL (http/https/file -- e.g. a local streaming URL) --
  // pass through. A Windows drive-letter path `C:\...` is NOT a URL here;
  // `Uri.tryParse` would mis-read `C:` as a scheme, so the check is by
  // explicit prefix, not `hasScheme`.
  if (path.startsWith('http://') ||
      path.startsWith('https://') ||
      path.startsWith('file://')) {
    return path;
  }
  // A Windows-shaped path is parsed with `windows: true` on every platform:
  // on POSIX `Uri.file('C:\...')` treats it as a relative POSIX path and
  // mangles it into `C%3A%5C...` instead of `file:///C:/...`.
  return Uri.file(path, windows: _windowsPath.hasMatch(path)).toString();
}

/// Builds the loopback media URL. [baseUri] keeps the helper deterministic in
/// tests; the running app uses the ephemeral port owned by
/// [MediaStreamServer].
String streamingMediaSrc(
  String kind,
  String host,
  String attachmentId, {
  Uri? baseUri,
}) {
  final base = baseUri ?? MediaStreamServer.instance.baseUri;
  if (base == null) {
    throw StateError('Media stream server is not started');
  }
  return base.replace(
    pathSegments: <String>[kind, host, attachmentId],
    query: null,
    fragment: null,
  ).toString();
}
