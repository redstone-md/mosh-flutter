import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/app/bundled_licenses.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the license page lists the native code Flutter does not collect',
      () async {
    final entries = await bundledLicenses().toList();
    LicenseEntry entryOf(String package) =>
        entries.firstWhere((entry) => entry.packages.contains(package));
    String textOf(LicenseEntry entry) =>
        entry.paragraphs.map((paragraph) => paragraph.text).join('\n');

    expect(textOf(entryOf('Mosh')), contains('GNU GENERAL PUBLIC LICENSE'));
    expect(textOf(entryOf('openmls')), isNotEmpty);
    expect(textOf(entryOf('github.com/anacrolix/torrent')),
        contains('Mozilla Public License'));
    final libmpv = entries
        .where((entry) => entry.packages.contains('libmpv'))
        .map(textOf)
        .join('\n');
    expect(libmpv, contains('GNU LESSER GENERAL PUBLIC LICENSE'));
    for (final build in [
      'libmpv-win32-video-build/releases/tag/',
      'libmpv-darwin-build/releases/tag/',
    ]) {
      expect(libmpv, contains(build));
    }
  });
}
