# IVO-23: independent voice-call controls

## Agreed scope

- An independent desktop call window on Windows, macOS and Linux, using
  `desktop_multi_window`. All call phases remain nonmodal.
- Main-engine Riverpod state owns signaling, capture, playback and ringtone.
  The child engine receives display data and sends call-id-bound commands.
- Navigation through DMs, groups, channels and Settings preserves the call.
  A compact application-level strip provides controls and reopens the window.
- Minimize preserves the call. Close declines an incoming call, cancels an
  outgoing call or ends an active call.
- Use the supplied original `29_cipher_stream` recording through the existing
  CPAL output-device selection. Keep the media protocol unchanged.
- Commit the implementation on `feat/call-ui`.

## Implementation and checks

1. Regression at the existing widget/bridge seams: conversation actions remain
   usable during a call, and navigation controls the original DM.
2. Centralize ringtone and timeout lifetime in call state. Serialize audio
   replacement and discard old setup/control completions.
3. Add the native-window adapter, safe display protocol, child entrypoint and
   runner registration. Reuse existing call controls and localization.
4. Replace the tone with embedded PCM from the supplied WAV. Check sample-rate
   adaptation, channel conversion, looping and timeout behavior.
5. Exercise two native clients through public app actions and the existing
   integration harness. Run Flutter and Rust checks, review against the start
   commit `2d5023af385b26b7551822cc893e3c80892c1731`, then commit.

Risks are separate Flutter-engine plugin registration, asynchronous window
creation after a call has ended, and teardown completing after a replacement
call starts. Tests observe public actions and resource factories. Native UI
checks use real Moss and independent installation processes.

## Implementation decisions

- Windows and macOS retain `desktop_multi_window`. Linux uses a separate Flutter
  process behind the same window interface. On Flutter 3.44.7, a second GTK engine
  crashed with GLX `BadAccess` when opening or destroying windows under the default
  OpenGL renderer. Software rendering passed the media scenario but is unsuitable
  as a product requirement. Process isolation lets each renderer own its EGL
  resources; audio remains in the main process. Stdio carries only display data
  and call-bound commands.
- Reuse GoRouter's provided stateful shell rather than constructing a second
  shell with the same key. Settings remain pushed above the chat. Remembering
  their default section after declarative route removal runs outside widget build.
- Schedule polling-driven snapshot invalidation after Riverpod's current batch.
  Sending a message refreshes both snapshot and list; a completed list must not
  rebuild the same snapshot twice in that batch.
