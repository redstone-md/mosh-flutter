import 'package:flutter_riverpod/misc.dart' show Override;

import 'package:mosh/src/features/conversation/conversation_call_binding.dart'
    show conversationCallBindingProvider;
import 'package:mosh/src/features/voice_call/voice_call_binding.dart'
    show voiceCallBinding;
import 'package:mosh/src/features/dm/cpal_voice_playback.dart'
    show CpalVoicePlaybackFactory;
import 'package:mosh/src/features/dm/record_voice_capture.dart'
    show RecordVoiceCaptureFactory;
import 'package:mosh/src/features/dm/cpal_ringtone.dart'
    show CpalRingtonePlayer;
import 'package:mosh/src/state/auto_poll_provider.dart'
    show autoPollIntervalProvider, kAutoPollInterval;
import 'package:mosh/src/state/voice_call_orchestrator_provider.dart'
    show
        ringtonePlayerProvider,
        voiceCaptureFactoryProvider,
        voicePlaybackFactoryProvider;

/// Provider bindings used by the production application root: the native
/// voice factories, the live auto-poll cadence (both default to inert so
/// `flutter test` gets no native handles and no live timer), and the
/// conversation module's call slots, which default to unbound.
final List<Override> productionOverrides = <Override>[
  voiceCaptureFactoryProvider
      .overrideWithValue(const RecordVoiceCaptureFactory()),
  voicePlaybackFactoryProvider
      .overrideWithValue(const CpalVoicePlaybackFactory()),
  ringtonePlayerProvider.overrideWithValue(const CpalRingtonePlayer()),
  autoPollIntervalProvider.overrideWithValue(kAutoPollInterval),
  // The one place the conversation module's call slots meet the module
  // that fills them.
  conversationCallBindingProvider.overrideWithValue(voiceCallBinding),
];
