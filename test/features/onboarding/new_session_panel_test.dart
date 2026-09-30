// Opening a step from the desktop welcome menu keeps the content column
// where the menu was: same left edge, same width.
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/onboarding/chat_create_step.dart';
import 'package:mosh/src/features/onboarding/onboard_menu.dart';
import 'package:mosh/src/routing/mosh_shell.dart';
import 'package:mosh/src/state/gateway_provider.dart';
import '../../support/pump.dart';
import '../../support/scriptable_gateway.dart';

void main() {
  testWidgets('a step lines up with the menu it replaced', (tester) async {
    await pumpScreen(
      tester,
      const ChatPaneWelcome(),
      overrides: [gatewayProvider.overrideWithValue(ScriptableGateway())],
    );
    final menu = tester.getRect(find.byType(OnboardMenu));
    final l = AppLocalizations.of(tester.element(find.byType(OnboardMenu)))!;

    await tester.tap(find.text(l.onboardTileChatTitle));
    await tester.pumpAndSettle();

    final step = tester.getRect(find.byType(ChatCreateStep));
    expect(step.left, menu.left);
    expect(step.width, menu.width);
  });
}
