// Invite-URI parser. Per ADR 0012, invite-URI parsing is UI work and
// lives here in Dart (NOT in mosh-core).

/// Error codes emitted by [InviteParseError].
enum InviteParseErrorCode {
  invalidUrl,
  invalidScheme,
  missingMesh,
  missingSession,
  missingGroup,
  missingFingerprint,
  invalidFingerprint,
}

/// Exception carrying a single [InviteParseErrorCode].
class InviteParseError implements Exception {
  final InviteParseErrorCode code;

  InviteParseError(this.code);

  @override
  String toString() => 'InviteParseError: $code';
}

/// A parsed single-DM Mosh invite. `peerHint` is nullable (matches TS
/// `peerHint: string | null`). Value equality via `==`/`hashCode` so
/// `expect(actual, equals(expected))` works in tests.
class MoshInvite {
  final String meshId;
  final String sessionId;
  final String? peerHint;
  final String fingerprint;

  const MoshInvite({
    required this.meshId,
    required this.sessionId,
    this.peerHint,
    required this.fingerprint,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MoshInvite &&
          other.meshId == meshId &&
          other.sessionId == sessionId &&
          other.peerHint == peerHint &&
          other.fingerprint == fingerprint;

  @override
  int get hashCode => Object.hash(meshId, sessionId, peerHint, fingerprint);
}

/// A parsed private-group Mosh invite. `label` is nullable (matches TS
/// `label: string | null`).
class MoshGroupInvite {
  final String meshId;
  final String groupId;
  final String? label;
  final String fingerprint;

  const MoshGroupInvite({
    required this.meshId,
    required this.groupId,
    this.label,
    required this.fingerprint,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MoshGroupInvite &&
          other.meshId == meshId &&
          other.groupId == groupId &&
          other.label == label &&
          other.fingerprint == fingerprint;

  @override
  int get hashCode => Object.hash(meshId, groupId, label, fingerprint);
}

// Constants (mirrors the TS module-level consts).

const String _moshInviteScheme = 'mosh';
const String _inviteHost = 'invite';
const String _groupHost = 'group';

const String _meshParam = 'mesh';
const String _sessionParam = 'session';
const String _groupParam = 'group';
const String _peerParam = 'peer';
const String _nameParam = 'name';
const String _fingerprintParam = 'fp';

const int _minTokenLength = 4;
const int _minFingerprintLength = 8;
const int _groupFingerprintLength = 32;

// Alnum start, then alnum/dot/underscore/hyphen. Case-insensitive (mirrors /.../i).
final RegExp _tokenPattern = RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9._-]*$');
// Hex + dashes (before dash-stripping); mirrors /^[a-f0-9-]+$/i.
final RegExp _fingerprintPattern = RegExp(r'^[a-fA-F0-9-]+$');

// Public parsing entry points (top-level pure functions).

/// Parses a single-DM Mosh invite URI. Throws [InviteParseError] on any
/// contract violation.
MoshInvite parseMoshInvite(String rawInvite) {
  final uri = _parseUrl(rawInvite);

  if (uri.scheme != _moshInviteScheme || uri.host != _inviteHost) {
    throw InviteParseError(InviteParseErrorCode.invalidScheme);
  }

  final meshId = _readToken(uri, _meshParam, InviteParseErrorCode.missingMesh);
  final sessionId = _readToken(
    uri,
    _sessionParam,
    InviteParseErrorCode.missingSession,
  );
  final peerHint = _readOptionalToken(uri, _peerParam);
  final fingerprint = _readFingerprint(uri, _minFingerprintLength, false);

  return MoshInvite(
    meshId: meshId,
    sessionId: sessionId,
    peerHint: peerHint,
    fingerprint: fingerprint,
  );
}

/// Parses a private-group Mosh invite URI. Throws [InviteParseError] on any
/// contract violation.
MoshGroupInvite parseMoshGroupInvite(String rawInvite) {
  final uri = _parseUrl(rawInvite);

  if (uri.scheme != _moshInviteScheme || uri.host != _groupHost) {
    throw InviteParseError(InviteParseErrorCode.invalidScheme);
  }

  final meshId = _readToken(uri, _meshParam, InviteParseErrorCode.missingMesh);
  final groupId = _readToken(
    uri,
    _groupParam,
    InviteParseErrorCode.missingGroup,
  );
  final label = _readLabel(uri);
  final fingerprint = _readFingerprint(uri, _groupFingerprintLength, true);

  return MoshGroupInvite(
    meshId: meshId,
    groupId: groupId,
    label: label,
    fingerprint: fingerprint,
  );
}

// Helpers (private).

/// Mirrors TS parseUrl: trim, then Uri.parse; FormatException -> invalid_url.
/// Dart nuance: Uri.parse is far more lenient than the WHATWG URL constructor
/// the TS impl relies on. A bare string like "not a url" parses as a relative
/// URI with an empty scheme and no authority (no FormatException), whereas the
/// TS constructor throws, surfacing as invalid_url. To mirror the contract,
/// treat any result lacking a scheme + authority as invalid_url.
Uri _parseUrl(String rawInvite) {
  try {
    final uri = Uri.parse(rawInvite.trim());
    if (!uri.hasAuthority || uri.scheme.isEmpty) {
      throw InviteParseError(InviteParseErrorCode.invalidUrl);
    }
    return uri;
  } on FormatException {
    throw InviteParseError(InviteParseErrorCode.invalidUrl);
  }
}

/// Mirrors TS `readToken`: required, must satisfy the token pattern.
String _readToken(Uri uri, String param, InviteParseErrorCode code) {
  final value = _readOptionalToken(uri, param);
  if (value == null) {
    throw InviteParseError(code);
  }
  return value;
}

/// Mirrors TS `readOptionalToken`: trim; null if empty or fails token validation.
String? _readOptionalToken(Uri uri, String param) {
  final raw = uri.queryParameters[param];
  if (raw == null) {
    return null;
  }
  final value = raw.trim();
  if (value.isEmpty) {
    return null;
  }
  return value.length >= _minTokenLength && _tokenPattern.hasMatch(value)
      ? value
      : null;
}

/// Mirrors TS `name` handling: `searchParams.get('name')?.trim() || null`.
/// Dart `Uri.queryParameters` URL-decodes but does NOT trim values, so we trim
/// here to match TS exactly.
String? _readLabel(Uri uri) {
  final raw = uri.queryParameters[_nameParam];
  if (raw == null) {
    return null;
  }
  final trimmed = raw.trim();
  return trimmed.isEmpty ? null : trimmed;
}

/// Extracts the raw `fp` value from the URL hash fragment. Requires the
/// explicit `fp=` key (a bare `#AABBCC` fragment is NOT accepted), mirroring
/// the TS `fingerprintFromHash` comment.
String _rawFingerprint(Uri uri) {
  // Dart's `uri.fragment` is the hash WITHOUT the leading `#`, so no stripping
  // is needed (unlike TS `url.hash.replace(/^#/, "")`). Parse it as query params.
  final fragmentParams = Uri.splitQueryString(uri.fragment);
  final raw = fragmentParams[_fingerprintParam]?.trim();
  if (raw == null || raw.isEmpty) {
    throw InviteParseError(InviteParseErrorCode.missingFingerprint);
  }
  return raw;
}

/// Normalizes (strip dashes, uppercase) and validates the fingerprint.
/// [exact] true => group (length must == _groupFingerprintLength);
/// false => invite (length >= _minFingerprintLength). Mirrors TS
/// `readFingerprint` / `readGroupFingerprint`.
String _readFingerprint(Uri uri, int lengthRequirement, bool exact) {
  final raw = _rawFingerprint(uri);
  // Validate raw shape first (hex + dashes). The TS order applies the regex to
  // the normalized (dash-stripped, uppercased) string; since the dash-stripped
  // string is always hex-only there, we check the raw here to also reject
  // non-hex chars that survive normalization (e.g. "zzzz" -> "ZZZZ").
  if (!_fingerprintPattern.hasMatch(raw)) {
    throw InviteParseError(InviteParseErrorCode.invalidFingerprint);
  }

  final normalized = raw.replaceAll('-', '').toUpperCase();
  final lengthOk = exact
      ? normalized.length == lengthRequirement
      : normalized.length >= lengthRequirement;
  if (!lengthOk) {
    throw InviteParseError(InviteParseErrorCode.invalidFingerprint);
  }
  return normalized;
}
