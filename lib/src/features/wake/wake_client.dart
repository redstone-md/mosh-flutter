import 'dart:convert';
import 'dart:io';

import 'package:mosh/src/rust/conversation/wake.dart';

/// The push address a phone registers: an iPhone's APNs tokens, or an
/// Android phone's Firebase installation id (mosh-wake/README.md).
sealed class WakeTokens {
  const WakeTokens();

  factory WakeTokens.fromJson(Map<String, dynamic> json) =>
      switch (json['fcm']) {
        final String installation => FcmWakeTokens(installation),
        _ => AppleWakeTokens.fromJson(json),
      };

  Map<String, dynamic> toJson();
}

/// `voip` rings a call through PushKit, `apns` shows message alerts.
/// `environment` is APNs's: `sandbox` for Xcode builds, `production` for
/// TestFlight and the App Store.
final class AppleWakeTokens extends WakeTokens {
  const AppleWakeTokens({this.voip, this.apns, required this.environment});

  factory AppleWakeTokens.fromJson(Map<String, dynamic> json) =>
      AppleWakeTokens(
          voip: json['voip'] as String?,
          apns: json['apns'] as String?,
          environment: json['environment'] as String);

  final String? voip;
  final String? apns;
  final String environment;

  @override
  Map<String, dynamic> toJson() => {
        if (voip != null) 'voip': voip,
        if (apns != null) 'apns': apns,
        'environment': environment,
      };

  @override
  bool operator ==(Object other) =>
      other is AppleWakeTokens &&
      other.voip == voip &&
      other.apns == apns &&
      other.environment == environment;

  @override
  int get hashCode => Object.hash(voip, apns, environment);
}

/// One Firebase installation id carries both calls and messages.
final class FcmWakeTokens extends WakeTokens {
  const FcmWakeTokens(this.installation);

  final String installation;

  @override
  Map<String, dynamic> toJson() => {'fcm': installation};

  @override
  bool operator ==(Object other) =>
      other is FcmWakeTokens && other.installation == installation;

  @override
  int get hashCode => installation.hashCode;
}

/// This device's entry at a wake service: contacts get `handle`; `secret`
/// stays on the device and is what updates the entry.
final class WakeRegistration {
  const WakeRegistration({
    required this.service,
    required this.handle,
    required this.secret,
  });

  final Uri service;
  final String handle;
  final String secret;

  /// A stored registration, or null when there is none or it does not read.
  static WakeRegistration? tryParse(String? stored) {
    if (stored == null) return null;
    try {
      final json = jsonDecode(stored) as Map<String, dynamic>;
      return WakeRegistration(
          service: Uri.parse(json['service'] as String),
          handle: json['handle'] as String,
          secret: json['secret'] as String);
    } on Object {
      return null;
    }
  }

  String toJson() => jsonEncode({
        'service': service.toString(),
        'handle': handle,
        'secret': secret,
      });
}

/// How a wake went: `forgotten` means the service has nothing to wake for
/// that kind, an unknown handle or a phone without the token for it; only a
/// call's drops the handle, as texts need the alert token a phone may lack.
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
        secret: json['secret'] as String);
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
        if (callId == null) ...{
          'kind': 'message',
          if (request.preview != null) 'preview': request.preview,
        } else ...{
          'kind': 'call',
          'call': callId
        },
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
    // A body that stalls cancels the response, freeing its socket.
    final text = await utf8.decoder.bind(response.timeout(_timeout)).join();
    return (response.statusCode, text);
  }
}
