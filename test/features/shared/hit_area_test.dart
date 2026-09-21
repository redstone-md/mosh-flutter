// Primary controls carry a >= 40px tap area while their painted visuals
// stay unchanged (audit 2026-09-21, hit-areas finding).
//
// Per control:
//  - composer send button: the painted 32px square keeps its size; the
//    theme's M3 padded tap target makes the button's own layout box the
//    >= 40px target (pinned here so no wrapper ever re-introduces a layout
//    cost beside the input);
//  - paperclip picker: the compact density shrank its hit box to 32px; the
//    LAYOUT box must be >= 40 (IconButton's hit area IS its layout box);
//  - fingerprint lock: a 15px glyph with a left-only inset was a ~19x15 tap
//    target; the padded InkWell must reach >= 40 and catch taps 16px right
//    of center;
//  - confirm-dialog close X and the org offer dismiss X: same >= 40 layout
//    contract.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/conversation/conversation_composer.dart';
import 'package:mosh/src/features/fingerprint/fingerprint_lock.dart';
import 'package:mosh/src/features/org/org_section.dart';
import 'package:mosh/src/features/shared/attachment_picker.dart';
import 'package:mosh/src/features/shared/confirm_dialog.dart';
import 'package:mosh/src/rust/org_runtime.dart';
import '../../support/pump.dart';

void main() {
  testWidgets('the send button catches taps just outside its 32px paint',
      (tester) async {
    var sends = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: ConversationComposer(
              controller: TextEditingController(text: 'hi'),
              sending: false,
              placeholder: 'placeholder',
              sendLabel: 'Send',
              onSend: () => sends++,
              attachLabel: 'Attach',
              onAttach: (_) {},
              onAttachmentPickError: (_) {},
              voiceRecordLabel: 'Record',
              voiceDiscardLabel: 'Discard',
              voiceStopLabel: 'Stop',
              voicePlayLabel: 'Play',
              voiceSendLabel: 'Send voice',
              onSendVoice: (_) {},
              onVoiceError: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final rect = tester.getRect(find.byKey(kComposerSendButtonKey));
    // Composer layout: the Row child is the button's own M3 padded
    // layout box (>= 40px on every platform; the exact height tracks the
    // row). The painted square inside stays 32x32. No wrapper consumes
    // composer Row space (CodeAnt #12 comment on
    // conversation_composer.dart).
    expect(rect.width, greaterThanOrEqualTo(40));
    expect(rect.height, greaterThanOrEqualTo(40));
    final paintedRect = tester.getRect(
      find
          .descendant(
            of: find.byKey(kComposerSendButtonKey),
            matching: find.byType(Material),
          )
          .first,
    );
    expect(paintedRect.size, const Size(32, 32));

    // 20px left of center: outside the painted square, inside the button's
    // own padded tap target.
    await tester.tapAt(rect.center - const Offset(20, 0));
    await tester.pump();

    expect(sends, 1);
  });

  testWidgets('the paperclip picker is at least a 40px target', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: AttachmentPicker(
              disabled: false,
              ariaLabel: 'attach',
              onPick: (_) {},
              onError: (_) {},
            ),
          ),
        ),
      ),
    );

    final size = tester.getSize(find.byType(AttachmentPicker));
    expect(size.width, greaterThanOrEqualTo(40));
    expect(size.height, greaterThanOrEqualTo(40));
  });

  testWidgets('the fingerprint lock target reaches past its 15px glyph',
      (tester) async {
    await pumpScreen(
      tester,
      const Scaffold(
        body: Center(
          child: FingerprintLock(
            fingerprint: '0011223344556677',
            hint: 'same on both sides',
          ),
        ),
      ),
    );

    final rect = tester.getRect(find.byType(FingerprintLock));
    expect(rect.size.width, greaterThanOrEqualTo(40));
    expect(rect.size.height, greaterThanOrEqualTo(40));

    // 16px right of center: inside the padded target, far outside the old
    // 15px glyph hit box.
    await tester.tapAt(rect.center + const Offset(16, 0));
    await tester.pumpAndSettle();
    expect(find.text('Encryption fingerprint'), findsOneWidget);
  });

  testWidgets('the confirm-dialog close X is at least a 40px target',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: ConfirmDialog(
              title: 'Leave chat?',
              body: 'This will erase the keys. Are you sure?',
              confirmLabel: 'Leave',
              cancelLabel: 'Cancel',
              onCancel: () {},
              onConfirm: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final size = tester.getSize(
      find.widgetWithIcon(IconButton, Icons.close),
    );
    expect(size.width, greaterThanOrEqualTo(40));
    expect(size.height, greaterThanOrEqualTo(40));
  });

  testWidgets('the org offer dismiss X is at least a 40px target',
      (tester) async {
    await pumpScreen(
      tester,
      Builder(
        builder: (context) {
          final l = AppLocalizations.of(context)!;
          return Scaffold(
            body: OrgSection(
              org: OrgSnapshot(
                orgPubkey: 'k',
                orgName: 'Org',
                meshId: 'mesh',
                ownPeerId: 'self',
                confirmationCode: 'CODE',
                inRoster: false,
                members: const [],
                dmOffers: [
                  const OrgDmOfferView(
                    offerId: 'o1',
                    fromPeerId: 'p1',
                    fromName: 'Alice',
                    inviteUri: 'mosh://invite',
                  ),
                ],
                groupOffers: const [],
                dmLinks: const [],
              ),
              busy: false,
              onMember: (_, __) {},
              onAcceptDmOffer: (_, __) {},
              onDismissDmOffer: (_, __) {},
              onAcceptGroupOffer: (_, __) {},
              onDismissGroupOffer: (_, __) {},
              onCreateGroup: (_, __) {},
              onLeave: (_) {},
              l: l,
            ),
          );
        },
      ),
    );

    final size = tester.getSize(
      find.widgetWithIcon(IconButton, Icons.close).first,
    );
    expect(size.width, greaterThanOrEqualTo(40));
    expect(size.height, greaterThanOrEqualTo(40));
  });
}
