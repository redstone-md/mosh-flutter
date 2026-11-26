import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/rust/org_runtime.dart' show OrgSnapshot;
import 'package:mosh/src/state/gateway_provider.dart';
import 'package:mosh/src/state/org_providers.dart';

import '../support/gateway_snapshots.dart';
import '../support/scriptable_bridge.dart';

/// Answers each organization listing when the test says so.
class _HeldOrgs extends ScriptableBridge {
  final listings = <Completer<List<OrgSnapshot>>>[];

  @override
  Future<List<OrgSnapshot>> listOrgs() {
    final listing = Completer<List<OrgSnapshot>>();
    listings.add(listing);
    return listing.future;
  }
}

void main() {
  // Regression (CodeAnt PR #12): an older refresh that finished last put its
  // stale list back.
  test('a refresh that finishes late does not replace a newer list', () async {
    final bridge = _HeldOrgs();
    final container = ProviderContainer(
        overrides: [bridgeFacadeProvider.overrideWithValue(bridge)]);
    addTearDown(container.dispose);
    final built = container.read(orgsProvider.future);
    bridge.listings.single.complete(const []);
    await built;
    final orgs = container.read(orgsProvider.notifier);
    final joined = cannedOrgSnapshot(orgPubkey: 'org-joined');

    final older = orgs.refresh();
    final newer = orgs.refresh();
    bridge.listings[2].complete([joined]);
    await newer;
    bridge.listings[1].complete(const []);
    await older;

    expect(container.read(orgsProvider).value, [joined]);
  });
}
