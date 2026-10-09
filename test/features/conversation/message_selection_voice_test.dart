import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/conversation/message_selection.dart';
import 'package:mosh/src/features/conversation/message_selection_actions.dart';
import 'package:mosh/src/features/shared/voice_composer.dart';

import '../../support/pump.dart';
import '../../support/voice_recorder.dart';

Future<void> _pumpComposer(WidgetTester tester, MessageSelection selection,
    List<VoiceSend> sent, List<String> errors,
    {double width = 390}) async {
  tester.view.physicalSize = Size(width, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(selection.dispose);
  selection.retain(['m1']);
  await pumpScreen(
    tester,
    Scaffold(
      body: MessageSelectionScope(
        selection: selection,
        onDelete: (_) {},
        onDeleteSelected: () {},
        onCopySelected: () {},
        selectedText: () => 'message',
        child: MessageSelectionComposer(
          child: VoiceComposer(
            disabled: false,
            onSend: sent.add,
            onError: errors.add,
            recordLabel: 'Record',
            discardLabel: 'Discard',
            stopLabel: 'Stop',
            playLabel: 'Play',
            sendLabel: 'Send voice',
            permissionDeniedLabel: 'mic denied',
            inputDeviceId: () => null,
          ),
        ),
      ),
    ),
  );
}

Future<void> _record(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Record'));
  // Capture has periodic timers, so pump frames instead of settling.
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 50));
}

Future<void> _hiddenRecording(WidgetTester tester) async {
  final recorder = VoiceRecorderProbe(tester);
  final selection = MessageSelection();
  final sent = <VoiceSend>[];
  final errors = <String>[];
  await _pumpComposer(tester, selection, sent, errors);
  await _record(tester);
  await tester.pump(const Duration(seconds: 1));
  expect(recorder.recording, isTrue);
  final state = tester.state(find.byType(VoiceComposer));
  selection.toggle('m1');
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 50));
  expect(recorder.count('stop'), 1);
  expect(recorder.recording, isFalse);
  expect(recorder.count('cancel'), 0);
  expect(sent, isEmpty);
  expect(find.byTooltip('Stop'), findsNothing);
  await tester.pump(const Duration(seconds: 2));
  selection.exit();
  await tester.pumpAndSettle();
  expect(tester.state(find.byType(VoiceComposer)), same(state));
  expect(find.byTooltip('Play'), findsOneWidget);
  expect(File(recorder.path!).existsSync(), isTrue);
  await tester.tap(find.byTooltip('Send voice'));
  await tester.pumpAndSettle();
  expect(sent.single.path, recorder.path);
  expect(sent.single.durationMs, lessThan(2000));
  expect(recorder.count('start'), 1);
  expect(recorder.count('stop'), 1);
  expect(errors, isEmpty);
}

Future<void> _desktopRecording(WidgetTester tester) async {
  final recorder = VoiceRecorderProbe(tester);
  final selection = MessageSelection();
  final errors = <String>[];
  await _pumpComposer(tester, selection, [], errors, width: 1000);
  await _record(tester);
  selection.toggle('m1');
  await tester.pump(const Duration(milliseconds: 50));
  expect(recorder.recording, isTrue);
  expect(recorder.count('stop'), 0);
  expect(find.byTooltip('Stop'), findsOneWidget);
  tester.view.physicalSize = const Size(390, 844);
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 50));
  expect(recorder.count('stop'), 1);
  expect(recorder.recording, isFalse);
  selection.exit();
  await tester.pumpAndSettle();
  expect(find.byTooltip('Play'), findsOneWidget);
  expect(errors, isEmpty);
}

Future<void> _pendingPermission(WidgetTester tester) async {
  final recorder = VoiceRecorderProbe(tester)..permission = Completer<bool>();
  final selection = MessageSelection();
  final errors = <String>[];
  await _pumpComposer(tester, selection, [], errors);
  await _record(tester);
  expect(recorder.count('hasPermission'), 1);
  selection.toggle('m1');
  await tester.pump();
  recorder.permission!.complete(true);
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 50));
  expect(recorder.count('start'), 0);
  expect(recorder.recording, isFalse);
  selection.exit();
  await tester.pumpAndSettle();
  expect(find.byTooltip('Record'), findsOneWidget);
  expect(errors, isEmpty);
}

Future<void> _pendingStart(WidgetTester tester) async {
  final recorder = VoiceRecorderProbe(tester)..starting = Completer<void>();
  final selection = MessageSelection();
  final errors = <String>[];
  await _pumpComposer(tester, selection, [], errors);
  await _record(tester);
  expect(recorder.count('start'), 1);
  selection.toggle('m1');
  await tester.pump();
  recorder.starting!.complete();
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 50));
  expect(recorder.count('stop'), 1);
  expect(recorder.recording, isFalse);
  selection.exit();
  await tester.pumpAndSettle();
  expect(find.byTooltip('Play'), findsOneWidget);
  expect(errors, isEmpty);
}

void main() {
  testWidgets('mobile selection stops capture and preserves the clip',
      _hiddenRecording);
  testWidgets('desktop selection keeps controls until the composer is hidden',
      _desktopRecording);
  testWidgets('selection during permission does not start hidden capture',
      _pendingPermission);
  testWidgets('selection during capture startup finishes the hidden recording',
      _pendingStart);
}
