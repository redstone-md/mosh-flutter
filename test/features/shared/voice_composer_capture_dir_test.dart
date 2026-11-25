// The VoiceComposer capture-directory regression (macOS 0.9.3 field bug:
// `PathNotFoundException` errno 2 on `…/Caches/app.mosh.mosh/mosh-voice-…​.m4a`).
//
// Root cause: `getTemporaryDirectory()` on macOS maps to
// `NSCachesDirectory` + the bundle id appended, and path_provider does NOT
// create that directory; `record_macos` writes via
// `AVCaptureFileOutput.startRecording(to:)`, which never creates parent
// dirs and reports the failure only to an unsurfaced delegate callback —
// `stop()` still returns the path, and `sendVoice`'s `readAsBytes()` dies
// with "No such file or directory".
//
// What is pinned here:
//  1. The clip path the recorder receives lives inside an explicitly
//     created `mosh-voice/` subdirectory (not the raw cache root).
//  2. The directory is created recursively EVEN WHEN the base dir does not
//     exist yet (the exact macOS state: base missing → errno 2).
//  3. The base dir switches to the app cache dir
//     (`getApplicationCacheDirectory`), whose plugin path DOES create the
//     base — belt and braces with the explicit recursive create.
//
// Driven through the real `record` plugin seam (VoiceRecorderProbe, whose
// capture fails like AVCaptureFileOutput when the directory is missing);
// `path_provider` answers a base dir that does not exist yet, so the
// recursive create is exercised for real on the host filesystem. Only
// `getApplicationCacheDirectory` is answered: a regression back to the
// temp dir gets no path at all.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../support/voice_recorder.dart';

void main() {
  testWidgets(
      'capture targets a mosh-voice/ dir created under a missing cache base',
      (tester) async {
    final base =
        Directory.systemTemp.createTempSync('mosh-voice-dir-test-parent');
    addTearDown(() => base.deleteSync(recursive: true));
    final recorder = VoiceRecorderProbe(tester,
        cache: Directory('${base.path}/Caches/app.mosh.mosh'));
    final errors = <String>[];
    await pumpVoiceComposer(tester, errors: errors);

    await tester.tap(find.byTooltip('Record'));
    await pumpVoiceFrames(tester);

    expect(errors, isEmpty,
        reason: 'the clip directory exists before the capture begins');
    // The clip lands in the mosh-voice subdirectory, not the cache root.
    expect(recorder.started.single, contains('mosh-voice'));
    expect(recorder.started.single, endsWith('.m4a'));
  });
}
