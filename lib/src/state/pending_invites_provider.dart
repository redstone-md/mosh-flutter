import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mosh/src/gateway/conversation_target.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import 'package:mosh/src/state/conversation_providers.dart';
import 'package:mosh/src/state/gateway_provider.dart';
import 'package:mosh/src/state/session_providers.dart';

/// Native saved invitations, refreshed by the DM list's existing poll owner.
final pendingInvitesProvider =
    AsyncNotifierProvider<PendingInvitesNotifier, List<InviteCreated>>(
        PendingInvitesNotifier.new);

class PendingInvitesNotifier extends AsyncNotifier<List<InviteCreated>> {
  Future<void>? _refreshing;
  bool _refreshAgain = false;
  int _generation = 0;

  @override
  Future<List<InviteCreated>> build() {
    _generation++;
    _refreshing = null;
    _refreshAgain = false;
    ref.listen(conversationListProvider(ConversationKind.dm), (before, next) {
      if (next is AsyncData<ConversationList> && before != next) {
        unawaited(refresh(background: true));
      }
    });
    return ref.watch(bridgeFacadeProvider).listPendingInvites();
  }

  /// Mutation refreshes coalesce one subsequent read; background reads join.
  Future<void> refresh({bool background = false}) {
    if (background && state.isLoading) return Future.value();
    if (_refreshing case final pending?) {
      if (!background) _refreshAgain = true;
      return pending;
    }
    final generation = _generation;
    return _refreshing = _refresh().whenComplete(() {
      if (generation == _generation) _refreshing = null;
    });
  }

  Future<void> _refresh() async {
    final startedUnder = ref;
    if (state.isLoading) {
      await AsyncValue.guard(() => future);
      if (!startedUnder.mounted) return;
    }
    do {
      _refreshAgain = false;
      final next = await AsyncValue.guard(
          () => startedUnder.read(bridgeFacadeProvider).listPendingInvites());
      if (!startedUnder.mounted) return;
      state = next;
    } while (_refreshAgain && startedUnder.mounted);
  }

  Future<InviteCreated> replace(String sessionId) async {
    final startedUnder = ref;
    final invite = await startedUnder
        .read(bridgeFacadeProvider)
        .replaceInvite(sessionId: sessionId);
    if (startedUnder.mounted) {
      startedUnder.invalidate(activeSessionProvider(sessionId));
      await refresh();
    }
    return invite;
  }

  /// Native admission must persist before the rail refresh or UI navigation.
  Future<SessionSnapshot> open(String sessionId) async {
    final startedUnder = ref;
    final session = await startedUnder
        .read(bridgeFacadeProvider)
        .openSession(sessionId: sessionId);
    if (!startedUnder.mounted) return session;
    startedUnder.invalidate(activeSessionProvider(sessionId));
    await startedUnder
        .read(conversationListProvider(ConversationKind.dm).notifier)
        .refresh();
    if (startedUnder.mounted) await refresh();
    return session;
  }
}
