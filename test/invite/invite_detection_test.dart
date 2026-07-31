import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/invite/invite_detection.dart';

const dmInvite = 'mosh://invite?mesh=7x9v&session=drift-41#fp=91A4-D2C8-77B0';
const groupInvite =
    'mosh://group?mesh=mesh-one&group=group-one#fp=AABBCCDDEEFF00112233445566778899';

void main() {
  group('detectInvite', () {
    test('detects supported invite kinds', () {
      expect(detectInvite(dmInvite),
          const InviteDetection(kind: InviteDetectionKind.dm));
      expect(detectInvite(groupInvite),
          const InviteDetection(kind: InviteDetectionKind.group));
    });

    test('returns a specific missing mesh message', () {
      final result = detectInvite('mosh://invite?bad=1');
      expect(result.kind, InviteDetectionKind.unknown);
      expect(result.errorCode, InviteParseErrorCode.missingMesh);
      expect(result.errorMessage, 'Invite link is missing mesh=...');
    });

    test('returns a group-specific fingerprint message', () {
      final result = detectInvite(
          'mosh://group?mesh=mesh-one&group=group-one#fp=ABCD');
      expect(result.kind, InviteDetectionKind.unknown);
      expect(result.errorCode, InviteParseErrorCode.invalidFingerprint);
      expect(result.errorMessage, 'Group fingerprint must be 32 hex characters.');
    });
  });
}
