/// How the voice-call module fills the conversation module's call slots.
///
/// The conversation module declares what it needs from a call (see
/// `conversation_call_binding.dart`) and never imports this module; this is
/// the adapter that answers it. The composition root binds the two, and a
/// test that wants a real call layer binds the same thing.
library;

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
