import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mosh/src/features/conversation/conversation_state.dart';
import 'package:mosh/src/features/shared/conversation_action_error.dart';
import 'package:mosh/src/gateway/conversation_target.dart';
import 'package:mosh/src/gateway/gateway.dart';
import 'package:mosh/src/state/conversation_providers.dart';
import 'package:mosh/src/state/gateway_provider.dart';

final conversationTextSendsProvider = NotifierProvider.family<
    ConversationTextSends, ConversationTextSendState, AnyConversationTarget>(
  ConversationTextSends.new,
);

class FailedConversationSend {
  const FailedConversationSend(this.body, this.error);
  final String body;
  final ConversationActionError error;
}

class ConversationTextSendState {
  const ConversationTextSendState({this.pending = 0, this.failures = const []});
  final int pending;
  final List<FailedConversationSend> failures;

  FailedConversationSend? get firstFailure => failures.firstOrNull;

  ConversationTextSendState copyWith({
    int? pending,
    List<FailedConversationSend>? failures,
  }) =>
      ConversationTextSendState(
        pending: pending ?? this.pending,
        failures:
            failures == null ? this.failures : List.unmodifiable(failures),
      );
}

/// Serializes native admission, never delivery or editing. Native message rows
/// own delivery status; only calls refused before admission need a local Retry.
class ConversationTextSends extends Notifier<ConversationTextSendState> {
  ConversationTextSends(this.target);
  final AnyConversationTarget target;
  Future<void> _tail = Future.value();
  int _lifetime = 0;

  @override
  ConversationTextSendState build() {
    _lifetime++;
    _tail = Future.value();
    ref.onDispose(() => _lifetime++);
    return const ConversationTextSendState();
  }

  Future<ConversationSendOutcome> send(String body) {
    if (body.isEmpty) {
      return Future.value(ConversationSendOutcome.nothingToSend);
    }
    final lifetime = _lifetime;
    final gateway = ref.read(gatewayProvider);
    state = state.copyWith(pending: state.pending + 1);
    final result = _tail.then((_) => _admit(gateway, body, lifetime));
    _tail = result.then((_) {});
    return result;
  }

  Future<ConversationSendOutcome> retry() {
    final failed = state.firstFailure;
    if (failed == null) {
      return Future.value(ConversationSendOutcome.nothingToSend);
    }
    state = state.copyWith(failures: state.failures.sublist(1));
    return send(failed.body);
  }

  bool _active(int lifetime) => ref.mounted && lifetime == _lifetime;

  Future<ConversationSendOutcome> _admit(
    Gateway gateway,
    String body,
    int lifetime,
  ) async {
    if (!_active(lifetime)) return ConversationSendOutcome.nothingToSend;
    try {
      await gateway.send(target, body: body);
      if (_active(lifetime)) refreshConversation(ref.invalidate, target.ref);
      return ConversationSendOutcome(sent: true, body: body);
    } catch (error) {
      if (_active(lifetime)) {
        state = state.copyWith(failures: [
          ...state.failures,
          FailedConversationSend(body, ConversationActionError.of(error)),
        ]);
      }
      return ConversationSendOutcome(sent: false, body: body);
    } finally {
      if (_active(lifetime)) state = state.copyWith(pending: state.pending - 1);
    }
  }
}
