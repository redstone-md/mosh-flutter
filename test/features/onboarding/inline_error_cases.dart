// A screen reader hears an onboarding inline error once, as a live region.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/src/features/onboarding/inline_error.dart';
import '../../support/pump.dart';

void main() {
  testWidgets('announces the message once as a live region', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpScreen(
      tester,
      const Scaffold(body: InlineError(message: 'Could not create invite')),
    );
    expect(
      tester.getSemantics(find.byType(InlineError)),
      isSemantics(label: 'Could not create invite', isLiveRegion: true),
    );
    semantics.dispose();
  });
}
