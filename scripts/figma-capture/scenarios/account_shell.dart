// Shared mounting for the account area: the real MoshApp shell with
// fictional chats, opened on Settings or a chat.
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/onboarding/first_run_profile.dart';
import 'package:mosh/src/features/onboarding/first_run_provider.dart';
import 'package:mosh/src/routing/app_router.dart';
import 'package:mosh/src/rust/api/diagnostics.dart' show NativeRuntimeStatus;
import 'package:mosh/src/rust/outbound_delivery.dart';
import 'package:mosh/src/rust/persistence.dart' show PersistenceRuntimeStatus;

import '../../../test/features/routing/shell_harness.dart';
import '../../../test/support/first_run.dart';
import '../../../test/support/gateway_snapshots.dart';
import '../../../test/support/message_builders.dart';
import '../../../test/support/scriptable_bridge.dart';
import '../../../test/support/scriptable_gateway.dart';
import '../../../test/support/settings.dart';
import 'harness.dart';

final _time = DateTime(2026, 11, 20, 18, 12);

/// Two ordinary DMs so the shell behind settings and overlays is not empty.
ScriptableGateway accountGateway() => ScriptableGateway()
  ..seedSessions([
    TestSnapshots.dm(
        sessionId: 'maya',
        displayName: 'Alex',
        peerDisplayName: 'Maya Chen',
        messages: [
          for (final (i, (mine, body)) in [
            (false, 'Did the new laptop pick up our chats?'),
            (true, 'Linking it now, the QR flow is quick.'),
            (false, 'Nice. See you at the studio tomorrow!'),
          ].indexed)
            TestMessages.dm(
                fromDevice: mine ? 'Alex' : 'Maya Chen',
                body: body,
                messageId: 'm$i',
                sentAtMs: BigInt.from(
                    _time.add(Duration(minutes: i)).millisecondsSinceEpoch),
                deliveryStatus: MessageDeliveryStatus.sent,
                read: mine),
        ]),
    TestSnapshots.dm(
        sessionId: 'leo',
        displayName: 'Alex',
        peerDisplayName: 'Leo Park',
        messages: [
          TestMessages.dm(
              fromDevice: 'Leo Park',
              body: 'Sending the slides tonight.',
              messageId: 'l0',
              sentAtMs: BigInt.from(_time
                  .subtract(const Duration(hours: 3))
                  .millisecondsSinceEpoch),
              deliveryStatus: MessageDeliveryStatus.sent),
        ]),
  ]);

/// The canned runtime with history persistence running, as in a real
/// install, so no "history is not being saved" banner appears.
NativeRuntimeStatus _savingHistory() {
  final canned = cannedNativeRuntimeStatus();
  return NativeRuntimeStatus(
      moss: canned.moss,
      secureStorage: canned.secureStorage,
      persistence: const PersistenceRuntimeStatus(
          backend: 'redb+aes-256-gcm+os-keychain',
          database: 'mosh.redb',
          available: true,
          encryptedAtRest: true),
      openmlsSmoke: canned.openmlsSmoke,
      openmlsRoundtrip: canned.openmlsRoundtrip);
}

/// MoshApp at [location] with the account defaults (English, a saved
/// profile, settings hardware seams) plus [overrides].
Future<void> pumpAccountApp(WidgetTester tester, Size size,
    {String location = AppRoutes.sessions,
    List<Override> overrides = const [],
    ScriptableBridge Function(ScriptableGateway gateway)? bridge}) async {
  final gateway = accountGateway();
  await pumpShellApp(tester,
      gateway: gateway,
      bridge: (bridge?.call(gateway) ??
          ScriptableBridge(conversations: gateway.conversations))
        ..seedNativeRuntimeStatus(_savingHistory()),
      physical: size,
      location: location,
      overrides: [
        ...figmaLocale,
        ...settingsCameraOverrides(),
        firstRunStoreProvider.overrideWithValue(MemoryFirstRunStore(
            const FirstRunProfile(
                displayName: 'Alex Rivera', completed: true))),
        ...overrides,
      ]);
}

/// Opens Settings and selects [section] (the nav label). Narrow windows start
/// at the section list, so the tap is needed on both form factors. With
/// [settle] false only fixed frames pass, for sections showing a spinner.
Future<void> openSettingsSection(WidgetTester tester, Size size, String section,
    {List<Override> overrides = const [], bool settle = true}) async {
  await pumpAccountApp(tester, size,
      location: AppRoutes.settings, overrides: overrides);
  await tester.tap(find.text(section).first);
  settle ? await tester.pumpAndSettle() : await frames(tester);
}

/// Fixed frames instead of settling, for screens with an indeterminate
/// progress indicator.
Future<void> frames(WidgetTester tester, [int count = 8]) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}
