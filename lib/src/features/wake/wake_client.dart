import 'dart:convert';
import 'dart:io';

import 'package:mosh/src/rust/private_dm_runtime/wake.dart';

/// The push tokens an iPhone registers: `voip` rings a call through PushKit,
/// `apns` shows the "New message" alert. `environment` is APNs's: `sandbox`
/// for Xcode builds, `production` for TestFlight and the App Store.
final class WakeTokens {
  const WakeTokens({this.voip, this.apns, required this.environment});

  factory WakeTokens.fromJson(Map<String, dynamic> json) => WakeTokens(
      voip: json['voip'] as String?,
      apns: json['apns'] as String?,
      environment: json['environment'] as String);

  final String? voip;
  final String? apns;
  final String environment;

  Map<String, dynamic> toJson() => {
        if (voip != null) 'voip': voip,
        if (apns != null) 'apns': apns,
        'environment': environment,
      };

  @override
  bool operator ==(Object other) =>
      other is WakeTokens &&
      other.voip == voip &&
      other.apns == apns &&
      other.environment == environment;

  @override
  int get hashCode => Object.hash(voip, apns, environment);
}

/// This device's entry at a wake service: contacts get `handle`; `secret`
/// stays on the device and is what updates the entry.
final class WakeRegistration {
  const WakeRegistration({
    required this.service,
    required this.handle,
    required this.secret,
    this.tokens,
  });

  final Uri service;
  final String handle;
  final String secret;

  /// The tokens the service holds for this entry.
  final WakeTokens? tokens;

  WakeRegistration withTokens(WakeTokens tokens) => WakeRegistration(
      service: service, handle: handle, secret: secret, tokens: tokens);

  /// A stored registration, or null when there is none or it does not read.
  static WakeRegistration? tryParse(String? stored) {
    if (stored == null) return null;
    try {
      final json = jsonDecode(stored) as Map<String, dynamic>;
      final tokens = json['tokens'];
      return WakeRegistration(
          service: Uri.parse(json['service'] as String),
          handle: json['handle'] as String,
          secret: json['secret'] as String,
          tokens: tokens == null
              ? null
              : WakeTokens.fromJson(tokens as Map<String, dynamic>));
    } on Object {
      return null;
    }
  }

  String toJson() => jsonEncode({
        'service': service.toString(),
        'handle': handle,
        'secret': secret,
        if (tokens != null) 'tokens': tokens!.toJson(),
      });
}

/// How a wake went: `forgotten` means the service no longer knows the handle.
enum WakeOutcome { sent, forgotten, refused }

const _timeout = Duration(seconds: 10);

/// The wake service's HTTP API (mosh-wake/README.md).
class WakeClient {
  final HttpClient _client = HttpClient()..connectionTimeout = _timeout;

  Future<WakeRegistration> register(Uri service, WakeTokens tokens) async {
    final (status, body) =
        await _request('POST', _at(service, 'v1/devices'), tokens.toJson());
    if (status != HttpStatus.created) {
      throw HttpException('wake registration refused: $status');
    }
    final json = jsonDecode(body) as Map<String, dynamic>;
    return WakeRegistration(
        service: service,
        handle: json['handle'] as String,
        secret: json['secret'] as String,
        tokens: tokens);
  }

  /// Replaces the tokens of `registration`; false when the service no longer
  /// has it, so the device registers anew.
  Future<bool> update(WakeRegistration registration, WakeTokens tokens) async {
    final (status, _) = await _request(
        'PUT', _device(registration), tokens.toJson(),
        secret: registration.secret);
    if (status == HttpStatus.unauthorized) return false;
    if (status != HttpStatus.noContent) {
      throw HttpException('wake update refused: $status');
    }
    return true;
  }

  Future<WakeOutcome> wake(WakeRequest request) async {
    final callId = request.callId;
    try {
      final (status, _) =
          await _request('POST', _at(Uri.parse(request.service), 'v1/wake'), {
        'handle': request.handle,
        if (callId == null)
          'kind': 'message'
        else ...{'kind': 'call', 'call': callId},
      });
      return switch (status) {
        HttpStatus.accepted => WakeOutcome.sent,
        HttpStatus.notFound => WakeOutcome.forgotten,
        _ => WakeOutcome.refused,
      };
    } on Object {
      // An unreachable service is like a busy one: the sender tries again
      // with the next call or the next queued text.
      return WakeOutcome.refused;
    }
  }

  void close() => _client.close(force: true);

  Uri _device(WakeRegistration registration) => _at(registration.service,
      'v1/devices/${Uri.encodeComponent(registration.handle)}');

  /// `path` under the service's own path, so a service behind a proxy
  /// prefix keeps it.
  static Uri _at(Uri service, String path) {
    final base = service.path.endsWith('/') ? service.path : '${service.path}/';
    return service.replace(path: '$base$path');
  }

  Future<(int, String)> _request(String method, Uri uri, Object body,
      {String? secret}) async {
    final request = await _client.openUrl(method, uri).timeout(_timeout);
    request.followRedirects = false;
    if (secret != null) {
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $secret');
    }
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode(body));
    final response = await request.close().timeout(_timeout);
    final text = await utf8.decoder.bind(response).join().timeout(_timeout);
    return (response.statusCode, text);
  }
}
