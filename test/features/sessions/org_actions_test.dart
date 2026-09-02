// Focused coverage for the one envelope the seven org actions run in
// (`org_actions.dart`). Busy state, the refresh, the mounted check, the
// error toast and the navigation all belong to the runner, so a failure
// and a destination have to look the same whichever action ran.
//
// On top of that: the two actions carrying real thought -- the DM-link
// scan in `openMemberDmAction` and the member list in
// `createOrgGroupAction` -- are asserted directly, because they are the
// only things the envelope does not own.
//
// Every call an org action makes is a 1:1 bridge mirror (ADR 0025), so the
// whole test runs on the bridge double.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/sessions/org_actions.dart';
import 'package:mosh/src/routing/app_router.dart' show AppRoutes;
import 'package:mosh/src/rust/api/conversation_bridge.dart'
    show ConversationBridgeError, ConversationBridgeErrorKind;
import 'package:mosh/src/rust/org_runtime.dart'
    show OrgDmLink, OrgMemberView, OrgSnapshot;
import 'package:mosh/src/state/gateway_provider.dart' show bridgeFacadeProvider;
import 'package:mosh/src/state/org_providers.dart' show orgOperationBusProvider;

import '../../support/scriptable_bridge.dart'
    show BridgeCall, BridgeMethod, ScriptableBridge;

const String _kStart = '/start';
const String _kStartLabel = 'start';
const String _kOrgPubkey = 'org-1';
const String _kOfferId = 'offer-1';

const OrgMemberView _kSelf = OrgMemberView(
  mossPeerId: 'peer-self',
  name: 'Me',
  role: 'admin',
  isSelf: true,
);

const OrgMemberView _kPeer = OrgMemberView(
  mossPeerId: 'peer-1',
  name: 'Ann',
  role: 'member',
  isSelf: false,
);

OrgSnapshot _org({
  List<OrgMemberView> members = const [_kSelf, _kPeer],
  List<OrgDmLink> dmLinks = const [],
}) =>
    OrgSnapshot(
      orgPubkey: _kOrgPubkey,
      orgName: 'Night shift',
      meshId: '',
      ownPeerId: _kSelf.mossPeerId,
      confirmationCode: '',
      inRoster: true,
      members: members,
      dmOffers: const [],
      groupOffers: const [],
      dmLinks: dmLinks,
    );

/// The seven org actions, each paired with the Gateway call it makes, so
/// one test can prove the envelope treats all seven alike.
typedef _OrgActionCase = ({
  BridgeMethod method,
  Future<void> Function(BuildContext context, WidgetRef ref) run,
});

List<_OrgActionCase> _allActions() => [
      (
        method: BridgeMethod.leaveOrg,
        run: (c, r) => leaveOrgAction(c, r, _org()),
      ),
      (
        method: BridgeMethod.sendOrgDmOffer,
        run: (c, r) => openMemberDmAction(c, r, _org(), _kPeer),
      ),
      (
        method: BridgeMethod.acceptOrgDmOffer,
        run: (c, r) => acceptOrgDmOfferAction(c, r, _kOrgPubkey, _kOfferId),
      ),
      (
        method: BridgeMethod.dismissOrgDmOffer,
        run: (c, r) => dismissOrgDmOfferAction(c, r, _kOrgPubkey, _kOfferId),
      ),
      (
        method: BridgeMethod.acceptOrgGroupOffer,
        run: (c, r) => acceptOrgGroupOfferAction(c, r, _kOrgPubkey, _kOfferId),
      ),
      (
        method: BridgeMethod.dismissOrgGroupOffer,
        run: (c, r) => dismissOrgGroupOfferAction(c, r, _kOrgPubkey, _kOfferId),
      ),
      (
        method: BridgeMethod.createOrgGroup,
        run: (c, r) => createOrgGroupAction(c, r, _org(), 'Night shift'),
      ),
    ];

/// The two things an org action takes that a test cannot construct by
/// hand: a live [BuildContext] and the [WidgetRef] behind it.
Future<({BuildContext context, WidgetRef ref})> _mount(
  WidgetTester tester,
  ScriptableBridge bridge,
) async {
  late BuildContext capturedContext;
  late WidgetRef capturedRef;
  final router = GoRouter(
    initialLocation: _kStart,
    routes: [
      GoRoute(
        path: _kStart,
        builder: (_, __) => _Capture(
          ready: (context, ref) {
            capturedContext = context;
            capturedRef = ref;
          },
        ),
      ),
      for (final path in [AppRoutes.dm, AppRoutes.group])
        GoRoute(
          path: '$path/:id',
          builder: (_, state) => Text(state.uri.path),
        ),
    ],
  );
  final container = ProviderContainer(
    overrides: [bridgeFacadeProvider.overrideWithValue(bridge)],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (context: capturedContext, ref: capturedRef);
}

/// Renders a marker the tests look for to prove no action navigated, and
/// hands its own [BuildContext] + [WidgetRef] back through [ready].
class _Capture extends ConsumerStatefulWidget {
  const _Capture({required this.ready});

  final void Function(BuildContext context, WidgetRef ref) ready;

  @override
  ConsumerState<_Capture> createState() => _CaptureState();
}

class _CaptureState extends ConsumerState<_Capture> {
  @override
  Widget build(BuildContext context) {
    widget.ready(context, ref);
    return const Scaffold(body: Text(_kStartLabel));
  }
}

void main() {
  testWidgets('the org stays busy for the whole action', (tester) async {
    final bridge = ScriptableBridge()..hold(BridgeMethod.leaveOrg);
    final harness = await _mount(tester, bridge);

    final running = leaveOrgAction(harness.context, harness.ref, _org());
    await tester.pump();
    expect(harness.ref.read(orgOperationBusProvider), contains(_kOrgPubkey));

    bridge.release(BridgeMethod.leaveOrg);
    await running;
    await tester.pumpAndSettle();
    expect(harness.ref.read(orgOperationBusProvider), isEmpty);
  });

  testWidgets('every org action turns a bridge failure into the same snack bar',
      (tester) async {
    for (final testCase in _allActions()) {
      final bridge = ScriptableBridge()
        ..failAlways(testCase.method, error: 'boom');
      final harness = await _mount(tester, bridge);

      await testCase.run(harness.context, harness.ref);
      await tester.pumpAndSettle();

      expect(
        find.text('boom'),
        findsOneWidget,
        reason: 'a failed ${testCase.method.name} must reach a snack bar',
      );
      expect(
        harness.ref.read(orgOperationBusProvider),
        isEmpty,
        reason: 'a failed ${testCase.method.name} must clear the busy flag',
      );
    }
  });

  // The bridge throws the generated ConversationBridgeError (ticket 17); the
  // toast picks its sentence from the kind and never shows the runtime's
  // diagnostic text (ticket 18).
  testWidgets('a bridge failure is worded by its kind in the snack bar',
      (tester) async {
    const error = ConversationBridgeError(
      kind: ConversationBridgeErrorKind.persistence,
      message: 'redb: write failed',
    );
    final bridge = ScriptableBridge()
      ..failAlways(BridgeMethod.leaveOrg, error: error);
    final harness = await _mount(tester, bridge);

    await leaveOrgAction(harness.context, harness.ref, _org());
    await tester.pumpAndSettle();

    final l = AppLocalizations.of(harness.context)!;
    expect(find.text(l.chatActionErrorPersistence), findsOneWidget);
    expect(find.textContaining(error.message), findsNothing);
  });

  testWidgets('the envelope re-reads every rail list after any action',
      (tester) async {
    for (final testCase in _allActions()) {
      final bridge = ScriptableBridge();
      final harness = await _mount(tester, bridge);

      // The dismisses change nothing outside the org -- the refresh is the
      // runner's, not the action's, so it runs for them too.
      await testCase.run(harness.context, harness.ref);
      await tester.pumpAndSettle();

      expect(
        bridge.countOf(BridgeMethod.listOrgs),
        greaterThan(0),
        reason: '${testCase.method.name} must re-read the orgs',
      );
      expect(
        bridge.countOf(BridgeMethod.listSessions),
        greaterThan(0),
        reason: '${testCase.method.name} must re-read the sessions',
      );
      expect(
        bridge.countOf(BridgeMethod.listChannels),
        greaterThan(0),
        reason: '${testCase.method.name} must re-read the channels',
      );
      expect(
        bridge.countOf(BridgeMethod.listGroups),
        greaterThan(0),
        reason: '${testCase.method.name} must re-read the groups',
      );
    }
  });

  testWidgets('leave and both dismisses stay put', (tester) async {
    final bridge = ScriptableBridge();
    final harness = await _mount(tester, bridge);

    await leaveOrgAction(harness.context, harness.ref, _org());
    await dismissOrgDmOfferAction(
        harness.context, harness.ref, _kOrgPubkey, _kOfferId);
    await dismissOrgGroupOfferAction(
        harness.context, harness.ref, _kOrgPubkey, _kOfferId);
    await tester.pumpAndSettle();

    expect(bridge.countOf(BridgeMethod.leaveOrg), 1);
    expect(bridge.countOf(BridgeMethod.dismissOrgDmOffer), 1);
    expect(bridge.countOf(BridgeMethod.dismissOrgGroupOffer), 1);
    expect(find.text(_kStartLabel), findsOneWidget);
  });

  testWidgets('accepting a DM offer lands on the new DM', (tester) async {
    final bridge = ScriptableBridge();
    final harness = await _mount(tester, bridge);

    await acceptOrgDmOfferAction(
        harness.context, harness.ref, _kOrgPubkey, _kOfferId);
    await tester.pumpAndSettle();

    final BridgeCall call = bridge.lastCall(BridgeMethod.acceptOrgDmOffer)!;
    expect(call.arg<String>('offerId'), _kOfferId);
    // The invite settings are the envelope's, not the action's: an unset
    // display name falls back to 'anonymous' here as everywhere else.
    expect(call.arg<String>('displayName'), 'anonymous');
    expect(call.arg<int>('listenPort'), 8765);
    expect(find.text('/dm/fake-org-accept-1'), findsOneWidget);
  });

  testWidgets('accepting a group offer lands on the group', (tester) async {
    final bridge = ScriptableBridge();
    final harness = await _mount(tester, bridge);

    await acceptOrgGroupOfferAction(
        harness.context, harness.ref, _kOrgPubkey, _kOfferId);
    await tester.pumpAndSettle();

    expect(bridge.countOf(BridgeMethod.acceptOrgGroupOffer), 1);
    expect(find.text('/group/fake-org-group-accept'), findsOneWidget);
  });

  testWidgets('a member with a linked DM jumps to it without an offer',
      (tester) async {
    final bridge = ScriptableBridge();
    final harness = await _mount(tester, bridge);
    // A link with no session id at all, and one with an empty id, are both
    // offers in flight -- only the third is a conversation to open.
    final org = _org(dmLinks: const [
      OrgDmLink(peerId: 'peer-1'),
      OrgDmLink(peerId: 'peer-1', sessionId: ''),
      OrgDmLink(peerId: 'peer-1', sessionId: 'dm-9'),
    ]);

    await openMemberDmAction(harness.context, harness.ref, org, _kPeer);
    await tester.pumpAndSettle();

    expect(bridge.countOf(BridgeMethod.sendOrgDmOffer), 0);
    expect(find.text('/dm/dm-9'), findsOneWidget);
  });

  testWidgets('a jump re-reads nothing', (tester) async {
    final bridge = ScriptableBridge();
    final harness = await _mount(tester, bridge);
    final org = _org(dmLinks: const [
      OrgDmLink(peerId: 'peer-1', sessionId: 'dm-9'),
    ]);

    await openMemberDmAction(harness.context, harness.ref, org, _kPeer);
    await tester.pumpAndSettle();

    // Nothing changed, so nothing is re-read -- and a failing re-read
    // cannot stand between the tap and the conversation.
    expect(bridge.countOf(BridgeMethod.listOrgs), 0);
    expect(bridge.countOf(BridgeMethod.listSessions), 0);
    expect(bridge.countOf(BridgeMethod.listChannels), 0);
    expect(bridge.countOf(BridgeMethod.listGroups), 0);
    expect(find.text('/dm/dm-9'), findsOneWidget);
  });

  testWidgets('a member without a linked DM gets an offer', (tester) async {
    final bridge = ScriptableBridge();
    final harness = await _mount(tester, bridge);

    await openMemberDmAction(harness.context, harness.ref, _org(), _kPeer);
    await tester.pumpAndSettle();

    expect(bridge.countOf(BridgeMethod.sendOrgDmOffer), 1);
    expect(
      bridge.lastCall(BridgeMethod.sendOrgDmOffer)!.arg<String>(
            'targetPeerId',
          ),
      'peer-1',
    );
    expect(find.text('/dm/fake-org-dm-1'), findsOneWidget);
  });

  testWidgets('tapping yourself does nothing', (tester) async {
    final bridge = ScriptableBridge();
    final harness = await _mount(tester, bridge);

    await openMemberDmAction(harness.context, harness.ref, _org(), _kSelf);
    await tester.pumpAndSettle();

    expect(bridge.calls, isEmpty);
    expect(harness.ref.read(orgOperationBusProvider), isEmpty);
    expect(find.text(_kStartLabel), findsOneWidget);
  });

  testWidgets('creating a group offers it to every non-self member',
      (tester) async {
    final bridge = ScriptableBridge();
    final harness = await _mount(tester, bridge);
    final org = _org(members: const [
      _kSelf,
      _kPeer,
      OrgMemberView(
        mossPeerId: 'peer-2',
        name: 'Bob',
        role: 'member',
        isSelf: false,
      ),
    ]);

    await createOrgGroupAction(
        harness.context, harness.ref, org, '  Night shift  ');
    await tester.pumpAndSettle();

    final BridgeCall call = bridge.lastCall(BridgeMethod.createOrgGroup)!;
    expect(call.arg<String>('label'), 'Night shift');
    expect(call.arg<List<String>>('memberPeerIds'), ['peer-1', 'peer-2']);
    expect(find.text('/group/fake-org-group-1'), findsOneWidget);
  });

  testWidgets('a blank group label is dropped', (tester) async {
    final bridge = ScriptableBridge();
    final harness = await _mount(tester, bridge);

    await createOrgGroupAction(harness.context, harness.ref, _org(), '   ');
    await tester.pumpAndSettle();

    expect(
      bridge.lastCall(BridgeMethod.createOrgGroup)!.arg<String?>('label'),
      isNull,
    );
  });
}
