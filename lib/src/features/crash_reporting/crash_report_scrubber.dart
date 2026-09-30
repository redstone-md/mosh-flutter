// The last gate before a crash report leaves the device (ADR 0035).
//
// Reports carry stack traces, error types and versions. They must not carry
// invites (a join capability), network addresses, OS user names, or the
// peer/session/group ids that would expose who talks to whom. Ids are
// replaced by a salted hash, so one install's reports still correlate with
// each other; the salt dies with the opt-out, so nothing links back.
library;

import 'dart:convert' show utf8;
import 'dart:io' show InternetAddress, InternetAddressType;

import 'package:cryptography/dart.dart' show DartSha256;
import 'package:sentry_flutter/sentry_flutter.dart';

/// Hex characters kept from the salted hash: enough to tell ids apart in one
/// install's reports, too few to brute-force back.
const int _idHashHexLength = 8;

final RegExp _invite = RegExp(r'mosh://\S+');
final RegExp _multiaddr =
    RegExp(r'/(?:ip4|ip6|dns|dns4|dns6|dnsaddr)/[^\s,;"' "'" r')\]]+');
final RegExp _ipv4 = RegExp(r'\b\d{1,3}(?:\.\d{1,3}){3}\b');
// Candidates only; `InternetAddress.tryParse` decides, so a clock such as
// 12:34:56 survives.
final RegExp _ipv6Candidate =
    RegExp(r'[0-9A-Fa-f]*:[0-9A-Fa-f]*:[0-9A-Fa-f:.]*');
final RegExp _homeDir = RegExp(r'([\\/](?:Users|home)[\\/])[^\\/\s]+');
final RegExp _id = RegExp(
  r'\b(?:[0-9a-fA-F]{16,}'
  r'|[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}'
  r'|(?:12D3Koo|Qm)[1-9A-HJ-NP-Za-km-z]{30,})\b',
);

class CrashReportScrubber {
  const CrashReportScrubber({required this.salt});

  /// The install's salt from the consent file; see `crash_reporting.rs`.
  final String salt;

  /// Rewrites every identifying token in [text].
  String scrub(String text) => text
      .replaceAll(_invite, '<invite>')
      .replaceAll(_multiaddr, '<addr>')
      .replaceAll(_ipv4, '<ip>')
      .replaceAllMapped(_ipv6Candidate, _maskIpv6)
      .replaceAllMapped(_homeDir, (m) => '${m[1]}<user>')
      .replaceAllMapped(_id, (m) => '<id:${_hash(m[0]!)}>');

  /// Scrubs [event] in place and returns it, as `beforeSend` expects.
  SentryEvent scrubEvent(SentryEvent event) {
    event
      ..serverName = null
      ..user = null;
    final message = event.message;
    if (message != null) {
      message
        ..formatted = scrub(message.formatted)
        ..template = _scrubOrNull(message.template)
        ..params = null;
    }
    for (final exception in event.exceptions ?? const <SentryException>[]) {
      exception.value = _scrubOrNull(exception.value);
      for (final frame in exception.stackTrace?.frames ?? const []) {
        frame
          ..absPath = _scrubOrNull(frame.absPath)
          ..fileName = _scrubOrNull(frame.fileName)
          ..package = _scrubOrNull(frame.package);
      }
    }
    for (final image in event.debugMeta?.images ?? const <DebugImage>[]) {
      image
        ..codeFile = _scrubOrNull(image.codeFile)
        ..debugFile = _scrubOrNull(image.debugFile);
    }
    return event;
  }

  String? _scrubOrNull(String? text) => text == null ? null : scrub(text);

  String _maskIpv6(Match match) {
    final address = InternetAddress.tryParse(match[0]!);
    return address?.type == InternetAddressType.IPv6 ? '<ip>' : match[0]!;
  }

  String _hash(String token) {
    final bytes =
        const DartSha256().hashSync(utf8.encode('$salt:$token')).bytes;
    return bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join()
        .substring(0, _idHashHexLength);
  }
}
