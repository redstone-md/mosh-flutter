import 'package:mosh/src/features/conversation/conversation_call_binding.dart'
    show ConversationCallBinding;
import 'package:mosh/src/features/voice_call/voice_call_layer.dart'
    show VoiceCallLayer, startVoiceCall;

/// The voice-call module behind the conversation's call slots.
final ConversationCallBinding voiceCallBinding = ConversationCallBinding(
  start: startVoiceCall,
  // The layer draws nothing itself; the conversation only gives it
  // somewhere to live.
  overlay: (context, host) => VoiceCallLayer(
    sessionId: host.conversationId,
    l: host.l,
    onVoiceCallError: host.onError,
  ),
);
