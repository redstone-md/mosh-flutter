// The app's icon roles and the roles of the Figma file "Mosh" are one list:
// a role added to either side without the other fails here.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _camel(String name) => name.replaceAllMapped(
    RegExp('[-_](\\w)'), (match) => match.group(1)!.toUpperCase());

void main() {
  test('MoshIcons holds the glyph icons.json names for every role', () {
    final figma =
        (jsonDecode(File('scripts/figma-design/icons.json').readAsStringSync())
                as Map)
            .cast<String, String>();
    const styles = {
      'Phosphor': 'regular',
      'PhosphorFill': 'fill',
      'PhosphorBold': 'bold'
    };
    // Each constant names its glyph in a trailing comment; the font family
    // must be the one that glyph's style lives in.
    final source = File('lib/src/app/mosh_icons.dart').readAsStringSync();
    final app = {
      for (final match in RegExp(
              r"static const IconData (\w+) =\s*IconData\(0x[0-9a-f]+, fontFamily: '(\w+)'\); // ([\w-]+)")
          .allMatches(source))
        match.group(1)!: (styles[match.group(2)!], match.group(3)!),
    };

    expect(app.length, 'static const IconData'.allMatches(source).length,
        reason: 'a role without its glyph name in a trailing comment');
    expect(app, {
      for (final MapEntry(key: role, value: glyph) in figma.entries)
        _camel(role): (
          glyph.endsWith('-fill')
              ? 'fill'
              : glyph.endsWith('-bold')
                  ? 'bold'
                  : 'regular',
          glyph
        ),
    });
  });
}
