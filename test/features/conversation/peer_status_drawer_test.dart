// Widget tests for `PeerStatusDrawer` (lib/src/features/conversation/
// peer_status_drawer.dart). The drawer is a `Positioned.fill` overlay (NOT a
// `showDialog` route), so unlike the call modals it owns its own focus + Esc
// handling. These tests assert:
//   - Esc calls `onClose`.
//   - Opened from the keyboard, it takes focus, keeps Tab inside, hides
//     the background from screen readers, and hands focus back on close.
//   - The header title + the NoActiveSession fallback render when no
//     conversation is active (idle branch).
//   - The session branch renders the SessionDiagnostics section content.
//   - Backdrop tap still closes (existing behavior preserved).
//   - The refresh button is disabled while refreshing.
//
// The pump host is a `MaterialApp` + `Stack` + `Positioned.fill` so the
// overlay resolves exactly as the host screens (dm_screen_body /
// channel_screen_body / group_screen_body) mount it -- matching the
// established DM widget-test pattern (localized `MaterialApp`, no
// Riverpod/gateway seam).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/src/features/conversation/peer_status_drawer.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import 'package:mosh/src/rust/private_dm_runtime/transport.dart';
import '../../support/pump.dart';

/// A minimal `SessionSnapshot` builder, mirroring the one in
/// `diagnostics_sections_test.dart`. Only the fields the drawer's session
/// branch reads are parameterized; the rest are the frb-required defaults
/// (empty lists, null optionals).
SessionSnapshot _session({
  String sessionId = 'sess-1',
  String peerDisplayName = 'alice',
  String displayName = 'me',
  DmSessionState state = DmSessionState.connected,
  PeerTransport transport = PeerTransport.relayed,
  String role = 'initiator',
}) =>
    SessionSnapshot(
      inviteAvailable: false,
      sessionId: sessionId,
      meshId: 'mesh-1',
      role: role,
      displayName: displayName,
      peerDisplayName: peerDisplayName,
      state: state,
      transport: transport,
      inviteUri: null,
      fingerprint: 'AABB',
      messages: const [],
      attachments: const [],
      mesh: null,
      events: const [],
      pendingCall: null,
      outgoingCall: null,
      activeCall: null,
    );

/// Pumps the drawer exactly as the host screens do: a `Stack` with the
/// drawer in a `Positioned.fill` over a placeholder body. The `Stack` is
/// required because `PeerStatusDrawer` is a `Positioned.fill` overlay (a
/// bare child of a `Stack`), not a `showDialog` route -- pumping it
/// directly under `MaterialApp.home` would not resolve the `Positioned`.
Future<void> _pump(WidgetTester tester, Widget child) => pumpScreen(
    tester,
    Scaffold(
      body: Stack(
        children: [
          const SizedBox.expand(),
          Positioned.fill(child: child),
        ],
      ),
    ));

void main() {
  testWidgets('Esc calls onClose', (tester) async {
    var closeCount = 0;
    await _pump(
      tester,
      PeerStatusDrawer(
        error: null,
        refreshing: false,
        onRefresh: () {},
        onClose: () => closeCount++,
      ),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    expect(closeCount, 1);
  });

  testWidgets('backdrop tap still closes (existing behavior preserved)',
      (tester) async {
    var closeCount = 0;
    await _pump(
      tester,
      PeerStatusDrawer(
        error: null,
        refreshing: false,
        onRefresh: () {},
        onClose: () => closeCount++,
      ),
    );
    // Tap the translucent backdrop (left of the 384px panel).
    await tester.tapAt(const Offset(10, 10));
    expect(closeCount, 1);
  });

  testWidgets('renders the header title + NoActiveSession fallback',
      (tester) async {
    await _pump(
      tester,
      PeerStatusDrawer(
        error: null,
        refreshing: false,
        onRefresh: () {},
        onClose: () {},
      ),
    );
    // Header h2 (peerStatusTitle).
    // `.diagnostics-drawer > header h2` is uppercased by CSS; the
    // accessible name stays natural-case.
    expect(find.text('CONNECTION STATUS'), findsOneWidget);
    // NoActiveSession fallback: `diagNoActiveTitle` is "No active session".
    // It renders twice -- once as the `Session` group label and once as
    // the empty-state title (mirrors `diagnostics_sections_test.dart`'s
    // NoActiveSession assertions, which also find both).
    expect(find.text('No active session'), findsNWidgets(2));
  });

  testWidgets('session branch renders the SessionDiagnostics section',
      (tester) async {
    await _pump(
      tester,
      PeerStatusDrawer(
        session: _session(peerDisplayName: 'alice'),
        error: null,
        refreshing: false,
        onRefresh: () {},
        onClose: () {},
      ),
    );
    // Header is always present.
    // `.diagnostics-drawer > header h2` is uppercased by CSS; the
    // accessible name stays natural-case.
    expect(find.text('CONNECTION STATUS'), findsOneWidget);
    // SessionDiagnostics renders the peer display name in its Peer row
    // (diagnostics_sections_test asserts the same value for this branch).
    expect(find.text('alice'), findsWidgets);
    // The idle fallback must NOT render when a session is active.
    expect(find.text('No active session'), findsNothing);
  });

  testWidgets('refresh button is disabled while refreshing', (tester) async {
    var refreshCount = 0;
    await _pump(
      tester,
      PeerStatusDrawer(
        error: null,
        refreshing: true,
        onRefresh: () => refreshCount++,
        onClose: () {},
      ),
    );
    // While refreshing the IconButton is disabled (onPressed == null), so a
    // tap does not fire onRefresh.
    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pump();
    expect(refreshCount, 0);
  });

  group('opened from the keyboard', () {
    Future<void> openFromKeyboard(WidgetTester tester) async {
      await pumpScreen(tester, const _Host());
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(_hasFocus(tester, 'Open'), isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.byType(PeerStatusDrawer), findsOneWidget);
    }

    testWidgets('Escape closes it and focus returns to the trigger',
        (tester) async {
      await openFromKeyboard(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.byType(PeerStatusDrawer), findsNothing);
      expect(_hasFocus(tester, 'Open'), isTrue);
    });

    testWidgets('Tab cycles through the drawer controls only', (tester) async {
      await openFromKeyboard(tester);

      for (var i = 0; i < 6; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        final focused = FocusManager.instance.primaryFocus!.context!;
        expect(focused.findAncestorWidgetOfExactType<PeerStatusDrawer>(),
            isNotNull,
            reason: 'Tab #${i + 1} left the drawer');
      }
    });

    testWidgets('the screen behind is hidden from screen readers',
        (tester) async {
      final handle = tester.ensureSemantics();
      await openFromKeyboard(tester);

      expect(find.semantics.byLabel('Behind'), findsNothing);
      handle.dispose();
    });
  });
}

bool _hasFocus(WidgetTester tester, String buttonText) =>
    Focus.of(tester.element(find.text(buttonText))).hasPrimaryFocus;

/// A screen with a trigger and one more control, and the drawer over both
/// while open -- the way the conversation screens and the shell host it.
class _Host extends StatefulWidget {
  const _Host();

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  bool _open = false;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Stack(
          fit: StackFit.expand,
          children: [
            Column(
              children: [
                TextButton(
                  onPressed: () => setState(() => _open = true),
                  child: const Text('Open'),
                ),
                TextButton(onPressed: () {}, child: const Text('Behind')),
              ],
            ),
            if (_open)
              Positioned.fill(
                child: PeerStatusDrawer(
                  error: null,
                  refreshing: false,
                  onRefresh: () {},
                  onClose: () => setState(() => _open = false),
                ),
              ),
          ],
        ),
      );
}
