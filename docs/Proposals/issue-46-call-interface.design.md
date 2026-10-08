# Issue 46: call interface and motion

Design brief for the [agreed video-call plan](issue-46-video-calls.plan.md).
The user selected `interface-design` for the interface and `transitions-dev`
for animation. This document translates those instructions to Flutter and the
existing Mosh components. No UI implementation or visual verification is claimed.

## Product context and direction

The person starts a call from a desktop DM, keeps messaging or changes chats
while talking, and may answer on a different linked installation. They need to
know who they are connected to, what their own devices are sending, and how to
stop sending or end the call. Consent and an uninterrupted conversation lead
the interface; route details and codec diagnostics stay secondary.

- Domain concepts: private DM, linked installation, selected answering device,
  local capture consent, user occupancy, Moss route and reconnecting call.
- Color world: the existing near-black window, graphite control surfaces,
  off-white readable text, moss-green DM/primary action, amber interruption,
  coral termination and blue informational state. These are Mosh's current
  tokens, not a new palette for calls.
- Signature: the same call and capture choices remain visible in its native
  window and the main-view strip while the person moves between conversations.
  Linked devices ring together, but only the selected installation carries media.
- Avoid an equal-size meeting grid; this DM has one remote participant and a
  smaller local preview. Avoid a separate colorful call theme; inherit Mosh's
  surfaces and semantic colors. Avoid decorative network/security badges;
  display only the runtime states that the application can establish.

The direction extends the current call window and compact strip. A connected
remote video leads the window. When video is absent, the contact and plain call
state lead it. Controls stay visible and in a stable order so camera and hang-up
do not move when the remote camera changes.

## Working brief

| Choice | Direction and reason |
| --- | --- |
| Intent | Desktop DM participants must talk, retain messaging and control capture without managing network configuration. |
| Hierarchy | Remote video or contact identity is primary; local preview and capture choices are secondary; route/codec details are optional. |
| Palette | Read MoshColors and ColorScheme roles. Moss marks answer/primary action; danger marks decline/end; warn marks recoverable loss or occupancy conflict. |
| Depth | Quiet tonal layers separate stage, controls and menus; existing hairlines establish boundaries. Avoid decorative shadows over video. |
| Surfaces | bg0 window/stage, bg1 controls/strip, bg2 raised panels, bg3 menu surface. Text over changing video needs an opaque themed plate. |
| Typography | Keep bundled Inter and the existing TextTheme. Contact uses headlineSmall/Medium where space permits, controls use labels, status uses bodySmall. Timer uses kLiveNumberFontFeatures. |
| Spacing | Keep the 4px grid. Use 16px around the control region, 8px within related actions, and 16px between groups. Call buttons retain 48px targets. |

Small selectors use `MoshShapes.control`; menus use `MoshShapes.menu`.
The stage can fit the available window without adding ornamental cards. Keep
video aspect ratio and use a neutral letterbox rather than stretching faces.
Local preview is subordinate to the remote stage and must not cover controls,
captions or an interruption message.

## Existing components to extend

| Existing component | Role in the video feature |
| --- | --- |
| [CallView](../../lib/src/features/voice_call/call_view.dart) | Shared phase/status/actions for the standalone window and compact main strip. Add video presentation without duplicating admission or media ownership. |
| [CallModalCard](../../lib/src/features/voice_call/call_modal_card.dart) | Preserve compact layout and modal semantics/focus behavior; adapt the standalone composition to video. |
| [CallButton](../../lib/src/features/voice_call/call_button.dart) | Retain Material keyboard behavior, tooltip and 48px target; add camera and use semantic foreground/background roles. |
| [MoshSelect](../../lib/src/app/mosh_select.dart) | Camera, microphone and speaker selection; keep its existing menu, keyboard and narrow-layout behavior. |
| [Mosh dialog route](../../lib/src/features/shared/mosh_dialog_route.dart) | Permission guidance and other actual modal content; reuse focus, safe areas and reduced-motion-aware transitions. |
| [ContextualIconSwitcher](../../lib/src/features/shared/contextual_icon_switcher.dart) | Camera/microphone glyph changes; reuse the component with call-specific timing where necessary. |
| [PressScale](../../lib/src/features/shared/press_scale.dart) | Existing optional press feedback; disable transforms when reduced motion is requested. |
| [Call window app](../../lib/src/features/voice_call/call_window_app.dart) | Presentation-only process; preserve its command identity checks and main-process authority. |

Current call views contain hardcoded card/action colors. When implementing this
feature, replace those feature-local values with existing semantic roles. A
filled moss or danger action uses its theme's dark foreground; white text/icons
on every colored fill would bypass the existing contrast decision. Required
status text uses fg1/fg2/fg3, never fg4. Avoid a second theme, picker or toast stack.

## Views and states

| View/state | Visible content and behavior |
| --- | --- |
| DM entry | Existing voice action plus a video action with an accessible label. Both enter the same call owner and respect known occupancy. |
| Outgoing video | Contact identity, ringing state and local camera preview. Preview is local; outgoing media waits for confirmed answer. Camera failure keeps voice available. |
| Incoming | Contact identity, accept/decline and receiving camera off. No remote video before confirmation; answering does not grant camera consent. |
| Answer awaiting confirmation | Show the pending action without claiming connection. Preserve terminal controls and the existing serialized close behavior. |
| Connected video | One remote stage, small local preview if enabled, stable microphone/camera/device/end controls and a tabular timer. |
| Connected without video | Contact identity and audio call state occupy the same stage; camera control remains available. Distinguish remote camera off from media still connecting. |
| Receive-only | Keep the remote stage and output audio. Mark missing/denied microphone or camera as unavailable and offer the relevant permission/device action. |
| Device unplugged | Show which capability is unavailable; retain other sending/receiving capabilities. A reconnect must preserve explicitly disabled capture choices. |
| Weak route | Plain status explains reduced/paused video; audio remains the priority. Do not display a frozen frame as current live video. |
| Reconnecting | Show a visible connection state during the agreed 15-second recovery window. Keep end available. Clear or label stale imagery. |
| Occupancy conflict | Show an amber call-bound message; explain that existing calls continue and new calls are blocked until they end. No automatic hang-up action. |
| Child-window failure | Main-view strip remains usable and can restore the window. Media lifetime and capture choices remain with the main process. |
| Ended or refused | Clear preview/frame buffers and transient UI for that call; stop ringing and follow the existing window/strip lifecycle. |

The compact strip retains origin contact, current call/capture state, microphone,
camera, end and restore controls. Navigation to the origin DM remains available.
At narrow widths, preserve those controls and truncate optional metadata before
removing actions. If one row cannot fit, move contact/status above the actions
rather than shrinking their targets. Device selectors live in the restored
window. Expanding or restoring presentation must not restart capture or
negotiate another call.

Keep the current close/Escape semantics for the call phase and the 30-second
no-answer timeout. A minimized window keeps microphone/camera choices. Do not
infer camera state from whether a preview widget is mounted.

## Motion mapping

The selected skill supplies web references. Mosh already uses its modal timing
in [MoshDialogMotion](../../lib/src/features/shared/mosh_dialog_motion.dart).
Use Flutter animation primitives and existing components; a CSS bundle or web
motion dependency is not part of this implementation.

| Element | Flutter direction | Purpose |
| --- | --- | --- |
| Actual modal content | Existing 250ms open / 150ms close, scale .96 to 1, Cubic(.22, 1, .36, 1). | Preserve the app's existing modal behavior. |
| Device menu | 250ms open / 150ms close with smooth-out curve and an origin at its trigger; restrained scale .97 opening / .99 closing when supported by the shared menu. | Connect the menu to the control without replacing MenuAnchor behavior. |
| Camera/microphone icon swap | 250ms with ease-in-out; reuse the switcher's small fade/scale rather than large glyph travel. | Explain a discrete capture change in the existing button slot. |
| Call status replacement | 150ms ease-in-out with at most 4px travel. Use a stable text slot; no blur over video. | Make phase changes legible without moving controls. |
| Tooltip | About 80ms delay, 150ms enter, 50ms exit, scale .98 to 1 with ease-out; use the existing Tooltip primitive. | Give infrequent icon actions readable labels. |
| Press feedback | Retain the existing optional .96 / 100ms PressScale behavior. | Match other Mosh controls; the skill has no required replacement for this usage. |
| Timer, incoming frames and codec counters | Immediate updates, stable tabular timer width. | Frequent updates must not replay decorative transitions. |

These are usage-based translations, not copies of the CSS implementation.
`ContextualIconSwitcher` currently fixes its curve to easeOutCubic and defaults
to 160ms. If implementing the 250ms/ease-in-out call mapping needs an additional
parameter, preserve existing defaults for other consumers. Keep all call-motion
values in one small feature policy; do not distribute new literals among views.

Animations affect presentation only. Mute/camera-off/end act immediately in the
native owner; no command waits for a closing or icon animation. A call-window
route transition must not scale or blur every live video frame. Use opacity and
small transforms for discrete UI changes; avoid looping rings, shimmer and bounce.

Read `MediaQuery.disableAnimationsOf(context)` in the call presentation. Reduced
motion removes travel/scale and uses immediate state changes. Existing dialogs
already do this; icon/press wrappers need the same consideration at composition.
Rapid phase changes, close during an animation and restore after termination
must leave correct controls/focus rather than completing an old transition.

## Presentation boundary and truthful state

The main process owns the engine, capture consent, devices, keys and selected
participants. The child receives call-bound presentation state and bounded
decoded frames; it sends commands tagged with the current call identity. It
must not initialize another engine or share an assumed Flutter texture ID from
the main process.

Use a bounded latest-frame presentation queue for each displayed track. Drop
obsolete frames rather than delaying the conversation. Bind buffers to the call
generation and release them when a track, window or call ends. Select the IPC
and pixel/texture mechanism through the native feasibility probe; stdio JSON is
the existing control channel, not a verified 720p30 pixel carrier.

Controls distinguish chosen state from availability and actual sending state.
For example, a camera the user disabled is different from an enabled choice
whose device disappeared. The latter does not authorize changing the former
when hardware returns. Native status is the source for warnings and diagnostics.

Optional diagnostics may report the negotiated codec, encoder implementation,
known hardware/software state and route. Never infer them from OS support, a
selected setting or a spinning icon. Automatic Moss discovery needs no host,
port, TURN/STUN or relay-bandwidth fields in the normal call flow.

## Review checklist

- Review outgoing preview, incoming consent, active video, audio-only,
  receive-only, reconnecting and conflict states at desktop and minimum widths.
- Verify one focal point: remote stage/contact first, capture controls second,
  diagnostics last. The local preview must remain secondary.
- Check long names, localization, text scaling and narrow-window control access.
  Avoid clipping focus rings or allowing menus behind the video surface.
- Exercise Tab/Shift-Tab, Enter/Space, Escape, focus return and named/toggled
  semantics. Unavailable controls explain the reason and recovery action.
- Verify contrast on stable plates and actual video backgrounds. Use icons and
  wording with semantic color, so state does not depend on hue alone.
- Verify reduced motion, rapid icon/status changes and close/restore races.
  Camera-off must stop capture immediately even while its glyph animates.
- Observe frame age and UI responsiveness while video is live. Screenshot review
  complements native quality tests and does not establish media correctness.

The existing system stays the source of tokens and shared interaction behavior.
Any reusable patterns saved later in `.interface-design/system.md` should refer
to those sources rather than creating another set of competing values.
