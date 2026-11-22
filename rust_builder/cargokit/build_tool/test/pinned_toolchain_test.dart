import 'dart:io';

import 'package:build_tool/src/pinned_toolchain.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('pinned_toolchain'));
  tearDown(() => root.deleteSync(recursive: true));

  test('finds the channel pinned above the crate, as rustup does', () {
    File(path.join(root.path, 'rust-toolchain.toml'))
        .writeAsStringSync('[toolchain]\nchannel = "1.96.0"\n');
    final crate = Directory(path.join(root.path, 'mosh-core'))..createSync();

    expect(pinnedToolchain(crate.path), '1.96.0');
  });

  test('is null without a toolchain file, so cargokit keeps its default', () {
    expect(pinnedToolchain(root.path), isNull);
  });
}
