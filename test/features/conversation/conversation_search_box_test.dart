// Regression test for the search field's caret.
//
// Both search rows used to build `TextEditingController(text: search)`
// inside `build`, so every rebuild handed the TextField a fresh controller
// and the caret snapped back to offset 0. Harmless while the screens only
// rebuilt on keystrokes; the 1 s snapshot poll now rebuilds them constantly,
// which would reset the caret mid-word. ConversationSearchBox owns the
// controller and only writes the incoming value back when it differs.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/conversation/conversation_search_box.dart';
import '../../support/pump.dart';

/// Hosts the box the way a screen does: the value lives in the parent and
/// comes back down as a prop.
class _Host extends StatefulWidget {
  const _Host({super.key});

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  String _search = '';

  /// Rebuilds without changing the query, standing in for a poll tick.
  void poll() => setState(() {});

  @override
  Widget build(BuildContext context) {
    return ConversationSearchBox(
      search: _search,
      onSearch: (value) => setState(() => _search = value),
      l: AppLocalizations.of(context)!,
    );
  }
}

TextEditingController _controller(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField)).controller!;

void main() {
  final hostKey = GlobalKey<_HostState>();

  Future<void> pumpBox(WidgetTester tester) =>
      pumpScreen(tester, Scaffold(body: _Host(key: hostKey)));

  testWidgets('a rebuild with an unchanged query leaves the caret alone',
      (tester) async {
    await pumpBox(tester);

    await tester.enterText(find.byType(TextField), 'report');
    await tester.pumpAndSettle();

    // Put the caret mid-word, as a user editing a typo would.
    _controller(tester).selection = const TextSelection.collapsed(offset: 3);
    await tester.pump();

    hostKey.currentState!.poll();
    await tester.pumpAndSettle();

    expect(_controller(tester).text, 'report');
    expect(_controller(tester).selection.baseOffset, 3,
        reason: 'a poll-driven rebuild must not move the caret');
  });

  testWidgets('an externally cleared query still reaches the field',
      (tester) async {
    await pumpBox(tester);

    await tester.enterText(find.byType(TextField), 'report');
    await tester.pumpAndSettle();
    expect(_controller(tester).text, 'report');

    // The mobile close button clears through the host (onSearch('')).
    await tester.enterText(find.byType(TextField), '');
    await tester.pumpAndSettle();
    expect(_controller(tester).text, isEmpty);
  });
}
