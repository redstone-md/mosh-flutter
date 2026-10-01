import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mosh/src/platform/app_data_dir.dart' show appDataDir;

/// Stable ids survive copy, locale and application-version changes.
enum ConversationNoticeKind {
  publicChannel('public-channel'),
  encryptedGroup('encrypted-group');

  const ConversationNoticeKind(this.storageKey);
  final String storageKey;
}

/// Each dismissal is a durable marker, so simultaneous writes cannot
/// overwrite another notice's preference. These flags contain no chat data.
class ConversationNoticeStore {
  const ConversationNoticeStore(this.directory);
  final Directory? directory;

  Set<ConversationNoticeKind> read() => {
        if (directory != null)
          for (final kind in ConversationNoticeKind.values)
            if (_marker(kind).existsSync()) kind,
      };

  Future<void> dismiss(ConversationNoticeKind kind) async {
    final directory = this.directory;
    if (directory == null) {
      throw StateError('Application data directory is not initialized');
    }
    await directory.create(recursive: true);
    await _marker(kind).writeAsString('', flush: true);
  }

  File _marker(ConversationNoticeKind kind) =>
      File('${directory!.path}/${kind.storageKey}');
}

final conversationNoticeStoreProvider =
    Provider<ConversationNoticeStore>((ref) {
  final path = appDataDir();
  return ConversationNoticeStore(
      path == null ? null : Directory('$path/dismissed-conversation-notices'));
});

final dismissedConversationNoticesProvider =
    NotifierProvider<DismissedConversationNotices, Set<ConversationNoticeKind>>(
  DismissedConversationNotices.new,
);

class DismissedConversationNotices
    extends Notifier<Set<ConversationNoticeKind>> {
  @override
  Set<ConversationNoticeKind> build() =>
      ref.watch(conversationNoticeStoreProvider).read();

  Future<void> dismiss(ConversationNoticeKind kind) async {
    await ref.read(conversationNoticeStoreProvider).dismiss(kind);
    if (ref.mounted) state = Set.unmodifiable({...state, kind});
  }
}
