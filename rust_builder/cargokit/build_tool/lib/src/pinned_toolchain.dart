import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:toml/toml.dart';

/// The channel of the nearest `rust-toolchain.toml` at or above [directory],
/// the file rustup itself would honour there, or null without one.
///
/// Cargokit names its toolchain explicitly (`rustup run <toolchain> cargo`),
/// which overrides that file; the builder passes this channel instead so app
/// builds compile with the repository's pinned compiler, not whatever
/// `stable` the machine has.
String? pinnedToolchain(String directory) {
  var current = path.normalize(path.absolute(directory));
  while (true) {
    final file = File(path.join(current, 'rust-toolchain.toml'));
    if (file.existsSync()) {
      final toolchain =
          TomlDocument.parse(file.readAsStringSync()).toMap()['toolchain'];
      final channel = toolchain is Map ? toolchain['channel'] : null;
      return channel is String ? channel : null;
    }
    final parent = path.dirname(current);
    if (parent == current) return null;
    current = parent;
  }
}
