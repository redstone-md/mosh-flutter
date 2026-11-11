// A request gets everything it asked for, however many windows that takes.
// The system's player on Android takes a response as the whole of what it
// requested: one that ended at the first window was the end of the media.
import 'dart:io';
import 'dart:typed_data';

// ignore_for_file: depend_on_referenced_packages
// Pure dart:io loopback tests, as in media_stream_server_test.dart.
import 'package:mosh/src/features/shared/media_stream_server.dart';
import 'package:mosh/src/rust/api/attachment_stream.dart';
import 'package:test/test.dart';

const _window = 512 * 1024;
const _size = 2 * _window + 100;
final _file = Uint8List.fromList(List.generate(_size, (i) => i % 251));

void main() {
  late MediaStreamServer server;
  late HttpClient client;

  /// Serves [_file] in the windows asked for. A window starting at or
  /// after [missingFrom] has not been downloaded, [arrivesAfter] times.
  Future<void> serve({int missingFrom = _size, int? arrivesAfter}) async {
    var asked = 0;
    server = MediaStreamServer(
      pollInterval: const Duration(milliseconds: 1),
      pollTimeout: const Duration(milliseconds: 40),
      fetchRange: ({
        required kind,
        required host,
        required attachmentId,
        required start,
        required end,
      }) async {
        final from = start.toInt();
        expect(end.toInt() - from, lessThanOrEqualTo(_window),
            reason: 'no more than a window is held in memory');
        final missing = from >= missingFrom &&
            (arrivesAfter == null || asked++ < arrivesAfter);
        return AttachmentStreamRange(
          state: missing
              ? AttachmentStreamState.pending
              : AttachmentStreamState.ready,
          bytes: missing
              ? Uint8List(0)
              : Uint8List.sublistView(
                  _file, from, end.toInt().clamp(from, _size)),
          totalSize: BigInt.from(_size),
          mime: 'video/mp4',
        );
      },
    );
    await server.start();
    addTearDown(server.close);
    client = HttpClient();
    addTearDown(() => client.close(force: true));
  }

  Future<HttpClientResponse> get({String? range}) async {
    final request = await client.getUrl(Uri.parse('${server.baseUri}/dm/h/a'));
    if (range != null) request.headers.set('range', range);
    return request.close();
  }

  Future<List<int>> body(HttpClientResponse response) =>
      response.fold(<int>[], (bytes, chunk) => bytes..addAll(chunk));

  test('a request without a range gets the whole attachment', () async {
    await serve();

    final response = await get();

    expect(response.statusCode, 206);
    expect(
        response.headers.value('content-range'), 'bytes 0-${_size - 1}/$_size');
    expect(response.headers.contentLength, _size);
    expect(await body(response), _file);
  });

  test('an open range runs from its start to the attachment\'s end', () async {
    await serve();

    final response = await get(range: 'bytes=600000-');

    expect(response.headers.value('content-range'),
        'bytes 600000-${_size - 1}/$_size');
    expect(await body(response), _file.sublist(600000));
  });

  test('a range longer than a window is served whole', () async {
    await serve();

    final response = await get(range: 'bytes=10-999999');

    expect(response.headers.value('content-range'), 'bytes 10-999999/$_size');
    expect(await body(response), _file.sublist(10, 1000000));
  });

  test('a window still downloading is waited for', () async {
    await serve(missingFrom: _window, arrivesAfter: 3);

    expect(await body(await get()), _file);
  });

  test('a window that never comes cuts the response short', () async {
    await serve(missingFrom: _window);

    final response = await get();

    // Cut, not ended: the player must not take the first window for the
    // whole attachment.
    await expectLater(body(response), throwsA(isA<HttpException>()));
  });
}
