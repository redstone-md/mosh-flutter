import 'package:mosh/src/features/background/android_waiting_owner.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:mosh/src/state/native_call_owner_provider.dart';
import 'package:mosh/src/state/gateway_provider.dart';
import 'package:mosh/src/features/voice_call/microphone_permission.dart';
import 'package:mosh/src/features/voice_call/camera_permission.dart';
import 'package:mosh/src/features/onboarding/first_run_provider.dart';

import 'package:mosh/src/features/conversation/conversation_call_binding.dart'
    show conversationCallBindingProvider;
import 'package:mosh/src/features/conversation/conversation_text_sends.dart'
    show maxTextCharsProvider;
import 'package:mosh/src/rust/api/conversation.dart' show maxTextChars;
import 'package:mosh/src/features/voice_call/cpal_ringtone.dart'
    show CpalRingtonePlayer;
import 'package:mosh/src/features/voice_call/android_ringtone.dart';
import 'package:mosh/src/features/voice_call/android_call_presentation.dart';
import 'package:mosh/src/features/voice_call/voice_call_binding.dart'
    show voiceCallBinding;
import 'dart:io' show Platform;
import 'package:mosh/src/state/auto_poll_provider.dart'
    show autoPollIntervalProvider, kAutoPollInterval;
import 'package:mosh/src/state/voice_call_orchestrator_provider.dart'
    show ringtonePlayerProvider;

/// Provider bindings used by the production application root: the ringtone
/// and the native call owner, the live auto-poll cadence (all default to
/// inert so `flutter test` gets no native handles and no live timer), and
/// the conversation module's call slots, which default to unbound.
final List<Override> productionOverrides = <Override>[
  if (Platform.isAndroid)
    androidCallPresentationProvider.overrideWith((ref) {
      final presentation = AndroidCallPresentation();
      ref.onDispose(presentation.dispose);
      return presentation;
    }),
  firstRunEnabledProvider.overrideWithValue(true),
  maxTextCharsProvider.overrideWith((ref) => maxTextChars()),
  ringtonePlayerProvider.overrideWithValue(Platform.isAndroid
      ? const AndroidRingtonePlayer()
      : const CpalRingtonePlayer()),
  if (_callEngine)
    nativeCallOwnerProvider.overrideWith((ref) {
      final owner =
          NativeCallOwner(ref.read(bridgeFacadeProvider), requestCallMicrophone,
              requestCamera: requestCallCamera,
              authorizeMedia: Platform.isAndroid
                  ? (microphone, camera) async {
                      final waiting = ref.read(androidWaitingOwnerProvider);
                      if (waiting == null) return false;
                      await waiting.refresh();
                      return waiting.platform.setMediaTypes(microphone, camera);
                    }
                  : null);
      ref.onDispose(owner.dispose);
      return owner;
    }),
  autoPollIntervalProvider.overrideWithValue(kAutoPollInterval),
  // The one place the conversation module's call slots meet the module
  // that fills them. Without a call engine (iOS until MOSH-77) a call would
  // connect with no media, so the slots stay unbound.
  if (_callEngine)
    conversationCallBindingProvider.overrideWithValue(voiceCallBinding),
];

/// Platforms that package the native call engine (`mosh-media/webrtc`).
final bool _callEngine = _desktop || Platform.isAndroid;
final bool _desktop =
    Platform.isWindows || Platform.isMacOS || Platform.isLinux;
