import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/rust/conversation/attachments.dart';

import 'package:mosh/src/features/shared/attachment_media_src.dart';
import 'package:mosh/src/features/conversation/conversation_attachment.dart';
import 'package:mosh/src/features/shared/attachment_open.dart';
import 'package:mosh/src/features/shared/media_stream_server.dart';
import 'package:mosh/src/gateway/conversation_target.dart';
import '../../support/conversation_cases.dart';

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
      // kind is the path segment, not a user value, so it stays raw.
      expect(
        streamingMediaSrc('group', 'g', 'a', baseUri: _testMediaBaseUri),
        'http://127.0.0.1:12345/group/g/a',
      );
    });
  });

  group('ConversationAttachment opening policy', () {
    for (final mime in ['image/png', 'video/mp4']) {
      test('$mime uses an available local path without downloading', () {
        final attachment = ConversationAttachment(
          descriptor: testAttachment(attachmentId: 'local', mime: mime),
          view: testAttachmentView(
            attachmentId: 'local',
            state: AttachmentState.available,
            localPath: '/tmp/local',
          ),
        );
        final plan = attachment.openPlan(const DmTarget('session'));
        expect(plan.intent, isA<AttachmentMediaOpenIntent>());
        expect((plan.intent as AttachmentMediaOpenIntent).src,
            'file:///tmp/local');
        expect((plan.download, plan.wait), (false, false));
      });
    }

    for (final path in [null, '']) {
      test('image with path=$path waits for a download', () {
        final plan = ConversationAttachment(
          descriptor: testAttachment(attachmentId: 'image', mime: 'image/png'),
          view: testAttachmentView(
              attachmentId: 'image',
              state: AttachmentState.offered,
              localPath: path),
        ).openPlan(const DmTarget('session'));
        expect(plan.intent, isA<AttachmentNoopOpenIntent>());
        expect((plan.download, plan.wait), (true, true));
      });
    }

    test('a non-media file without a path cannot open', () {
      final plan = ConversationAttachment(
        descriptor: testAttachment(attachmentId: 'pdf'),
      ).openPlan(const DmTarget('session'));
      expect(plan.intent, isA<AttachmentNoopOpenIntent>());
      expect((plan.download, plan.wait), (false, false));
    });

    for (final target in <AnyConversationTarget>[
      const ChannelTarget('general'),
      const GroupTarget('g')
    ]) {
      test('${target.kind.name} streams media while downloading', () async {
        final server = MediaStreamServer.instance;
        await server.start();
        addTearDown(server.close);
        final mime = target.kind == ConversationKind.channel
            ? 'video/mp4'
            : 'audio/mpeg';
        final plan = ConversationAttachment(
          descriptor: testAttachment(attachmentId: 'stream', mime: mime),
        ).openPlan(target);
        expect(plan.intent, isA<AttachmentMediaOpenIntent>());
        expect((plan.intent as AttachmentMediaOpenIntent).src,
            streamingMediaSrc(target.kind.name, target.id, 'stream'));
        expect((plan.download, plan.wait), (true, false));
      });
    }
  });
}
