import 'dart:convert';

/// A full-size public invitation for rendering/decoding tests, never a runtime peer.
String deviceLinkQrFixture() =>
    'mosh://device-link/${base64Url.encode(utf8.encode(jsonEncode({
              'version': 2,
              'id': 'a' * 32,
              'expires_at': 1790945000,
              'device': {
                'device_id': 'b' * 64,
                'signing_public_key': 'c' * 64,
                'moss_peer_id': 'd' * 64,
                'name': 'Trusted desktop',
              },
              'secret': List.generate(32, (index) => index + 1),
            }))).replaceAll('=', '')}';
