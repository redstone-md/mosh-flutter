// S2-3: intake test for the `mosh://` deep-link -> /join wiring.
//
// The intake subscribes to a Stream<Uri> and, for each `mosh://` URI,
// navigates appRouter to /join with the raw URI string as `extra`; the /join
// route builder forwards `extra` to InvitePasteScreen.initialInviteUri, so
// the field arrives pre-pasted and live detection runs on it.
//
// Under `flutter test` there is no Windows app_links plugin, so we exercise
// the intake through its single test seam: startMoshDeepLinkIntake accepts an
// optional `linkStream`. We inject a StreamController<Uri> and push URIs
// through it, then assert the app (pumped via MoshApp, which owns appRouter)
// navigates to /join with the field pre-filled.
//
// Three cases:
//   1. warm link: URI arrives AFTER the first frame (router ready) -> direct
//      appRouter.go(/join); the field is pre-pasted and the detection badge
//      reads "Private chat invite detected".
//   2. scheme gate: a non-`mosh` URI is ignored; the app stays on /.
//   3. cold-start replay: a `mosh://` URI arrives BEFORE the first frame
//      (router not ready) -> it is buffered and replayed on the first frame;
//      after pumping, the app is on /join with the field pre-filled.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mosh/main.dart';
import 'package:mosh/src/routing/app_router.dart';
import 'package:mosh/src/deeplink/mosh_deep_link.dart';

const _inviteUri = 'mosh://invite?mesh=7x9v&session=drift-41#fp=91A4-D2C8-77B0';

void main() {
  // Pump MoshApp (which mounts appRouter) inside a ProviderScope, matching
  // the production widget tree. appRouter is a process-global GoRouter, so a
  // go() issued by the intake shows up on the next pump of MoshApp.
  Future<ProviderContainer> pumpApp(WidgetTester tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MoshApp(),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  setUp(() {
    // The intake's router-ready flag and pending-URI buffer are process-global
    // (intentionally: the cold-start replay must survive across the gap
    // between startMoshDeepLinkIntake() and the first frame). Reset them so
    // each test starts from a known state.
    resetMoshDeepLinkIntakeStateForTest();
    // appRouter is also process-global: a go(/join) issued in one test would
    // leave the next test's fresh MoshApp on /join. Reset to the home route
    // before each test pumps the app.
    appRouter.go('/');
  });

  testWidgets(
      'warm mosh:// link navigates to /join with the field pre-filled',
      (tester) async {
    final controller = StreamController<Uri>();
    addTearDown(controller.close);
    final intake = startMoshDeepLinkIntake(linkStream: controller.stream);
    addTearDown(intake.dispose);

    await pumpApp(tester);
    // Sanity: we start on the onboarding home.
    expect(find.text('Start a conversation'), findsOneWidget);

    // Warm link: emit AFTER the first frame, so the router is ready and the
    // intake calls appRouter.go(/join) directly from the listener.
    controller.add(Uri.parse(_inviteUri));
    await tester.pumpAndSettle();

    // We are now on /join: its AppBar title is "Join with a link".
    expect(find.text('Join with a link'), findsOneWidget);

    // The field is pre-pasted with the deep-link URI and live detection has
    // run on it, so the badge reads the dm-detected message.
    expect(find.text(_inviteUri), findsOneWidget);
    expect(find.text('Private chat invite detected'), findsOneWidget);
  });

  testWidgets('non-mosh scheme is ignored (ADR 0015 single scheme)',
      (tester) async {
    final controller = StreamController<Uri>();
    addTearDown(controller.close);
    final intake = startMoshDeepLinkIntake(linkStream: controller.stream);
    addTearDown(intake.dispose);

    await pumpApp(tester);
    expect(find.text('Start a conversation'), findsOneWidget);

    // A stray https link must NOT navigate.
    controller.add(Uri.parse('https://example.com/invite'));
    await tester.pumpAndSettle();
    expect(find.text('Start a conversation'), findsOneWidget);
    // We must still be on home, not /join. 'Join with a link' appears on BOTH
    // screens (onboarding tile title AND /join AppBar title), so it is a poor
    // discriminator. The /join empty-field badge 'Waiting for a mosh://
    // link...' is unique to /join; it must NOT be present.
    expect(find.text('Waiting for a mosh:// link…'), findsNothing);
  });

  testWidgets('cold-start mosh:// link is replayed on the first frame',
      (tester) async {
    final controller = StreamController<Uri>();
    addTearDown(controller.close);
    final intake = startMoshDeepLinkIntake(linkStream: controller.stream);
    addTearDown(intake.dispose);

    // Emit the cold-start link BEFORE pumping the app: the router is not yet
    // mounted (_routerReady == false), so the intake buffers it in the
    // pending-URI slot. (The post-frame callback that flips _routerReady is
    // registered on this same intake, but only fires once a frame is pumped.)
    controller.add(Uri.parse(_inviteUri));

    // Pump the app: the first frame runs the post-frame callback, which flips
    // _routerReady and replays the buffered URI via appRouter.go(/join).
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MoshApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Join with a link'), findsOneWidget);
    expect(find.text(_inviteUri), findsOneWidget);
    expect(find.text('Private chat invite detected'), findsOneWidget);
  });
}
