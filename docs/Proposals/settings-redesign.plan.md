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
3. Connection: collapsible VPN adapter controls. Remove manual host/port and
   incoming-port fields. The user's screen review removes discovery and
   diagnostics/status cards; automatic discovery continues without controls,
   and version information stays in About. The user's follow-up replaces
   Apply/Reset with a VPN bypass switch and explicit saved on/off state.
   Keep the refresh icon beside the adapter selector and existing relaunch.
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
The user accepted this pattern after comparing a standalone inline example.

## VPN restart correction

The local review found that the bypass switch read the current process binding
instead of saved consent, and startup did not apply that consent to Moss.
Read the existing consent API in settings; restore and resolve the saved
adapter once before shared runtime nodes start. Preserve per-call overrides,
the current node until restart, and startup fallback for unavailable hardware.
No dependency, schema or public bridge change is needed. First reproduce with
separate saved/runtime states and independent native processes, then verify
Flutter, real Moss startup, Rust formatting/tests/clippy and Android arm64.

## Privacy screen

Use two shared toggle cards for crash reporting and read receipts. Reuse
SettingsSurface, SettingsIcon and AsyncSwitchTile; keep the existing reporter,
bridge reads/writes, default-off consent, pending guards and rollback.
Keep short explanations beside switches, collapse longer details with Material
ExpansionTile, and keep the native stack-memory warning outside the disclosure.
Persist each disclosure with a separate PageStorage key.

The task is choosing what leaves this device. Switches lead the hierarchy;
the icon plates, graphite surfaces, moss accent and muted explanatory text
follow the approved Mosh settings. Use 20px card padding and 16px card gaps,
theme title/body styles and existing rounded surfaces. Adapt the icon/toggle
header for phones and enlarged text instead of squeezing the explanation.

Check existing SDK and receipt write seams, missing reporting availability,
loading/error/rollback, disclosure independence and section return. Inspect
desktop, Android-size and 320px/enlarged-text captures. Run formatting, Flutter
analysis/tests/changed-line coverage and an Android arm64 debug build. No
native APIs, schemas, dependencies or reporting data flows change here.
