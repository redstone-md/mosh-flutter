import 'dart:io';

import 'package:build_tool/src/builder.dart';
import 'package:build_tool/src/options.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

void main() {
  late Directory root;
  late Directory crate;

  setUp(() {
    root = Directory.systemTemp.createTempSync('cargokit_options');
    crate = Directory(path.join(root.path, 'mosh-core'))..createSync();
  });
  tearDown(() => root.deleteSync(recursive: true));

  void pin(String channel) => File(path.join(root.path, 'rust-toolchain.toml'))
      .writeAsStringSync('[toolchain]\nchannel = "$channel"\n');
  void configure(String yaml) =>
      File(path.join(crate.path, 'cargokit.yaml')).writeAsStringSync(yaml);
  String toolchain() => CargokitCrateOptions.load(manifestDir: crate.path)
      .toolchain(BuildConfiguration.release);

  test('builds with the channel pinned above the crate, as rustup would', () {
    pin('1.96.0');
    configure('cargo:\n  release:\n    extra_flags: [--locked]\n');

    expect(toolchain(), '1.96.0');
  });

  test('a toolchain named in cargokit.yaml overrides the pin', () {
    pin('1.96.0');
    configure('cargo:\n  release:\n    toolchain: nightly\n');

    expect(toolchain(), 'nightly');
  });

  test('builds with stable when the pin names no channel', () {
    File(path.join(root.path, 'rust-toolchain.toml'))
        .writeAsStringSync('[toolchain]\npath = "/opt/rust"\n');

    expect(toolchain(), 'stable');
  });
}
