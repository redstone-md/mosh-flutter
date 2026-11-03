import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/sessions/rail_entry.dart';
import 'package:mosh/src/rust/message_deletion/types.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import '../../support/message_builders.dart';

void main() {
  test('deleted latest messages have a localized preview and keep chat order',
      () async {
    final l = await AppLocalizations.delegate.load(const Locale('en'));
    final entry = DmRailEntry(TestSnapshots.dm(sessionId: 'dm', messages: [
      ChatMessage(
          fromDevice: 'peer', body: 'earlier text', sentAtMs: BigInt.one),
      ChatMessage(
          fromDevice: 'peer',
          body: '',
          sentAtMs: BigInt.two,
          metadata: const MessageMetadata(
              canDeleteForEveryone: false,
              localOnly: false,
              deletion: DeletionMarker(
                  scope: DeleteScope.forEveryone,
                  status: DeletionStatus.confirmed))),
    ]));
    expect(entry.preview(l), 'Message deleted');
    expect(entry.activity.sentAtMs, BigInt.two);
  });
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
