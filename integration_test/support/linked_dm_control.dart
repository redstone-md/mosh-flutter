import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Coordinates fixtures through adb reverse. This never carries DM traffic.
final class LinkedDmControl {
  LinkedDmControl(this._tester);
  final WidgetTester _tester;
  // Host widget bindings override HttpClient with a fake returning 400.
  // This isolated control channel deliberately uses the SDK's real client.
  final _http = _NativeHttpOverrides().createHttpClient(null);
  final _url = const String.fromEnvironment('MOSH_TEST_CONTROL_URL');
  final _token = const String.fromEnvironment('MOSH_TEST_CONTROL_TOKEN');

  Future<Map<String, dynamic>> ask(String action,
      [Map<String, Object?> data = const {}]) async {
    return (await _tester.runAsync(() => _request(action, data)))!;
  }

  Future<Map<String, dynamic>> _request(
      String action, Map<String, Object?> data) async {
    if (_url.isEmpty || _token.isEmpty) {
      throw StateError('Run this test through scripts/android_linked_dm.dart');
    }
    final request = await _http.postUrl(Uri.parse('$_url/$action'));
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $_token');
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode(data));
    final response =
        await request.close().timeout(const Duration(seconds: 100));
    final body = await utf8.decoder.bind(response).join();
    if (response.statusCode != HttpStatus.ok) {
      throw StateError('Native fixture $action failed: $body');
    }
    return jsonDecode(body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> peer(String target, String action,
          {String? argument, String? body}) =>
      ask('peer', {
        'target': target,
        'action': action,
        'argument': argument,
        'body': body,
      });

  Future<void> concurrentSend(
      String session, Future<void> Function() phoneSend) async {
    await _tester.runAsync(() => Future.wait([
          phoneSend(),
          _request('peer', {
            'target': 'original',
            'action': 'dm_send',
            'argument': session,
            'body': 'Desktop concurrent',
          }),
        ]));
  }

  void close() => _http.close(force: true);
}

final class _NativeHttpOverrides extends HttpOverrides {}
