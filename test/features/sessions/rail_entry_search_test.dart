import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/sessions/rail_entry.dart';
import '../../support/message_builders.dart';

void main() {
  test('renamed DMs remain searchable by canonical id, original name and alias',
      () async {
    final l = await AppLocalizations.delegate.load(const Locale('en'));
    final entry = DmRailEntry(
        TestSnapshots.dm(sessionId: 'canonical-42', peerDisplayName: 'Alice'),
        personalName: 'Family');
    for (final query in ['canonical-42', 'Alice', 'Family']) {
      expect(recentRailEntries([entry], l, query: query), [entry]);
    }
  });
}
