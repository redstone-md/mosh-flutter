import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/conversation/attachment_actions.dart';
import 'package:mosh/src/rust/conversation/attachments.dart';
import '../../support/pump.dart';

AttachmentDescriptor _descriptor() => AttachmentDescriptor(
      attachmentId: 'attachment-1',
      contentHash: 'hash-1',
      fileName: 'report.pdf',
      mime: 'application/pdf',
      totalSize: BigInt.from(1024),
    );

IconButton _actionButton(WidgetTester tester) =>
    tester.widget<IconButton>(find.byType(IconButton));

void main() {
  testWidgets('offered download is disabled while a transfer is busy',
      (tester) async {
    await pumpScreen(
        tester,
        Builder(
          builder: (context) => Scaffold(
            body: AttachmentActions(
              descriptor: _descriptor(),
              view: null,
              state: AttachmentState.offered,
              outgoing: false,
              busy: true,
              onDownload: (_) {},
              onCancel: (_) {},
              onOpen: (_) {},
              l: AppLocalizations.of(context)!,
            ),
          ),
        ));

    expect(_actionButton(tester).onPressed, isNull);
  });

  testWidgets('failed retry is disabled while a transfer is busy',
      (tester) async {
    await pumpScreen(
        tester,
        Builder(
          builder: (context) => Scaffold(
            body: AttachmentActions(
              descriptor: _descriptor(),
              view: null,
              state: AttachmentState.failed,
              outgoing: false,
              busy: true,
              onDownload: (_) {},
              onCancel: (_) {},
              onOpen: (_) {},
              l: AppLocalizations.of(context)!,
            ),
          ),
        ));

    expect(_actionButton(tester).onPressed, isNull);
  });

  testWidgets('downloading cancel stays enabled while a transfer is busy',
      (tester) async {
    await pumpScreen(
        tester,
        Builder(
          builder: (context) => Scaffold(
            body: AttachmentActions(
              descriptor: _descriptor(),
              view: null,
              state: AttachmentState.downloading,
              outgoing: false,
              busy: true,
              onDownload: (_) {},
              onCancel: (_) {},
              onOpen: (_) {},
              l: AppLocalizations.of(context)!,
            ),
          ),
        ));

    expect(_actionButton(tester).onPressed, isNotNull);
  });
}
