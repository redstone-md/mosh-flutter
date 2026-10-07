// Widget tests for the group-create step (GroupCreateStep), opened the way
// a person does: the start menu in the chat pane at /chat, then a tap on
// the "Create a group" card (`pumpStartStep`). The bridge is scripted.
//
// Test 1: initial state -- lead, name field, Create button, no invite.
// Test 2: the name is required: Create stays disabled until one is typed.
// Test 3: tapping Create calls the bridge's createGroup, replaces the form
//   with the InviteResult card (URI, Open group, footer) and auto-copies.
// Test 4: "Create another group" returns to an empty form.
// Test 5: Back returns to the start menu.
// Test 6: a failed create shows a persistent inline error, no SnackBar.
// Test 7: Open group lands on the group just created.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/src/features/conversation/group_screen.dart';
import 'package:mosh/src/features/onboarding/group_create_step.dart';
import 'package:mosh/src/features/onboarding/invite_result.dart';
import 'package:mosh/src/features/onboarding/start/start_menu.dart';
import '../../support/scriptable_bridge.dart';
import '../../support/scriptable_gateway.dart';
import '../../support/start_menu.dart';

const _card = 'Create a group';
const _groupStepBody =
    'Create a group with end-to-end encryption. You invite members once it exists.';
const _groupFooter =
    'Anyone who has this link can join the group. Send it only to people you want in.';

/// Stubs the flutter/services clipboard channel so the auto-copy on create
/// does not hang the test waiting on a real platform channel. Returns the
/// texts Clipboard.setData received.
List<String> _stubClipboard() {
  final copied = <String>[];
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'Clipboard.setData') {
      copied.add((call.arguments as Map)['text'] as String);
    }
    return null;
  });
  addTearDown(() => TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, null));
  return copied;
}

Finder _inStep(Finder matching) =>
    find.descendant(of: find.byType(GroupCreateStep), matching: matching);

final _nameField = _inStep(find.byType(TextField));
final _createButton = _inStep(find.byType(FilledButton));

void main() {
  Future<void> pumpGroupStep(WidgetTester tester, {ScriptableBridge? bridge}) =>
      pumpStartStep(tester, _card, bridge: bridge ?? ScriptableBridge());

  Future<void> createNamed(WidgetTester tester, String name) async {
    await tester.enterText(_nameField, name);
    await tester.pump();
    await tester.tap(_createButton);
    await tester.pumpAndSettle();
  }

  testWidgets('initial state renders lead, name field, and Create button',
      (tester) async {
    await pumpGroupStep(tester);

    expect(find.byType(GroupCreateStep), findsOneWidget);
    expect(find.text(_groupStepBody), findsOneWidget);
    expect(find.text('Group name'), findsOneWidget);
    expect(find.text('Create group'), findsOneWidget);
    expect(find.byType(InviteResult), findsNothing);
  });

  testWidgets('Create button is disabled until a name is typed',
      (tester) async {
    await pumpGroupStep(tester);

    FilledButton button() => tester.widget<FilledButton>(_createButton);
    expect(button().onPressed, isNull);

    // Whitespace alone is not a name.
    await tester.enterText(_nameField, '   ');
    await tester.pump();
    expect(button().onPressed, isNull);

    await tester.enterText(_nameField, 'friends');
    await tester.pump();
    expect(button().onPressed, isNotNull);
  });

  testWidgets(
      'tapping Create creates via the bridge and shows the InviteResult card',
      (tester) async {
    final bridge = ScriptableBridge();
    await pumpGroupStep(tester, bridge: bridge);
    final copied = _stubClipboard();

    // The scripted bridge derives the invite URI from the name.
    await createNamed(tester, 'friends');

    const uri = 'mosh://group/fake-group-friends';
    expect(find.byType(InviteResult), findsOneWidget);
    expect(find.text(uri), findsOneWidget);
    expect(find.text('Open group'), findsOneWidget);
    expect(find.text(_groupFooter), findsOneWidget);
    // The form is gone and the invite was copied on create.
    expect(_nameField, findsNothing);
    expect(find.text('Create group'), findsNothing);
    expect(copied, [uri]);
    expect(find.widgetWithText(OutlinedButton, 'Copied'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    // Reading the notifier initializes it once, then the explicit refresh
    // performs the post-create fetch. Pin both calls so this cannot pass on
    // provider initialization alone.
    expect(bridge.countOf(BridgeMethod.listGroups), 2);
  });

  testWidgets('Create another group returns to an empty form', (tester) async {
    await pumpGroupStep(tester);
    _stubClipboard();
    await createNamed(tester, 'friends');

    final another = find.widgetWithText(TextButton, 'Create another group');
    await tester.ensureVisible(another);
    await tester.tap(another);
    await tester.pumpAndSettle();

    expect(find.byType(InviteResult), findsNothing);
    expect(tester.widget<TextField>(_nameField).controller!.text, isEmpty);
    expect(tester.widget<FilledButton>(_createButton).onPressed, isNull);
  });

  testWidgets('Back returns to the start menu', (tester) async {
    await pumpGroupStep(tester);

    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();

    expect(find.byType(StartMenu), findsOneWidget);
    expect(find.byType(GroupCreateStep), findsNothing);
  });

  testWidgets(
      'a failed create surfaces a persistent inline error (role="alert") and no SnackBar',
      (tester) async {
    const message = 'Group runtime offline';
    final throwing = ScriptableBridge()
      ..failAlways(BridgeMethod.createGroup, error: message);
    _stubClipboard();
    await pumpGroupStep(tester, bridge: throwing);

    await createNamed(tester, 'friends');

    // A non-bridge error renders as its own text (the classifier's text
    // arm) and the inline error is the ONE source of feedback -- no
    // transient SnackBar.
    expect(find.text(message), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    expect(find.byType(InviteResult), findsNothing);
    expect(throwing.countOf(BridgeMethod.listGroups), 0);
  });

  testWidgets('Open group lands on the group just created', (tester) async {
    final gateway = ScriptableGateway();
    final bridge = ScriptableBridge(conversations: gateway.conversations);
    await pumpStartStep(tester, _card, bridge: bridge, gateway: gateway);
    _stubClipboard();

    await createNamed(tester, 'friends');
    await tester.tap(find.text('Open group'));
    await tester.pumpAndSettle();

    expect(find.byType(GroupScreen), findsOneWidget);
    expect(find.byType(GroupCreateStep), findsNothing);
  });
}
