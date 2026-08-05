import 'package:flutter_riverpod/misc.dart' show Override;

import 'package:mosh/src/features/dm/cpal_voice_playback.dart'
    show CpalVoicePlaybackFactory;
import 'package:mosh/src/features/dm/record_voice_capture.dart'
    show RecordVoiceCaptureFactory;
import 'package:mosh/src/state/voice_call_orchestrator_provider.dart'
    show voiceCaptureFactoryProvider, voicePlaybackFactoryProvider;

/// Provider bindings used by the production application root.
final List<Override> productionVoiceOverrides = <Override>[
  voiceCaptureFactoryProvider
      .overrideWithValue(const RecordVoiceCaptureFactory()),
  voicePlaybackFactoryProvider
      .overrideWithValue(const CpalVoicePlaybackFactory()),
];
