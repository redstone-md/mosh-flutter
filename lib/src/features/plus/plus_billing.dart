import 'dart:convert';
import 'dart:io';
import 'package:mosh/src/rust/plus/types.dart';
import 'plus_config.dart';

class PlusBilling {
  PlusBilling(PlusConfig config) : _base = config.server;
  final Uri _base;
  final HttpClient _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 10);

  Future<Map<String, dynamic>> catalog() => _request('GET', '/v1/catalog');
  Future<Map<String, dynamic>> create() => _request('POST', '/v1/orders');
  Future<Map<String, dynamic>> refresh(PlusOrder order) =>
      _request('POST', _path(order, 'refresh'), order: order);
  Future<Map<String, dynamic>> issue(PlusOrder order, String blinded) =>
      _request('POST', _path(order, 'issue'),
          order: order, body: {'blinded_message_b64': blinded});

  String _path(PlusOrder order, String action) =>
      '/v1/orders/${Uri.encodeComponent(order.id)}/$action';

  Future<Map<String, dynamic>> _request(String method, String path,
      {PlusOrder? order, Map<String, String>? body}) async {
    final request = await _client
        .openUrl(method, _base.resolve(path))
        .timeout(const Duration(seconds: 10));
    request.followRedirects = false;
    if (order != null) {
      final token = order.accessToken;
      if (token == null) {
        throw const FormatException('Missing Mosh+ order access');
      }
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    }
    if (body != null) {
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
    }
    final response = await request.close().timeout(const Duration(seconds: 15));
    var size = 0;
    final bytes = <int>[];
    await for (final chunk in response.timeout(const Duration(seconds: 15))) {
      size += chunk.length;
      if (size > 65536) throw const FormatException('Oversized Mosh+ response');
      bytes.addAll(chunk);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw const HttpException('Mosh+ request failed');
    }
    return jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
  }

  void close() => _client.close(force: true);
}
