# Settings redesign

Confirmed on 2026-10-02. Work on `feat/settings-redesign`, one completed
screen at a time. Publish each verified screen for a local development build;
wait for feedback before starting the next screen.

## Presentation

Use the composition of the five settings references in `../mosh-redesign/`
with Mosh's current palette, typography and shared shapes. Settings occupy a
separate route above the preserved chat. Wide windows have a section sidebar;
narrow windows and Android have a section list followed by a detail view.
Remember the last section for the wide sidebar during the application launch,
without disk storage. Per the phone review, every narrow settings entry starts
at the section list, including after a section has been visited.

The order is Sound, Devices, Connection, Privacy, About. Short explanations
stay beside controls; longer details collapse. Consequential warnings remain
visible. Window chrome remains familiar; settings do not claim global network
connectivity.

## Delivery

1. Frame and Sound: full-screen route, return to preserved chat, responsive
   navigation, microphone/speaker cards and the existing speaker test.
2. Devices: roster and two step-by-step actions. The trusted installation
   displays a new five-minute, single-use QR invitation. The new installation
   scans it, shows a confirmation code, and the trusted installation enters
   that code to approve. Android uses `mobile_scanner`; image/link import is
   available on every platform. Update the bridge and saved pairing context.
   Reject legacy QR imports while preserving existing identities, history and
   already committed delivery/receipt records. Reuse independent keys,
   signed rosters, atomic admission and acknowledgement mechanisms.
3. Connection: automatic discovery, collapsible VPN adapter controls and real
   runtime diagnostics. Remove manual host/port and incoming-port fields.
4. Privacy: crash reporting and read receipts, both off by default. Explain
   the native minidump memory caveat and preserve consent/error handling.
5. About: actual build version and accurate private-chat/group versus public
   channel protection descriptions.

Camera/video settings, microphone testing, licences, changelog and updater
actions are separate features and are excluded from this redesign.

## First screen checks and risks

Run formatting, Flutter analysis and the Flutter suite. Cover sidebar and
narrow back navigation, preservation of the chat route/widget state, section
memory, hardware loading/error/unplugged selections and audio-test cleanup.
Inspect desktop and narrow screenshots with the production theme.

Reuse Riverpod audio enumeration/persistence and the existing ringtone seam.
No Rust API, storage or dependency changes belong to the first screen. Audio
hardware and native window behaviour still need the user's local dev build.
Record verification and the first-screen implementation in the feature guide.

## Menu review follow-up

The user approved trying adaptive selection menus on 2026-10-02: a styled
Material MenuAnchor popover on desktop and a titled bottom sheet on phones
and narrow windows. Reuse the same theme/rows for chat actions. Preserve
controlled choices, hardware/error handling and adapter application. Verify
keyboard focus/dismissal, long names and nullable default selection, then
publish on the same branch for local review before choosing another pattern.
