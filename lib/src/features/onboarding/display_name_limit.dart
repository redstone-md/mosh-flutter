import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show StringCharacters;

/// The longest display name in Unicode code points: the unit the core counts,
/// and 64 of them always fit the 256-byte name in a device proof.
const kDisplayNameMaxRunes = 64;

/// Keeps a typed or pasted name within [kDisplayNameMaxRunes], cutting only
/// between whole characters, so every name the field accepts also saves.
class DisplayNameLimit extends TextInputFormatter {
  const DisplayNameLimit();

  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    if (newValue.text.runes.length <= kDisplayNameMaxRunes) return newValue;
    final kept = StringBuffer();
    var runes = 0;
    for (final character in newValue.text.characters) {
      runes += character.runes.length;
      if (runes > kDisplayNameMaxRunes) break;
      kept.write(character);
    }
    final text = kept.toString();
    return TextEditingValue(
        text: text, selection: TextSelection.collapsed(offset: text.length));
  }
}
