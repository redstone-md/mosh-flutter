// Parity tests for `computeRevokedDmBadges`
// (lib/src/features/sessions/revoked_dm_badges.dart) -- the 1-в-1 Dart port of
// React's `computeRevokedDmBadges`
// (mosh/src/features/private-dm/org/use-orgs.ts L228-253, test cases in
// org-ui.test.tsx L178-207). Mirrors the React test shape 1-в-1: no-roster
// (rosterVersion == null -> empty map), still-member link (not badged),
// revoked-member link (badged with org name), plus a mixed-orgs case and a
// null-sessionId link (skipped). Fixtures use the real OrgSnapshot /
// OrgDmLink / OrgMemberView constructors.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/src/features/sessions/revoked_dm_badges.dart';
import 'package:mosh/src/rust/org_runtime.dart';

/// Minimal org fixture -- mirrors React `orgSnapshot` defaults (own peer in
/// the roster, a verified roster_version) with overridable roster, members,
/// and dm links. OrgDmLink/OrgMemberView built from the real constructors.
OrgSnapshot _org({
  required String name,
  BigInt? rosterVersion,
  List<OrgMemberView> members = const [],
  List<OrgDmLink> dmLinks = const [],
}) =>
    OrgSnapshot(
      orgPubkey: 'pk-$name',
      orgName: name,
      meshId: 'm',
      ownPeerId: 'me',
      confirmationCode: 'CODE-$name',
      inRoster: true,
      rosterVersion: rosterVersion,
      members: members,
      dmOffers: const [],
      groupOffers: const [],
      dmLinks: dmLinks,
    );

/// Verified roster version for the "still a member" / "left the roster"
/// cases -- BigInt.one is not a const constructor, so it is passed in at
/// each call site rather than used as a default param value.
final BigInt _verified = BigInt.from(1);

OrgMemberView _member(String peerId, {String name = 'x'}) => OrgMemberView(
      mossPeerId: peerId,
      name: name,
      role: 'member',
      isSelf: false,
    );

OrgDmLink _link(String peerId, {String? sessionId}) =>
    OrgDmLink(peerId: peerId, sessionId: sessionId);

void main() {
  group('computeRevokedDmBadges', () {
    test('badges linked sessions whose peer left the roster and only those',
        () {
      // 1-в-1 with React org-ui.test.tsx "badges linked sessions whose peer
      // left the roster and only those": bob is still a member (not badged),
      // carol left (badged), dave's link has no session id (skipped).
     final org = _org(
       name: 'acme',
        rosterVersion: _verified,
       members: [_member('b' * 64, name: 'bob')],
       dmLinks: [
         _link('b' * 64, sessionId: 'dm-bob'),
         _link('c' * 64, sessionId: 'dm-carol'),
         _link('d' * 64, sessionId: null),
       ],
     );
     final badges = computeRevokedDmBadges([org]);
     expect(badges['dm-carol'], 'acme');
     expect(badges.containsKey('dm-bob'), isFalse);
     expect(badges.length, 1);
   });

   test('never badges when no roster has been verified yet', () {
     // 1-в-1 with React "never badges when no roster has been verified yet":
     // rosterVersion == null -- absence of a member proves nothing.
     final org = _org(
       name: 'acme',
       rosterVersion: null,
       members: const [],
       dmLinks: [_link('c' * 64, sessionId: 'dm-carol')],
     );
     expect(computeRevokedDmBadges([org]).length, 0);
   });

   test('mixed orgs: only the revoked-member org is badged', () {
     // Two orgs -- one with a still-member link, one with a revoked-member
     // link. Only the revoked one's session is badged (with its own name).
     final stillOrg = _org(
       name: 'still-co',
        rosterVersion: _verified,
       members: [_member('b' * 64, name: 'bob')],
       dmLinks: [_link('b' * 64, sessionId: 'dm-bob')],
     );
     final revokedOrg = _org(
       name: 'gone-co',
        rosterVersion: _verified,
       members: const [],
       dmLinks: [_link('z' * 64, sessionId: 'dm-zoe')],
     );
     final badges = computeRevokedDmBadges([stillOrg, revokedOrg]);
     expect(badges.length, 1);
     expect(badges['dm-zoe'], 'gone-co');
     expect(badges.containsKey('dm-bob'), isFalse);
   });

   test('skips dm links without a session id', () {
     // A link whose sessionId is null is skipped entirely (never badged),
     // even when its peer is not in the verified roster.
     final org = _org(
       name: 'acme',
        rosterVersion: _verified,
       members: const [],
       dmLinks: [_link('c' * 64, sessionId: null)],
     );
     expect(computeRevokedDmBadges([org]).length, 0);
   });
  });
}
