import 'package:mosh/src/features/conversation/conversation_call_binding.dart'
    show ConversationCallBinding;
import 'package:mosh/src/features/voice_call/voice_call_layer.dart'
    show startVoiceCall;
import 'package:flutter/widgets.dart';

/// The voice-call module behind the conversation's call slots.
final ConversationCallBinding voiceCallBinding = ConversationCallBinding(
  start: startVoiceCall,
  // The app-level host renders call controls across every route.
  overlay: (context, host) => const SizedBox.shrink(),
);
