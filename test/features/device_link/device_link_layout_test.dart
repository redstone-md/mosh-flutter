import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/app/mosh_theme.dart';
import 'package:mosh/src/features/device_link/device_link_flow.dart';
import 'package:mosh/src/features/device_link/device_link_import_form.dart';
import 'package:mosh/src/features/device_link/device_link_qr.dart';
import 'package:mosh/src/features/device_link/device_link_start_actions.dart';
import 'package:mosh/src/features/device_link/device_list.dart';
import 'package:mosh/src/rust/device_link/types.dart';

import '../../support/pump.dart';
import '../../support/device_link_fixture.dart';

const _own = DeviceDescriptor(
    deviceId: 'aaaaaaaa',
    signingPublicKey: 'key',
    mossPeerId: 'peer',
    name: 'A very long computer name that should wrap on a small phone');
const _other = DeviceDescriptor(
    deviceId: 'bbbbbbbb',
    signingPublicKey: 'other-key',
    mossPeerId: 'other-peer',
    name: 'Another desktop');

DeviceLinkSnapshot _snapshot(DeviceLinkPhase phase) => DeviceLinkSnapshot(
      userId: 'a' * 64,
      ownDeviceId: _own.deviceId,
      devices: const [_own, _other],
      phase: phase,
      canJoin: false,
      revoked: false,
      revocations: const [],
      qrUri: phase == DeviceLinkPhase.showingQr ? deviceLinkQrFixture() : null,
      confirmationCode:
          phase == DeviceLinkPhase.awaitingConfirmation ? '1234ABCD5678' : null,
      pendingDevice: phase == DeviceLinkPhase.showingQr ? null : _other,
    );

Future<void> _pump(WidgetTester tester, Widget child) => pumpScreen(
      tester,
      Theme(
        data: buildMoshTheme(),
        child: Scaffold(
          body: SingleChildScrollView(
            child: Padding(padding: const EdgeInsets.all(16), child: child),
          ),
        ),
      ),
      settle: false,
    );

void main() {
  testWidgets(
      'the two roles are explicit; used devices cannot join another user',
      (tester) async {
    var action = '';
    await _pump(
        tester,
        DeviceLinkStartActions(
          canJoin: true,
          revoked: false,
          onAuthorize: () => action = 'authorize',
          onJoin: () => action = 'join',
        ));
    await tester.tap(find.text('Create linking QR'));
    expect(action, 'authorize');
    await tester
        .tap(find.widgetWithText(OutlinedButton, 'Connect this device'));
    expect(action, 'join');
    await _pump(
        tester,
        DeviceLinkStartActions(
          canJoin: false,
          revoked: false,
          onAuthorize: () {},
          onJoin: () {},
        ));
    expect(tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
        isNull);
    expect(find.textContaining('already has chats'), findsOneWidget);
    await _pump(
        tester,
        DeviceLinkStartActions(
          canJoin: true,
          revoked: true,
          onAuthorize: () {},
          onJoin: () {},
        ));
    expect(find.text('Create linking QR'), findsNothing);
    expect(find.text('Request access again'), findsOneWidget);
    expect(
        find.textContaining('Received messages remain here'), findsOneWidget);
  });

  testWidgets(
      'joining has camera, image and link alternatives; busy disables actions',
      (tester) async {
    var input = '';
    var camera = false;
    var image = false;
    await _pump(
        tester,
        DeviceLinkImportForm(
          busy: false,
          onSubmit: (uri) => input = uri,
          onImage: () => image = true,
          onScan: () => camera = true,
        ));
    await tester.tap(find.text('Scan QR with camera'));
    await tester.tap(find.text('Choose QR image'));
    expect(camera, isTrue);
    expect(image, isTrue);
    await tester.enterText(
        find.byType(TextField), '  mosh://device-link/test  ');
    await tester.tap(find.byTooltip('Connect'));
    expect(input, 'mosh://device-link/test');
    await tester.testTextInput.receiveAction(TextInputAction.go);
    expect(input.trim(), 'mosh://device-link/test');
    await _pump(
        tester,
        DeviceLinkImportForm(
          busy: true,
          onSubmit: (_) {},
          onImage: () {},
        ));
    expect(find.text('Scan QR with camera'), findsNothing);
    expect(tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
        isNull);
    expect(
        tester.widget<IconButton>(find.byType(IconButton)).onPressed, isNull);
  });

  testWidgets('trusted device asks for the code; delivery cannot be cancelled',
      (tester) async {
    var approved = '';
    var cancelled = false;
    await _pump(
        tester,
        DeviceLinkFlow(
          snapshot: _snapshot(DeviceLinkPhase.awaitingApproval),
          role: DeviceLinkRole.authorizing,
          busy: false,
          onApprove: (code) => approved = code,
          onCancel: () => cancelled = true,
        ));
    await tester.enterText(find.byType(TextField), '1234ABCD5678');
    await tester.tap(find.text('Approve device'));
    expect(approved, '1234ABCD5678');
    await tester.tap(find.text('Cancel link'));
    expect(cancelled, isTrue);
    await _pump(
        tester,
        DeviceLinkFlow(
          snapshot: _snapshot(DeviceLinkPhase.delivering),
          role: DeviceLinkRole.authorizing,
          busy: false,
          onApprove: (_) {},
          onCancel: () {},
        ));
    expect(find.text('Cancel link'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.textContaining('Approval saved.'), findsOneWidget);
  });

  for (final width in [320.0, 800.0]) {
    for (final phase in [
      DeviceLinkPhase.showingQr,
      DeviceLinkPhase.awaitingConfirmation,
      DeviceLinkPhase.delivering
    ]) {
      testWidgets('$phase fits width $width with larger text', (tester) async {
        tester.view.physicalSize = Size(width, 850);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final s = _snapshot(phase);
        await _pump(
            tester,
            MediaQuery(
              data: MediaQueryData(
                  size: Size(width, 850),
                  textScaler: const TextScaler.linear(1.5)),
              child: Column(children: [
                LinkedDeviceList(snapshot: s, onRemove: (_) {}),
                const SizedBox(height: 16),
                DeviceLinkFlow(
                  snapshot: s,
                  role: phase == DeviceLinkPhase.awaitingConfirmation
                      ? DeviceLinkRole.joining
                      : DeviceLinkRole.authorizing,
                  busy: false,
                  onApprove: (_) {},
                  onCancel: () {},
                ),
              ]),
            ));
        expect(tester.takeException(), isNull);
        expect(find.text('This device'), findsOneWidget);
        expect(
            find.text('1234ABCD5678'),
            phase == DeviceLinkPhase.awaitingConfirmation
                ? findsOneWidget
                : findsNothing);
        expect(find.byType(DeviceLinkQr),
            phase == DeviceLinkPhase.showingQr ? findsOneWidget : findsNothing);
      });
    }
  }
}
