/// Pure UI-helper: classify a pasted string as a mosh invite.
///
/// Ported from `src/features/private-dm/invite/invite-detection.ts` per
/// ADR 0012. The detection logic is a pure function on a `String` — the
/// clipboard read itself happens in the widget layer via Flutter's
/// `Clipboard.getData`, not here.
///
/// The TS implementation delegates the heavy lifting to the invite-uri
/// parser (`invite-uri.ts`). The Dart parser lives in
/// `package:mosh/src/invite/invite_uri.dart` (S4.2). This module routes the
/// dm/group parse through `parseMoshInvite` / `parseMoshGroupInvite` and
/// surfaces the canonical `InviteParseError.code` — `invite_uri.dart` is the
/// single source of truth for invite-URI parsing (ADR 0012). It still owns
/// the bits uri has no concept of: `org` bundle detection, the
/// `_InviteFamily` host switch, and the family-branched fingerprint message.
library;

import 'package:mosh/src/invite/invite_uri.dart';

export 'package:mosh/src/invite/invite_uri.dart'
    show InviteParseErrorCode, InviteParseError;

/// The kind of invite (or non-invite) a pasted string was classified as.
enum InviteDetectionKind { dm, group, org, empty, unknown }

/// Result of [detectInvite]. Value-equal so tests mirror TS `toEqual`.
class InviteDetection {
  final InviteDetectionKind kind;
  final InviteParseErrorCode? errorCode;
  final String? errorMessage;

  const InviteDetection({
    required this.kind,
    this.errorCode,
    this.errorMessage,
  });

  @override
  bool operator ==(Object other) =>
      other is InviteDetection &&
      other.kind == kind &&
      other.errorCode == errorCode &&
      other.errorMessage == errorMessage;

  @override
  int get hashCode => Object.hash(kind, errorCode, errorMessage);

  @override
  String toString() =>
      'InviteDetection(kind: $kind, errorCode: $errorCode, errorMessage: $errorMessage)';
}

/// Detects the kind of mosh invite in [value] (trimmed of any surrounding
/// clipboard whitespace). Returns the family and, on failure, the
/// specific parse error code + a human message — exactly mirroring
/// `detectInvite` in invite-detection.ts.
InviteDetection detectInvite(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return const InviteDetection(kind: InviteDetectionKind.empty);
  }

  final dmError = _tryParseDm(trimmed);
  if (dmError == null) {
    return const InviteDetection(kind: InviteDetectionKind.dm);
  }

  final groupError = _tryParseGroup(trimmed);
  if (groupError == null) {
    return const InviteDetection(kind: InviteDetectionKind.group);
  }

  if (_isOrgBundle(trimmed)) {
    return const InviteDetection(kind: InviteDetectionKind.org);
  }

  final family = _detectInviteFamily(trimmed);
  if (family == _InviteFamily.org) {
    return const InviteDetection(
      kind: InviteDetectionKind.unknown,
      errorMessage:
          'Organization bundle needs mesh=…, name=… and #org=<64 hex chars>.',
    );
  }
  final code = family == _InviteFamily.group ? groupError : dmError;
  return InviteDetection(
    kind: InviteDetectionKind.unknown,
    errorCode: code,
    errorMessage: _inviteErrorMessage(code, family),
  );
}

enum _InviteFamily { dm, group, org, unknown }

/// Matches the Rust-side `ParsedOrgBundle::parse` contract — case-sensitive
/// `mosh://org` prefix, `mesh=` and `name=` params present, and a `#org=`
/// fragment of exactly 64 hex characters. Returns false on any other shape.
bool _isOrgBundle(String value) {
  if (!value.startsWith('mosh://org')) {
    return false;
  }
  final uri = Uri.tryParse(value);
  if (uri == null || uri.scheme != 'mosh' || uri.host != 'org') {
    return false;
  }
  final mesh = uri.queryParameters['mesh'];
  final name = uri.queryParameters['name'];
  final fragment =
      uri.fragment.startsWith('org=') ? uri.fragment.substring(4) : '';
  final hex = RegExp(r'^[0-9a-fA-F]{64}$');
  return mesh != null &&
      mesh.isNotEmpty &&
      name != null &&
      name.isNotEmpty &&
      hex.hasMatch(fragment);
}

_InviteFamily _detectInviteFamily(String value) {
  final uri = Uri.tryParse(value);
  if (uri == null || !uri.hasScheme || uri.scheme != 'mosh') {
    return _InviteFamily.unknown;
  }
  switch (uri.host) {
    case 'invite':
      return _InviteFamily.dm;
    case 'group':
      return _InviteFamily.group;
    case 'org':
      return _InviteFamily.org;
    default:
      return _InviteFamily.unknown;
  }
}

/// Attempts a DM (mosh://invite) parse. Returns the error code on failure,
/// null on success. Delegates to the canonical `parseMoshInvite` parser
/// (invite_uri.dart) and reads the thrown `InviteParseError.code`.
InviteParseErrorCode? _tryParseDm(String value) {
  try {
    parseMoshInvite(value);
    return null;
  } on InviteParseError catch (e) {
    return e.code;
  }
}

/// Attempts a group (mosh://group) parse. Returns the error code on
/// failure, null on success. Delegates to the canonical
/// `parseMoshGroupInvite` parser (invite_uri.dart). Group fingerprints must
/// be exactly 32 hex chars (the parser's `GROUP_FINGERPRINT_LENGTH`).
InviteParseErrorCode? _tryParseGroup(String value) {
  try {
    parseMoshGroupInvite(value);
    return null;
  } on InviteParseError catch (e) {
    return e.code;
  }
}

/// Maps a parse error code to the human message shown in the UI, branching
/// on the invite family for the fingerprint message. Mirrors the TS
/// `inviteErrorMessage` switch exactly.
String _inviteErrorMessage(InviteParseErrorCode code, _InviteFamily family) {
  switch (code) {
    case InviteParseErrorCode.invalidUrl:
      return 'Paste the full mosh:// invite link.';
    case InviteParseErrorCode.invalidScheme:
      return 'Invite links must start with mosh://invite or mosh://group.';
    case InviteParseErrorCode.missingMesh:
      return 'Invite link is missing mesh=...';
    case InviteParseErrorCode.missingSession:
      return 'Private chat invite is missing session=...';
    case InviteParseErrorCode.missingGroup:
      return 'Group invite is missing group=...';
    case InviteParseErrorCode.missingFingerprint:
      return 'Invite link is missing #fp=...';
    case InviteParseErrorCode.invalidFingerprint:
      return family == _InviteFamily.group
          ? 'Group fingerprint must be 32 hex characters.'
          : 'Fingerprint must be hex and at least 8 characters.';
  }
}
