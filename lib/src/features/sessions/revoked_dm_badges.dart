// Pure helper + Riverpod provider for the "no longer in <org>" DM badge in
// the sessions list -- the 1-в-1 port of React's `computeRevokedDmBadges`
// (mosh/src/features/private-dm/org/use-orgs.ts L228-253) consumed by the
// React `SessionRail` subtitle branch (SessionRail.tsx L36-38).
//
// Given the polled joined-orgs list, returns a map of session-id -> org-name
// for every org-bound DM whose linked peer is NO LONGER in that org's
// verified roster. The React rail swaps the session's state subtitle for
// `${orgText.revokedBadge} ${orgName}` when this map has the session id.
//
// Safety rule (mirrors React): an org whose roster has not yet been verified
// (`rosterVersion == null` -- fresh join, restart before first gossip) is
// skipped entirely. Absence of a member proves nothing in that state, so we
// never badge against an unverified roster.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mosh/src/rust/org_runtime.dart' show OrgSnapshot;
import 'package:mosh/src/state/org_providers.dart' show orgsProvider;

/// Compute session-id -> org-name badges for org-bound DMs whose peer left
/// the org's roster. Pure; 1-в-1 with React `computeRevokedDmBadges`.
Map<String, String> computeRevokedDmBadges(List<OrgSnapshot> orgs) {
  final badges = <String, String>{};
  for (final org in orgs) {
    // No verified roster (fresh join, restart before first gossip): absence
    // of a member proves nothing -- never badge.
    if (org.rosterVersion == null) {
      continue;
    }
    for (final link in org.dmLinks) {
      if (link.sessionId == null) {
        continue;
      }
      final stillMember =
          org.members.any((m) => m.mossPeerId == link.peerId);
      if (!stillMember) {
        badges[link.sessionId!] = org.orgName;
      }
    }
  }
  return badges;
}

/// Server-derived map of revoked-org DM badges for the sessions rail. Watches
/// `orgsProvider`; degrades to an empty map while loading or on error so the
/// badge simply stays absent during a refresh (mirrors React clearing to 0).
final revokedDmBadgesProvider = Provider<Map<String, String>>((ref) {
  final orgs = ref.watch(orgsProvider).value ?? const <OrgSnapshot>[];
  return computeRevokedDmBadges(orgs);
});
