// What a press on an attachment's card does in each state of its transfer.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_icons.dart';
import 'package:mosh/src/features/conversation/attachment_actions.dart';
import 'package:mosh/src/features/conversation/conversation_attachment.dart';
import 'package:mosh/src/rust/conversation/attachments.dart';
import '../../support/conversation_cases.dart';

final _l = lookupAppLocalizations(const Locale('en'));

/// The action of a file in [state], with what it called recorded in [calls].
AttachmentAction? _action(AttachmentState state, List<String> calls,
        {bool busy = false, String mime = 'application/pdf', String? path}) =>
    attachmentAction(
      ConversationAttachment(
          descriptor: AttachmentDescriptor(
            attachmentId: 'attachment-1',
            contentHash: 'hash-1',
            fileName: 'report.pdf',
            mime: mime,
            totalSize: BigInt.from(1024),
          ),
          view: testAttachmentView(
              attachmentId: 'attachment-1', state: state, localPath: path)),
      busy: busy,
      l: _l,
      onDownload: (id) => calls.add('download $id'),
      onCancel: (id) => calls.add('cancel $id'),
      onOpen: () => calls.add('open'),
    );

void main() {
  for (final (state, glyph, tooltip, call) in [
    (AttachmentState.offered, MoshIcons.download, 'Download', 'download'),
    (AttachmentState.paused, MoshIcons.download, 'Resume download', 'download'),
    (
      AttachmentState.cancelled,
      MoshIcons.refresh,
      'Retry download',
      'download'
    ),
    (AttachmentState.failed, MoshIcons.refresh, 'Retry', 'download'),
    (AttachmentState.downloading, MoshIcons.close, 'Cancel download', 'cancel'),
  ]) {
    test('${state.name}: the card offers "$tooltip"', () {
      final calls = <String>[];
      final action = _action(state, calls)!;
      expect(action.glyph, glyph);
      expect(action.tooltip, tooltip);
      expect(action.label, contains('report.pdf'));
      action.onPressed!();
      expect(calls, ['$call attachment-1']);
    });
  }

  for (final state in [
    AttachmentState.offered,
    AttachmentState.paused,
    AttachmentState.cancelled,
    AttachmentState.failed,
  ]) {
    test('${state.name} waits while another transfer is busy', () {
      expect(_action(state, [], busy: true)!.onPressed, isNull);
    });
  }

  test('a running transfer can be stopped while it keeps the others waiting',
      () {
    expect(_action(AttachmentState.downloading, [], busy: true)!.onPressed,
        isNotNull);
  });

  test('a file that is here opens', () {
    final calls = <String>[];
    final action =
        _action(AttachmentState.available, calls, path: '/tmp/report.pdf')!;
    expect(action.opens, isTrue);
    action.onPressed!();
    expect(calls, ['open']);
  });

  test('opening media that has not arrived waits for another transfer', () {
    final action =
        _action(AttachmentState.offered, [], mime: 'audio/mpeg', busy: true)!;
    expect(action.opens, isTrue);
    expect(action.onPressed, isNull);
  });

  test('media that can play before it has arrived opens straight away', () {
    final calls = <String>[];
    _action(AttachmentState.offered, calls, mime: 'audio/mpeg')!.onPressed!();
    expect(calls, ['open']);
  });
}
