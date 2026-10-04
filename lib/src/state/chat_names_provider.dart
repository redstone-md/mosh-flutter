import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mosh/src/gateway/conversation_target.dart';
import 'package:mosh/src/rust/chat_names/types.dart';
import 'package:mosh/src/state/gateway_provider.dart';

final chatNamesProvider =
    AsyncNotifierProvider<ChatNamesNotifier, ChatNameSnapshot>(
        ChatNamesNotifier.new);

class ChatNamesNotifier extends AsyncNotifier<ChatNameSnapshot> {
  bool _reading = false;

  @override
  Future<ChatNameSnapshot> build() {
    _reading = false;
    return ref.watch(bridgeFacadeProvider).personalNames();
  }

  Future<void> refresh() async {
    if (_reading || state.isLoading) return;
    _reading = true;
    final startedUnder = ref;
    final next = await AsyncValue.guard(
        () => startedUnder.read(bridgeFacadeProvider).personalNames());
    if (!startedUnder.mounted) return;
    state = next;
    _reading = false;
  }
}

final personalChatRenameAvailableProvider = Provider<bool>((ref) => ref.watch(
    chatNamesProvider.select((names) => names.value?.canRename ?? false)));

/// The canonical address stays separate from the name used for display.
final personalChatNameProvider =
    Provider.family<String?, ConversationRef>((ref, conversation) {
  final entries =
      ref.watch(chatNamesProvider).value?.entries ?? const <ChatNameEntry>[];
  for (final entry in entries) {
    if (entry.conversationKey == conversation.key) return entry.name;
  }
  return null;
});

String chatDisplayName(String originalName, String? personalName) =>
    personalName ?? originalName;
