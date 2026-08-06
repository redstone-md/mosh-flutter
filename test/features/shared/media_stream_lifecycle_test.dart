// Lifecycle tests for MediaStreamLifecycleOwner that require the Flutter
// widget binding. Kept separate from the pure dart:io server tests in
// media_stream_server_test.dart so those tests can run without the
// TestWidgetsFlutterBinding HTTP mock (which otherwise returns 400 for
// every HttpClient request).
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MediaStreamServer server;
  tearDown(() async => server.close());

  test('lifecycle owner disposes its observer and server', () async {
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
    final owner = await MediaStreamLifecycleOwner.start(server: server);
    expect(server.baseUri, isNotNull);

    owner.didChangeAppLifecycleState(AppLifecycleState.detached);
    await Future<void>.delayed(Duration.zero);

    expect(server.baseUri, isNull);
    await owner.dispose();
  });
}
