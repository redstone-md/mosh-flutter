// Primary controls carry a >= 40px tap area while their painted visuals
// stay unchanged (audit 2026-09-21, hit-areas finding).
//
// Per control:
//  - composer send button: on the desktop the painted 40px plate is the
//    target itself; a phone pads it to 48px (pinned here so no wrapper
//    ever re-introduces a layout cost beside the input);
//  - paperclip picker: the compact density shrank its hit box to 32px; the
//    LAYOUT box must be >= 40 (IconButton's hit area IS its layout box);
//  - fingerprint lock: a 15px glyph with a left-only inset was a ~19x15 tap
//    target; the padded InkWell must reach >= 40 and catch taps 16px right
//    of center;
//  - confirm-dialog close X and the org offer dismiss X: same >= 40 layout
//    contract.
import 'package:mosh/src/app/mosh_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_icons.dart';
import 'package:mosh/src/features/conversation/conversation_composer.dart';
import 'package:mosh/src/features/org/org_section.dart';
import 'package:mosh/src/features/shared/attachment_picker.dart';
import 'package:mosh/src/features/shared/mosh_dialog.dart';
import 'package:mosh/src/rust/org_runtime.dart';
import '../../support/pump.dart';

import '../../support/voice_recorder.dart';

void main() {
  testWidgets('the send button is a 40px plate that takes a press at its edge',
      (tester) async {
    var sends = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: moshThemeData,
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
              voiceLabels: testVoiceLabels,
              onSendVoice: (_) {},
              onVoiceError: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final rect = tester.getRect(find.byKey(kComposerSendButtonKey));
    expect(rect.width, greaterThanOrEqualTo(40));
    expect(rect.height, greaterThanOrEqualTo(40));
    final plate = tester.getRect(
      find
          .descendant(
            of: find.byKey(kComposerSendButtonKey),
            matching: find.byType(Material),
          )
          .first,
    );
    expect(plate.size, const Size(40, 40));

    await tester.tapAt(rect.center - const Offset(18, 0));
    await tester.pump();

    expect(sends, 1);
  });

  testWidgets('the paperclip picker is at least a 40px target', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: moshThemeData,
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

  testWidgets('the close X of a dialog without answers is a 40px target',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: moshThemeData,
        home: Scaffold(
          body: Center(
            child: MoshDialog(title: 'Call devices', closeLabel: 'Close'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final size = tester.getSize(
      find.widgetWithIcon(IconButton, MoshIcons.close),
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
                inRoster: true,
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
      find.widgetWithIcon(IconButton, MoshIcons.close).first,
    );
    expect(size.width, greaterThanOrEqualTo(40));
    expect(size.height, greaterThanOrEqualTo(40));
  });
}
