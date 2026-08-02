// Shared attachment media-source helpers -- the 1-1 Flutter port of React's
// `src/features/private-dm/attachment-utils.ts`. React uses Tauri's
// `convertFileSrc` (a custom scheme) for local files; Flutter has no such
// scheme, so a downloaded attachment is served via `file://` + the absolute
// path (see [localFileSrc]). The streaming URL shape
// (`http://moshmedia.localhost/...`) is reserved here to match the slice-3
// Rust moshmedia:// streaming protocol; the viewer just needs the URL
// string, the protocol server itself is slice-3 Rust work.
//
// [resolveMediaOpen] is the pure decision function ported from React
// `use-chat-orchestration.ts` L243-265 `openAttachment`: given a descriptor,
// the current view, and the (kind, host) it returns the (src, download,
// wait) decision the screen acts on. Extracted as a pure function so it is
// unit-testable without pumping a widget (the screen wiring stays thin).
library;

import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';

/// React `isViewableMedia` -- image/video/audio. Drives the open affordance.
bool isViewableMedia(String mime) =>
    mime.startsWith('image/') || isStreamableMedia(mime);

/// React `isStreamableMedia` -- video/audio. These stream while downloading.
bool isStreamableMedia(String mime) =>
    mime.startsWith('video/') || mime.startsWith('audio/');

/// React `localFileSrc` (Tauri `convertFileSrc`) -- Flutter equivalent. A
/// downloaded attachment lives on disk, so it is served via `file://` + the
/// absolute path. `Uri.file` normalizes Windows backslashes to forward
/// slashes and percent-encodes as needed. A path that already starts with a
/// known URL scheme (`http://`, `https://`, `file://` -- e.g. the
/// `moshmedia.localhost` streaming URL) is returned verbatim. A Windows
/// drive-letter path (`C:\...`) is NOT treated as a URL (its `C:` would
/// otherwise parse as a scheme), so it is wrapped in `file://`.
String localFileSrc(String path) {
  if (path.isEmpty) return path;
  // Already a URL (http/https/file -- e.g. the moshmedia streaming URL) --
  // pass through. A Windows drive-letter path `C:\...` is NOT a URL here;
  // `Uri.tryParse` would mis-read `C:` as a scheme, so the check is by
  // explicit prefix, not `hasScheme`.
  if (path.startsWith('http://') ||
      path.startsWith('https://') ||
      path.startsWith('file://')) {
    return path;
  }
  return Uri.file(path).toString();
}

/// React `streamingMediaSrc` -- the moshmedia streaming URL. Same shape as
/// React for parity: `http://moshmedia.localhost/${kind}/${host}/${id}` with
/// host + id percent-encoded. Matches the slice-3 Rust moshmedia://
/// streaming protocol; the viewer only needs the URL string.
String streamingMediaSrc(String kind, String host, String attachmentId) {
  return 'http://moshmedia.localhost/$kind/'
      '${Uri.encodeComponent(host)}/${Uri.encodeComponent(attachmentId)}';
}

/// The open decision returned by [resolveMediaOpen]. Mirrors the three
/// branches of React `openAttachment`:
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

/// Pure port of React `openAttachment` (use-chat-orchestration.ts L243-265).
/// Decides the (src, download, wait) for opening `descriptor` given the
/// current `view` + the streaming (kind, host). The screen calls this and
/// acts: show the viewer with `src` when set, kick the download when
/// `download`, and arm the pendingOpen resolver when `wait`.
MediaOpenDecision resolveMediaOpen({
  required AttachmentDescriptor descriptor,
  AttachmentView? view,
  required String kind,
  required String host,
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
      src: streamingMediaSrc(kind, host, descriptor.attachmentId),
      download: true,
      wait: false,
    );
  }
  return const MediaOpenDecision(src: null, download: true, wait: true);
}
