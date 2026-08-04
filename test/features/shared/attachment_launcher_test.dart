import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/src/features/shared/attachment_launcher.dart';

void main() {
  test('rejects non-desktop platforms before invoking url_launcher', () async {
    var launchCalls = 0;
    final launcher = UrlLauncherAttachmentLauncher(
      isDesktop: false,
      launch: (_) async {
        launchCalls++;
        return true;
      },
    );

    await expectLater(
      launcher.open('/tmp/report.pdf'),
      throwsA(
        isA<UnsupportedError>().having(
          (error) => error.message,
          'message',
          'Opening downloaded files is supported on Windows, macOS, and Linux.',
        ),
      ),
    );
    expect(launchCalls, 0);
  });

  test('launches a file URI on desktop through the injected function',
      () async {
    Uri? launchedUri;
    final launcher = UrlLauncherAttachmentLauncher(
      isDesktop: true,
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
    final launcher = UrlLauncherAttachmentLauncher(
      isDesktop: true,
      launch: (_) async => false,
    );

    await expectLater(
      launcher.open('/tmp/report.pdf'),
      throwsA(isA<StateError>()),
    );
  });
}
