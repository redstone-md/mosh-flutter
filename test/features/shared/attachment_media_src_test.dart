// Unit tests for `attachment_media_src.dart` -- the pure helpers + the
// [resolveMediaOpen] decision function that ports React's `openAttachment`
// state machine (use-chat-orchestration.ts L243-265). Pure-function tests:
// no widget pump, no Gateway, no native cdylib -- the screen wiring stays
// thin and is exercised by the per-screen attachment suites instead.
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/src/features/shared/attachment_media_src.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';

AttachmentDescriptor _descriptor({
  required String attachmentId,
  required String mime,
}) =>
    AttachmentDescriptor(
      attachmentId: attachmentId,
      contentHash: 'h-$attachmentId',
      fileName: 'f-$attachmentId',
      mime: mime,
      totalSize: BigInt.zero,
      thumbnailB64: null,
      voice: null,
    );

AttachmentView _view({
  required String attachmentId,
  AttachmentState state = AttachmentState.available,
  String? localPath,
}) =>
    AttachmentView(
      attachmentId: attachmentId,
      direction: 'incoming',
      state: state,
      completedChunks: BigInt.zero,
      chunkCount: BigInt.one,
      localPath: localPath,
    );

final _testMediaBaseUri = Uri(
  scheme: 'http',
  host: '127.0.0.1',
  port: 12345,
);

void main() {
  group('isStreamableMedia', () {
    test('true for video/* and audio/*', () {
      expect(isStreamableMedia('video/mp4'), isTrue);
      expect(isStreamableMedia('video/webm'), isTrue);
      expect(isStreamableMedia('audio/mpeg'), isTrue);
      expect(isStreamableMedia('audio/ogg'), isTrue);
    });

    test('false for image/* and non-media', () {
      expect(isStreamableMedia('image/png'), isFalse);
      expect(isStreamableMedia('image/jpeg'), isFalse);
      expect(isStreamableMedia('application/pdf'), isFalse);
      expect(isStreamableMedia('text/plain'), isFalse);
      expect(isStreamableMedia(''), isFalse);
    });
  });

  group('isViewableMedia', () {
    test('true for image/video/audio', () {
      expect(isViewableMedia('image/png'), isTrue);
      expect(isViewableMedia('video/mp4'), isTrue);
      expect(isViewableMedia('audio/mpeg'), isTrue);
    });

    test('false for non-viewable', () {
      expect(isViewableMedia('application/pdf'), isFalse);
      expect(isViewableMedia('text/plain'), isFalse);
      expect(isViewableMedia(''), isFalse);
    });
  });

  group('localFileSrc', () {
    test('wraps an absolute path in a file:// URL', () {
      // A POSIX-style absolute path keeps its slashes + encodes nothing
      // special here; the assertion is the file scheme + the path verbatim
      // under the file:// authority.
      final src = localFileSrc('/tmp/mosh/abc.bin');
      expect(src, 'file:///tmp/mosh/abc.bin');
    });

    test('normalizes Windows backslashes to forward slashes', () {
      final src = localFileSrc(r'C:\Users\me\Downloads\pic.png');
      expect(src, startsWith('file:///'));
      expect(src, contains('C:/Users/me/Downloads/pic.png'));
      expect(src, isNot(contains(r'\')));
    });

    test('passes an already-schemed URL through verbatim', () {
      const url = 'http://127.0.0.1:12345/dm/sess/att-1';
      expect(localFileSrc(url), url);
      const fileUrl = 'file:///tmp/mosh/abc.bin';
      expect(localFileSrc(fileUrl), fileUrl);
    });

    test('empty path is returned empty', () {
      expect(localFileSrc(''), '');
    });
  });

  group('streamingMediaSrc', () {
    test('fails loudly when the production server is not started', () {
      expect(
        () => streamingMediaSrc('dm', 'session', 'attachment'),
        throwsStateError,
      );
    });

    test('builds the local server shape with encoded components', () {
      final src = streamingMediaSrc(
        'dm',
        'session with space',
        'att/1',
        baseUri: _testMediaBaseUri,
      );
      expect(
        src,
        'http://127.0.0.1:12345/dm/'
        'session%20with%20space/att%2F1',
      );
    });

    test('leaves simple ASCII components unencoded', () {
      final src = streamingMediaSrc(
        'channel',
        'general',
        'att-42',
        baseUri: _testMediaBaseUri,
      );
      expect(src, 'http://127.0.0.1:12345/channel/general/att-42');
    });

    test('kind is interpolated verbatim (not encoded)', () {
      // kind is the path segment, not a user value; React keeps it raw too.
      expect(
        streamingMediaSrc('group', 'g', 'a', baseUri: _testMediaBaseUri),
        'http://127.0.0.1:12345/group/g/a',
      );
    });
  });

  group('resolveMediaOpen', () {
    test('already-downloaded view -> local file src, no download, no wait', () {
      final d = _descriptor(attachmentId: 'a1', mime: 'image/png');
      final v = _view(attachmentId: 'a1', localPath: '/tmp/mosh/a1.png');
      final dec = resolveMediaOpen(
        descriptor: d,
        view: v,
        kind: 'dm',
        host: 'sess',
      );
      expect(dec.src, 'file:///tmp/mosh/a1.png');
      expect(dec.download, isFalse);
      expect(dec.wait, isFalse);
    });

    test('streamable + not downloaded -> stream src + download, no wait', () {
      final d = _descriptor(attachmentId: 'a2', mime: 'video/mp4');
      final dec = resolveMediaOpen(
        descriptor: d,
        view: null,
        kind: 'channel',
        host: 'general',
        mediaBaseUri: _testMediaBaseUri,
      );
      expect(dec.src, 'http://127.0.0.1:12345/channel/general/a2');
      expect(dec.download, isTrue);
      expect(dec.wait, isFalse);
    });

    test('audio is streamable too', () {
      final d = _descriptor(attachmentId: 'a3', mime: 'audio/mpeg');
      final dec = resolveMediaOpen(
        descriptor: d,
        view: null,
        kind: 'group',
        host: 'g-1',
        mediaBaseUri: _testMediaBaseUri,
      );
      expect(dec.src, 'http://127.0.0.1:12345/group/g-1/a3');
      expect(dec.download, isTrue);
      expect(dec.wait, isFalse);
    });

    test('image + not downloaded -> wait + download, no src', () {
      final d = _descriptor(attachmentId: 'a4', mime: 'image/jpeg');
      final dec = resolveMediaOpen(
        descriptor: d,
        view: null,
        kind: 'dm',
        host: 'sess',
      );
      expect(dec.src, isNull);
      expect(dec.download, isTrue);
      expect(dec.wait, isTrue);
    });

    test('other mime + not downloaded -> wait + download, no src', () {
      final d = _descriptor(attachmentId: 'a5', mime: 'application/pdf');
      final dec = resolveMediaOpen(
        descriptor: d,
        view: null,
        kind: 'dm',
        host: 'sess',
      );
      expect(dec.src, isNull);
      expect(dec.download, isTrue);
      expect(dec.wait, isTrue);
    });

    test('empty localPath is treated as not downloaded', () {
      final d = _descriptor(attachmentId: 'a6', mime: 'image/png');
      final v = _view(attachmentId: 'a6', localPath: '');
      final dec = resolveMediaOpen(
        descriptor: d,
        view: v,
        kind: 'dm',
        host: 'sess',
      );
      // image + no usable local path -> wait branch
      expect(dec.src, isNull);
      expect(dec.wait, isTrue);
      expect(dec.download, isTrue);
    });

    test('already-downloaded streamable prefers the local file', () {
      // React's first branch wins: local_path beats streamable.
      final d = _descriptor(attachmentId: 'a7', mime: 'video/mp4');
      final v = _view(attachmentId: 'a7', localPath: '/tmp/mosh/a7.mp4');
      final dec = resolveMediaOpen(
        descriptor: d,
        view: v,
        kind: 'dm',
        host: 'sess',
      );
      expect(dec.src, 'file:///tmp/mosh/a7.mp4');
      expect(dec.download, isFalse);
      expect(dec.wait, isFalse);
    });
  });
}
