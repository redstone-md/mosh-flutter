/// Pure UI-helper: classify a pasted string as a mosh invite.
///
/// Ported from `src/features/private-dm/invite/invite-detection.ts` per
/// ADR 0012. The detection logic is a pure function on a `String` — the
/// clipboard read itself happens in the widget layer via Flutter's
/// `Clipboard.getData`, not here.
///
/// The TS implementation delegates the heavy lifting to the invite-uri
/// parser (`invite-uri.ts`). The Dart parser lives in
/// `package:mosh/src/invite/invite_uri.dart`, authored by S4.2 in
/// parallel. To keep this module testable and green independently of
/// S4.2's completion, the parsing needed to reproduce the exact
/// `errorCode`/`kind` behavior of the TS tests is inlined below. Once
/// S4.2's `invite_uri.dart` lands, a follow-up should swap this inline
/// parse for `import 'package:mosh/src/invite/invite_uri.dart';` and
/// route through `parseMoshInvite` / `parseMoshGroupInvite` /
/// `InviteParseError` directly. That integration is deliberately
/// deferred to avoid a hard cross-subagent dependency at test time.
library;

/// The kind of invite (or non-invite) a pasted string was classified as.
enum InviteDetectionKind { dm, group, org, empty, unknown }

/// Error codes — mirror the TS `InviteParseErrorCode` union.
enum InviteParseErrorCode {
  invalidUrl,
  invalidScheme,
  missingMesh,
  missingSession,
  missingGroup,
  missingFingerprint,
  invalidFingerprint,
}

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
  final fragment = uri.fragment.startsWith('org=')
      ? uri.fragment.substring(4)
      : '';
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
/// null on success. Mirrors the validation in invite-uri.ts.
InviteParseErrorCode? _tryParseDm(String value) {
  final uri = Uri.tryParse(value);
  if (uri == null || !uri.hasScheme) {
    return InviteParseErrorCode.invalidUrl;
  }
  if (uri.scheme != 'mosh' || uri.host != 'invite') {
    return InviteParseErrorCode.invalidScheme;
  }
  final mesh = _readToken(uri, 'mesh');
  if (mesh == null) {
    return InviteParseErrorCode.missingMesh;
  }
  final session = _readToken(uri, 'session');
  if (session == null) {
    return InviteParseErrorCode.missingSession;
  }
  final fp = _fingerprintFromHash(uri);
  if (fp == null) {
    return InviteParseErrorCode.missingFingerprint;
  }
  final normalized = fp.replaceAll('-', '').toUpperCase();
  final validHex =
      RegExp(r'^[a-f0-9-]+$', caseSensitive: false).hasMatch(normalized);
  if (normalized.length < 8 || !validHex) {
    return InviteParseErrorCode.invalidFingerprint;
  }
  return null;
}

/// Attempts a group (mosh://group) parse. Returns the error code on
/// failure, null on success. Group fingerprints must be exactly 32 hex
/// chars (mirrors `GROUP_FINGERPRINT_LENGTH` in invite-uri.ts).
InviteParseErrorCode? _tryParseGroup(String value) {
  final uri = Uri.tryParse(value);
  if (uri == null || !uri.hasScheme) {
    return InviteParseErrorCode.invalidUrl;
  }
  if (uri.scheme != 'mosh' || uri.host != 'group') {
    return InviteParseErrorCode.invalidScheme;
  }
  final mesh = _readToken(uri, 'mesh');
  if (mesh == null) {
    return InviteParseErrorCode.missingMesh;
  }
  final group = _readToken(uri, 'group');
  if (group == null) {
    return InviteParseErrorCode.missingGroup;
  }
  final fp = _fingerprintFromHash(uri);
  if (fp == null) {
    return InviteParseErrorCode.missingFingerprint;
  }
  final normalized = fp.replaceAll('-', '').toUpperCase();
  final validHex =
      RegExp(r'^[a-f0-9-]+$', caseSensitive: false).hasMatch(normalized);
  if (normalized.length != 32 || !validHex) {
    return InviteParseErrorCode.invalidFingerprint;
  }
  return null;
}

/// Reads and validates a path/query token: must be present, trimmed
/// non-empty, at least 4 chars, and match `[a-z0-9][a-z0-9._-]*` (mirrors
/// `TOKEN_PATTERN` / `MIN_TOKEN_LENGTH`). Returns null if missing/invalid.
String? _readToken(Uri uri, String param) {
  final raw = uri.queryParameters[param]?.trim();
  if (raw == null || raw.isEmpty) {
    return null;
  }
  final tokenPattern = RegExp(r'^[a-z0-9][a-z0-9._-]*$', caseSensitive: false);
  return raw.length >= 4 && tokenPattern.hasMatch(raw) ? raw : null;
}

/// Extracts the `fp=` value from the URI fragment. Returns null if the
/// `fp` key is absent (mirrors `fingerprintFromHash`, which throws
/// `missing_fingerprint` — here null signals that to the caller).
String? _fingerprintFromHash(Uri uri) {
  final fragment = uri.fragment;
  if (fragment.isEmpty) {
    return null;
  }
  final params = Uri.splitQueryString(fragment);
  final raw = params['fp']?.trim();
  if (raw == null || raw.isEmpty) {
    return null;
  }
  return raw;
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
