import 'package:flutter_test/flutter_test.dart';
import 'package:open_filex/open_filex.dart';

import 'package:mosh/src/features/shared/attachment_launcher.dart';

void main() {
  group('AttachmentLauncherImpl desktop (url_launcher path)', () {
    test('launches a file URI on desktop through the injected function',
        () async {
      Uri? launchedUri;
      final launcher = AttachmentLauncherImpl(
        isDesktop: true,
        isAndroid: false,
        isWeb: false,
        launch: (uri) async {
          launchedUri = uri;
          return true;
        },
      );

      await launcher.open('/tmp/report with spaces.pdf');

      expect(launchedUri, Uri.file('/tmp/report with spaces.pdf'));
    });

    test('fails predictably when the desktop launcher declines the URI',
        () async {
      final launcher = AttachmentLauncherImpl(
        isDesktop: true,
        isAndroid: false,
        isWeb: false,
        launch: (_) async => false,
      );

      await expectLater(
        launcher.open('/tmp/report.pdf'),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('AttachmentLauncherImpl android (open_filex path)', () {
    test('opens when open_filex reports ResultType.done', () async {
      var openCalls = 0;
      String? openedPath;
      final launcher = AttachmentLauncherImpl(
        isDesktop: false,
        isAndroid: true,
        isWeb: false,
        openFilex: (path) async {
          openCalls++;
          openedPath = path;
          return OpenResult(type: ResultType.done, message: 'done');
        },
      );

      await launcher.open('/data/user/0/app/files/attachments/report.pdf');

      expect(openCalls, 1);
      expect(
        openedPath,
        '/data/user/0/app/files/attachments/report.pdf',
      );
    });

    test('throws StateError with the result message on a non-done result',
        () async {
      final launcher = AttachmentLauncherImpl(
        isDesktop: false,
        isAndroid: true,
        isWeb: false,
        openFilex: (_) async => OpenResult(
          type: ResultType.noAppToOpen,
          message: 'No app found to open this file',
        ),
      );

      await expectLater(
        launcher.open('/tmp/report.pdf'),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('No app found to open this file'),
          ),
        ),
      );
    });
  });

  group('AttachmentLauncherImpl web', () {
    test('throws UnsupportedError before any plugin is invoked', () async {
      var launchCalls = 0;
      var openFilexCalls = 0;
      final launcher = AttachmentLauncherImpl(
        isWeb: true,
        launch: (_) async {
          launchCalls++;
          return true;
        },
        openFilex: (_) async {
          openFilexCalls++;
          return OpenResult(type: ResultType.done, message: 'done');
        },
      );

      await expectLater(
        launcher.open('/tmp/report.pdf'),
        throwsA(isA<UnsupportedError>()),
      );
      expect(launchCalls, 0);
      expect(openFilexCalls, 0);
    });
  });
}
