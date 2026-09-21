// Shared attachment media-source helpers. A downloaded attachment is
// served via `file://` + the absolute
// path (see [localFileSrc]). Streaming media is served by the local
// ephemeral HTTP server below.
//
// [resolveMediaOpen] is the pure decision function for opening an
// attachment: given a descriptor,
// the current view, and the (kind, host) it returns the (src, download,
// wait) decision the screen acts on. Extracted as a pure function so it is
// unit-testable without pumping a widget (the screen wiring stays thin).
library;

import 'package:mosh/src/rust/conversation/attachments.dart';
import 'package:mosh/src/features/shared/attachment_open.dart';
import 'package:mosh/src/features/shared/media_stream_server.dart';

/// image/video/audio. Drives the open affordance.
bool isViewableMedia(String mime) =>
    mime.startsWith('image/') || isStreamableMedia(mime);

/// video/audio. These stream while downloading.
bool isStreamableMedia(String mime) =>
    mime.startsWith('video/') || mime.startsWith('audio/');

/// Matches a Windows path shape: a drive letter with a separator
/// (`C:\...`, `C:/...`) or a UNC share (`\\server\share`). Such paths can sit
/// in the database on any platform (written by a Windows install), so
/// [localFileSrc] must parse them as Windows paths everywhere, not only on
/// Windows where `Uri.file` defaults to it.
final _windowsPath = RegExp(r'^([A-Za-z]:[\\/]|\\\\)');

/// Resolves an already-downloaded attachment without performing a side
/// effect. Media remains an in-app viewer intent; every other file becomes an
/// external-open intent. A missing path returns a no-op for the caller's
/// normal download/media state machine.
AttachmentOpenIntent resolveLocalAttachmentOpen({
  required AttachmentDescriptor descriptor,
  AttachmentView? view,
}) {
  final localPath = view?.localPath;
  if (localPath == null || localPath.isEmpty) {
    return const AttachmentNoopOpenIntent();
  }
  if (isViewableMedia(descriptor.mime)) {
    return AttachmentMediaOpenIntent(
      descriptor: descriptor,
      src: localFileSrc(localPath),
    );
  }
  return AttachmentExternalOpenIntent(localPath: localPath);
}

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

/// The open decision returned by [resolveMediaOpen]:
/// - `src` set + `download` false + `wait` false: already downloaded, show
///   the local file immediately.
/// - `src` set + `download` true + `wait` false: streamable media, stream
///   `streamingMediaSrc` while the download runs.
/// - `src` null + `download` true + `wait` true: image/other, wait for the
///   full download before showing (the pendingOpen resolver drives this).
class MediaOpenDecision {
  const MediaOpenDecision(
      {this.src, required this.download, required this.wait});
  final String? src;
  final bool download;
  final bool wait;
}

/// Pure decision function for opening an attachment. Decides the (src,
/// download, wait) for opening `descriptor` given the
/// current `view` + the streaming (kind, host). The screen calls this and
/// acts: show the viewer with `src` when set, kick the download when
/// `download`, and arm the pendingOpen resolver when `wait`.
MediaOpenDecision resolveMediaOpen({
  required AttachmentDescriptor descriptor,
  AttachmentView? view,
  required String kind,
  required String host,
  Uri? mediaBaseUri,
}) {
  final localPath = view?.localPath;
  if (localPath != null && localPath.isNotEmpty) {
    return MediaOpenDecision(
      src: localFileSrc(localPath),
      download: false,
      wait: false,
    );
  }
  if (isStreamableMedia(descriptor.mime)) {
    return MediaOpenDecision(
      src: streamingMediaSrc(
        kind,
        host,
        descriptor.attachmentId,
        baseUri: mediaBaseUri,
      ),
      download: true,
      wait: false,
    );
  }
  return const MediaOpenDecision(src: null, download: true, wait: true);
}
