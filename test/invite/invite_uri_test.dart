// S4.2: Dart mirror of src/features/private-dm/invite/invite-uri.test.ts.
// Uses the `test` package (available transitively for pure-Dart unit tests under
// `flutter test`). One assertion per TS `it`/`it.each` case.
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/invite/invite_uri.dart';

const String trackerInvite =
    'mosh://invite?mesh=7x9v&session=drift-41#fp=91A4-D2C8-77B0';
const String staticPeerInvite =
    'mosh://invite?mesh=7x9v&session=drift-41&peer=alice#fp=91A4-D2C8-77B0';
const String groupInvite =
    'mosh://group?mesh=mesh-one&group=group-one&name=Friends#fp=AABBCCDDEEFF00112233445566778899';

/// Asserts that [callback] throws an [InviteParseError] whose [code] equals [code].
void expectInviteParseError(
  void Function() callback,
  InviteParseErrorCode code,
) {
  expect(
    callback,
    throwsA(
      allOf(
        isA<InviteParseError>(),
        predicate<InviteParseError>((e) => e.code == code),
      ),
    ),
  );
}

void main() {
  group('parseMoshInvite', () {
    test('parses a tracker-first Mosh invite URI', () {
      expect(
        parseMoshInvite(trackerInvite),
        equals(const MoshInvite(
          meshId: '7x9v',
          sessionId: 'drift-41',
          peerHint: null,
          fingerprint: '91A4D2C877B0',
        )),
      );
    });

    test('keeps optional static peer hints for fallback', () {
      expect(parseMoshInvite(staticPeerInvite).peerHint, 'alice');
    });

    // Mirrors the TS `invalidInvites` array via `it.each`. Six cases.
    test('rejects "not a url" as invalid_url', () {
      expectInviteParseError(
        () => parseMoshInvite('not a url'),
        InviteParseErrorCode.invalidUrl,
      );
    });

    test('rejects https scheme as invalid_scheme', () {
      expectInviteParseError(
        () => parseMoshInvite(
          'https://invite?mesh=7x9v&session=drift-41#fp=91A4D2C8',
        ),
        InviteParseErrorCode.invalidScheme,
      );
    });

    test('rejects missing mesh as missing_mesh', () {
      expectInviteParseError(
        () => parseMoshInvite('mosh://invite?session=drift-41#fp=91A4D2C8'),
        InviteParseErrorCode.missingMesh,
      );
    });

    test('rejects missing session as missing_session', () {
      expectInviteParseError(
        () => parseMoshInvite('mosh://invite?mesh=7x9v#fp=91A4D2C8'),
        InviteParseErrorCode.missingSession,
      );
    });

    test('rejects missing fingerprint as missing_fingerprint', () {
      expectInviteParseError(
        () => parseMoshInvite('mosh://invite?mesh=7x9v&session=drift-41'),
        InviteParseErrorCode.missingFingerprint,
      );
    });

    test('rejects non-hex fingerprint as invalid_fingerprint', () {
      expectInviteParseError(
        () =>
            parseMoshInvite('mosh://invite?mesh=7x9v&session=drift-41#fp=zzzz'),
        InviteParseErrorCode.invalidFingerprint,
      );
    });
  });

  group('parseMoshGroupInvite', () {
    test('parses a private group invite URI', () {
      expect(
        parseMoshGroupInvite(groupInvite),
        equals(const MoshGroupInvite(
          meshId: 'mesh-one',
          groupId: 'group-one',
          label: 'Friends',
          fingerprint: 'AABBCCDDEEFF00112233445566778899',
        )),
      );
    });

    // Mirrors the TS group `invalidInvites` array via `it.each`. Six cases.
    test('rejects "not a url" as invalid_url', () {
      expectInviteParseError(
        () => parseMoshGroupInvite('not a url'),
        InviteParseErrorCode.invalidUrl,
      );
    });

    test('rejects invite host as invalid_scheme', () {
      expectInviteParseError(
        () => parseMoshGroupInvite(
          'mosh://invite?mesh=mesh-one&group=group-one#fp=AABBCCDDEEFF00112233445566778899',
        ),
        InviteParseErrorCode.invalidScheme,
      );
    });

    test('rejects missing mesh as missing_mesh', () {
      expectInviteParseError(
        () => parseMoshGroupInvite(
          'mosh://group?group=group-one#fp=AABBCCDDEEFF00112233445566778899',
        ),
        InviteParseErrorCode.missingMesh,
      );
    });

    test('rejects missing group as missing_group', () {
      expectInviteParseError(
        () => parseMoshGroupInvite(
          'mosh://group?mesh=mesh-one#fp=AABBCCDDEEFF00112233445566778899',
        ),
        InviteParseErrorCode.missingGroup,
      );
    });

    test('rejects missing fingerprint as missing_fingerprint', () {
      expectInviteParseError(
        () => parseMoshGroupInvite(
          'mosh://group?mesh=mesh-one&group=group-one',
        ),
        InviteParseErrorCode.missingFingerprint,
      );
    });

    test('rejects short fingerprint as invalid_fingerprint', () {
      expectInviteParseError(
        () => parseMoshGroupInvite(
          'mosh://group?mesh=mesh-one&group=group-one#fp=ABCD',
        ),
        InviteParseErrorCode.invalidFingerprint,
      );
    });
  });
}
