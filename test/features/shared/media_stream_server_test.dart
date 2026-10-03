import 'dart:io';
import 'dart:typed_data';

// ignore_for_file: depend_on_referenced_packages
// These are pure dart:io loopback server tests. Importing the pure-Dart
// `test` package (rather than `flutter_test`) avoids the
// TestWidgetsFlutterBinding HTTP mock, which would otherwise return 400 for
// every HttpClient request and prevent the loopback server from being hit.
// `test` is available transitively via `flutter_test`; the lifecycle test
// that needs the binding lives in media_stream_lifecycle_test.dart.
import 'package:test/test.dart';
import 'package:mosh/src/features/shared/attachment_media_src.dart';
import 'package:mosh/src/features/shared/media_stream_server.dart';
import 'package:mosh/src/rust/api/attachment_stream.dart';

AttachmentStreamRange _range({
  required AttachmentStreamState state,
  List<int> bytes = const <int>[],
  int totalSize = 0,
  String mime = '',
}) =>
    AttachmentStreamRange(
      state: state,
      bytes: Uint8List.fromList(bytes),
      totalSize: BigInt.from(totalSize),
      mime: mime,
    );

Future<List<int>> _body(HttpClientResponse response) async {
  return response.fold<List<int>>(
    <int>[],
    (bytes, chunk) => bytes..addAll(chunk),
  );
}

void main() {
  group('MediaStreamServer', () {
    late MediaStreamServer server;

    tearDown(() async {
      await server.close();
    });

    test('serves a capped GET with range headers and decoded arguments',
        () async {
      String? seenHost;
      String? seenAttachment;
      server = MediaStreamServer(
        fetchRange: ({
          required String kind,
          required String host,
          required String attachmentId,
          required BigInt start,
          required BigInt end,
        }) async {
          expect(kind, 'dm');
          expect(start, BigInt.from(2));
          expect(end, BigInt.from(6));
          seenHost = host;
          seenAttachment = attachmentId;
          return _range(
            state: AttachmentStreamState.ready,
            bytes: <int>[2, 3, 4, 5, 6, 7],
            totalSize: 20,
            mime: 'audio/ogg',
          );
        },
      );
      await server.start();

      final client = HttpClient();
      addTearDown(client.close);
      final uri = Uri.parse(
        '${server.baseUri}/dm/host%20with%20space/att%2F1',
      );
      final request = await client.getUrl(uri);
      request.headers.set('range', 'bytes=2-5');
      final response = await request.close();

      expect(response.statusCode, 206);
      expect(response.headers.value('content-type'), 'audio/ogg');
      expect(response.headers.value('accept-ranges'), 'bytes');
      expect(response.headers.value('content-range'), 'bytes 2-5/20');
      expect(response.headers.contentLength, 4);
      expect(await _body(response), <int>[2, 3, 4, 5]);
      expect(seenHost, 'host with space');
      expect(seenAttachment, 'att/1');
    });

    test('serves HEAD headers without a response body', () async {
      server = MediaStreamServer(
        fetchRange: ({
          required String kind,
          required String host,
          required String attachmentId,
          required BigInt start,
          required BigInt end,
        }) async =>
            _range(
          state: AttachmentStreamState.ready,
          bytes: <int>[1, 2, 3, 4],
          totalSize: 4,
          mime: 'video/mp4',
        ),
      );
      await server.start();

      final client = HttpClient();
      addTearDown(client.close);
      final response = await client
          .headUrl(
            Uri.parse('${server.baseUri}/group/g/a'),
          )
          .then((request) => request.close());

      expect(response.statusCode, 206);
      expect(response.headers.value('content-type'), 'video/mp4');
      expect(response.headers.value('content-range'), 'bytes 0-3/4');
      expect(response.headers.contentLength, 4);
      expect(await _body(response), isEmpty);
    });

    test('polls pending ranges until they become ready', () async {
      var calls = 0;
      server = MediaStreamServer(
        pollInterval: const Duration(milliseconds: 1),
        pollTimeout: const Duration(milliseconds: 100),
        fetchRange: ({
          required String kind,
          required String host,
          required String attachmentId,
          required BigInt start,
          required BigInt end,
        }) async {
          calls++;
          if (calls == 1) {
            return _range(
              state: AttachmentStreamState.pending,
              totalSize: 3,
            );
          }
          return _range(
            state: AttachmentStreamState.ready,
            bytes: <int>[7, 8, 9],
            totalSize: 3,
            mime: 'application/octet-stream',
          );
        },
      );
      await server.start();

      final client = HttpClient();
      addTearDown(client.close);
      final response = await client
          .getUrl(
            Uri.parse('${server.baseUri}/channel/general/a'),
          )
          .then((request) => request.close());

      expect(response.statusCode, 206);
      expect(await _body(response), <int>[7, 8, 9]);
      expect(calls, greaterThanOrEqualTo(2));
    });

    test('maps unknown and fetch errors to 404', () async {
      for (final result in <Future<AttachmentStreamRange> Function()>[
        () async => _range(state: AttachmentStreamState.unknown),
        () async => throw StateError('bridge failure'),
      ]) {
        server = MediaStreamServer(
          fetchRange: ({
            required String kind,
            required String host,
            required String attachmentId,
            required BigInt start,
            required BigInt end,
          }) =>
              result(),
        );
        await server.start();
        final client = HttpClient();
        addTearDown(client.close);
        final response = await client
            .getUrl(
              Uri.parse('${server.baseUri}/dm/h/a'),
            )
            .then((request) => request.close());
        expect(response.statusCode, 404);
        await response.drain<void>();
        await server.close();
      }
    });

    test('returns 416 for invalid and unsatisfiable ranges', () async {
      server = MediaStreamServer(
        fetchRange: ({
          required String kind,
          required String host,
          required String attachmentId,
          required BigInt start,
          required BigInt end,
        }) async =>
            _range(
          state: AttachmentStreamState.ready,
          bytes: <int>[1, 2, 3],
          totalSize: 3,
          mime: 'audio/ogg',
        ),
      );
      await server.start();
      final client = HttpClient();
      addTearDown(client.close);

      final invalid = await client.getUrl(
        Uri.parse('${server.baseUri}/dm/h/a'),
      );
      invalid.headers.set('range', 'bytes=-2');
      final invalidResponse = await invalid.close();
      expect(invalidResponse.statusCode, 416);
      await invalidResponse.drain<void>();

      final unsatisfiable = await client.getUrl(
        Uri.parse('${server.baseUri}/dm/h/a'),
      );
      unsatisfiable.headers.set('range', 'bytes=3-');
      final unsatisfiableResponse = await unsatisfiable.close();
      expect(unsatisfiableResponse.statusCode, 416);
      expect(
        unsatisfiableResponse.headers.value('content-range'),
        'bytes */3',
      );
      await unsatisfiableResponse.drain<void>();
    });

    test('returns 416 for multiple Range header values', () async {
      server = MediaStreamServer(
        fetchRange: ({
          required String kind,
          required String host,
          required String attachmentId,
          required BigInt start,
          required BigInt end,
        }) async =>
            _range(
          state: AttachmentStreamState.ready,
          bytes: <int>[1, 2, 3],
          totalSize: 3,
          mime: 'audio/ogg',
        ),
      );
      await server.start();

      final client = HttpClient();
      addTearDown(client.close);
      final request = await client.getUrl(
        Uri.parse('${server.baseUri}/dm/h/a'),
      );
      request.headers
        ..set('range', 'bytes=0-0')
        ..add('range', 'bytes=2-2');
      final response = await request.close();

      expect(response.statusCode, 416);
      await response.drain<void>();

      final commaSeparated = await client.getUrl(
        Uri.parse('${server.baseUri}/dm/h/a'),
      );
      commaSeparated.headers.set('range', 'bytes=0-0,2-2');
      final commaSeparatedResponse = await commaSeparated.close();
      expect(commaSeparatedResponse.statusCode, 416);
      await commaSeparatedResponse.drain<void>();
    });

    test('serves an empty attachment with viewer-compatible headers', () async {
      server = MediaStreamServer(
        fetchRange: ({
          required String kind,
          required String host,
          required String attachmentId,
          required BigInt start,
          required BigInt end,
        }) async =>
            _range(
          state: AttachmentStreamState.ready,
          totalSize: 0,
          mime: 'audio/ogg',
        ),
      );
      await server.start();

      final client = HttpClient();
      addTearDown(client.close);
      final response = await client
          .getUrl(Uri.parse('${server.baseUri}/dm/h/a'))
          .then((request) => request.close());

      expect(response.statusCode, 206);
      expect(response.headers.value('content-type'), 'audio/ogg');
      expect(response.headers.value('accept-ranges'), 'bytes');
      expect(response.headers.value('content-range'), 'bytes 0-0/0');
      expect(response.headers.contentLength, 0);
      expect(await _body(response), isEmpty);
    });

    test('rejects an explicit range for an empty attachment', () async {
      server = MediaStreamServer(
        fetchRange: ({
          required String kind,
          required String host,
          required String attachmentId,
          required BigInt start,
          required BigInt end,
        }) async =>
            _range(
          state: AttachmentStreamState.ready,
          totalSize: 0,
        ),
      );
      await server.start();

      final client = HttpClient();
      addTearDown(client.close);
      final request = await client.getUrl(
        Uri.parse('${server.baseUri}/dm/h/a'),
      );
      request.headers.set('range', 'bytes=0-0');
      final response = await request.close();

      expect(response.statusCode, 416);
      expect(response.headers.value('content-range'), 'bytes */0');
      await response.drain<void>();
    });

    test('returns 504 after the injected polling timeout', () async {
      server = MediaStreamServer(
        pollInterval: const Duration(milliseconds: 1),
        pollTimeout: const Duration(milliseconds: 10),
        fetchRange: ({
          required String kind,
          required String host,
          required String attachmentId,
          required BigInt start,
          required BigInt end,
        }) async =>
            _range(
          state: AttachmentStreamState.pending,
          totalSize: 100,
        ),
      );
      await server.start();

      final client = HttpClient();
      addTearDown(client.close);
      final response = await client
          .getUrl(
            Uri.parse('${server.baseUri}/dm/h/a'),
          )
          .then((request) => request.close());

      expect(response.statusCode, 504);
      await response.drain<void>();
    });

    test('streamingMediaSrc uses the started server base URI', () async {
      server = MediaStreamServer(
        fetchRange: ({
          required String kind,
          required String host,
          required String attachmentId,
          required BigInt start,
          required BigInt end,
        }) async =>
            _range(state: AttachmentStreamState.unknown),
      );
      await server.start();

      final src = streamingMediaSrc('dm', 'h', 'a', baseUri: server.baseUri);
      final uri = Uri.parse(src);
      expect(uri.port, server.baseUri!.port);
      expect(uri.host, server.baseUri!.host);
      expect(uri.pathSegments, <String>['dm', 'h', 'a']);
    });
  });
}
