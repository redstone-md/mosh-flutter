import 'dart:convert';
import 'dart:io';
import 'package:mosh/src/rust/plus/types.dart';
import 'package:mosh/src/rust/plus/checkout.dart';
import 'package:mosh/src/rust/plus/recovery_types.dart';
import 'plus_config.dart';

class PlusBilling {
  PlusBilling(PlusConfig config)
      : _base = config.server,
        _version = config.mainnet ? 'v2' : 'v1';
  final Uri _base;
  final String _version;
  final HttpClient _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 10);

  Future<Map<String, dynamic>> catalog() =>
      _request('GET', '/$_version/catalog');
  Future<Map<String, dynamic>> create() => _request('POST', '/v1/orders');
  Future<Map<String, dynamic>> refresh(PlusOrder order) =>
      _request('POST', _path(order, 'refresh'), order: order);
  Future<Map<String, dynamic>> issue(PlusOrder order, String blinded) =>
      _request('POST', _path(order, 'issue'),
          order: order, body: {'blinded_message_b64': blinded});

  Future<Map<String, dynamic>> registerSeries(PlusSeries series) =>
      _request('POST', '/v2/series',
          body: {'id': series.id, 'access_token': series.accessToken});
  Future<Map<String, dynamic>> createMainnet(
          PlusSeries series, PlusCheckoutIntent intent) =>
      _request('POST', '/v2/orders', token: series.accessToken, body: {
        'series_id': series.id,
        'asset': intent.asset,
        'request_id': intent.requestId
      });
  Future<Map<String, dynamic>> schedule(PlusSeries series) =>
      _request('GET', '/v2/series/${Uri.encodeComponent(series.id)}',
          token: series.accessToken);
  Future<Map<String, dynamic>> startRecovery(
          PlusSeries series, PlusRecoverySession session) async =>
      _validateRecovery(
          await _request('POST', '/v2/recovery/sessions',
              token: series.accessToken,
              body: {
                'id': session.id,
                'series_id': series.id,
                'poll_token': session.pollToken,
                'public_key_b64': session.publicKeyB64
              }),
          session);
  Future<Map<String, dynamic>> recoveryStatus(PlusRecoverySession session,
          {String? after}) async =>
      _validateRecovery(
          await _request(
              'GET',
              '/v2/recovery/${Uri.encodeComponent(session.id)}/status'
                  '${after == null ? '' : '?after=${Uri.encodeQueryComponent(after)}'}',
              token: session.pollToken),
          session);
  Future<Map<String, dynamic>> recover(PlusRecoverySession session,
          String orderId, PlusRecoveryIssuance request) =>
      _request('POST',
          '/v2/recovery/${Uri.encodeComponent(session.id)}/orders/${Uri.encodeComponent(orderId)}/issue',
          token: session.pollToken,
          body: {
            'blinded_message_b64': request.blindedMessageB64,
            'destination_signature_b64': request.destinationSignatureB64
          });

  Map<String, dynamic> _validateRecovery(
      Map<String, dynamic> json, PlusRecoverySession session) {
    final url = Uri.parse(json['url'] as String);
    if (json['id'] != session.id ||
        json['code'] != session.code ||
        url.origin != _base.origin ||
        url.path != '/recover/${session.id}' ||
        url.userInfo.isNotEmpty ||
        url.hasQuery ||
        url.hasFragment) {
      throw const FormatException('Mosh+ recovery destination changed');
    }
    return json;
  }

  String _path(PlusOrder order, String action) =>
      '/$_version/orders/${Uri.encodeComponent(order.id)}/$action';

  Future<Map<String, dynamic>> _request(String method, String path,
      {PlusOrder? order, String? token, Map<String, dynamic>? body}) async {
    final request = await _client
        .openUrl(method, _base.resolve(path))
        .timeout(const Duration(seconds: 10));
    request.followRedirects = false;
    if (order != null) {
      token = order.accessToken;
      if (token == null) {
        throw const FormatException('Missing Mosh+ order access');
      }
    }
    if (token != null) {
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
