import 'dart:convert';
import 'dart:io';

/// A stand-in wake service on loopback: answers each request with the next
/// queued status and records what it was asked.
class WakeServiceStub {
  WakeServiceStub._(this.server);

  final HttpServer server;
  final requests = <(String, String, String?, Map<String, dynamic>)>[];
  final statuses = <int>[];

  /// The body of every 201.
  Map<String, dynamic> created = {'handle': 'h', 'secret': 's'};

  Uri get uri => Uri.parse('http://127.0.0.1:${server.port}');

  static Future<WakeServiceStub> start() async {
    final stub = WakeServiceStub._(
        await HttpServer.bind(InternetAddress.loopbackIPv4, 0));
    stub.server.listen((request) async {
      final body = await utf8.decoder.bind(request).join();
      stub.requests.add((
        request.method,
        request.uri.path,
        request.headers.value('authorization'),
        body.isEmpty ? {} : jsonDecode(body) as Map<String, dynamic>,
      ));
      final status = stub.statuses.removeAt(0);
      request.response.statusCode = status;
      if (status == 201) request.response.write(jsonEncode(stub.created));
      await request.response.close();
    });
    return stub;
  }

  Future<void> close() => server.close(force: true);
}
