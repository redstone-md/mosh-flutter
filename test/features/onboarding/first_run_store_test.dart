import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/onboarding/first_run_profile.dart';

void main() {
  late Directory directory;
  late FirstRunStore store;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('mosh-first-run-');
    store = FirstRunStore(directory);
  });
  tearDown(() => directory.delete(recursive: true));

  test('new installation has no saved profile', () async {
    expect(await store.read(), isNull);
  });

  test('replacement restores name, progress and completion in a new store',
      () async {
    await store.write(
        const FirstRunProfile(displayName: 'Juno', step: SetupStep.device));
    await store.write(const FirstRunProfile(
        displayName: 'Juno', step: SetupStep.network, completed: true));
    final restored = await FirstRunStore(directory).read();
    expect(restored!.displayName, 'Juno');
    expect(restored.step, SetupStep.network);
    expect(restored.completed, isTrue);
    expect(
        await File('${directory.path}/first-run.json.tmp').exists(), isFalse);
  });

  test('overlapping writes preserve the latest submitted progress', () async {
    await Future.wait([
      store.write(const FirstRunProfile(displayName: 'One')),
      store.write(
          const FirstRunProfile(displayName: 'Two', step: SetupStep.device)),
    ]);
    expect((await store.read())!.displayName, 'Two');
  });

  test('a failed replacement preserves the previous record and permits retry',
      () async {
    await store.write(const FirstRunProfile(displayName: 'Original'));
    final obstruction = Directory('${directory.path}/first-run.json.tmp');
    await obstruction.create();
    await expectLater(store.write(const FirstRunProfile(displayName: 'Lost')),
        throwsA(isA<FileSystemException>()));
    expect((await store.read())!.displayName, 'Original');
    await obstruction.delete();
    await store.write(const FirstRunProfile(displayName: 'Recovered'));
    expect((await store.read())!.displayName, 'Recovered');
  });

  test('corrupt or unknown preferences never become a fresh installation',
      () async {
    for (final content in [
      'invalid',
      '{}',
      '{"version":2,"displayName":"Juno","step":"name","completed":false}',
      '{"version":1,"displayName":"","step":"network","completed":false}'
    ]) {
      await File('${directory.path}/first-run.json').writeAsString(content);
      await expectLater(store.read(), throwsFormatException);
    }
  });

  test('an uninitialized storage directory cannot claim success', () async {
    await expectLater(FirstRunStore(null).read(), throwsStateError);
    await expectLater(
        FirstRunStore(null).write(const FirstRunProfile()), throwsStateError);
  });
}
