# First-run setup

Status: implemented. The design interview and local preference format were
approved on 2026-10-02.

## Agreed scope

- Show the setup wizard once on first launch. Later launches open conversations.
- Keep name, device linking and network preferences accessible in Settings.
- Follow the three reference screens in `../mosh-redesign`: name, device, network.
- Use a large card, step indicator, illustration on the left and form on the
  right. Stack these blocks vertically in narrow windows.
- Generate three separate transparent PNG illustrations: shield with orbits,
  laptop with phone, and shield with network symbols. Use dark translucent glass,
  green light and thin orbits. Keep text, buttons and forms in Flutter.
- Write copy that matches real privacy guarantees. Public Moss trackers prevent
  promising absence of metadata.
- Require a display name, restore it after restart, and allow editing in Settings.
  Use initials for the avatar. Name changes apply to new conversations; existing
  conversations keep their names.
- Offer "This is my first device" and "Connect to an existing profile". The
  first choice continues setup; the second reuses QR/image/link import and
  approval on the trusted installation.
- Use automatic networking by default. Choosing a physical adapter is optional
  and explains that it routes Mosh traffic around the VPN. Explain any required
  restart before applying it.
- Skip setup on existing installations with conversations or linked devices.
- Hold an incoming conversation invitation until setup finishes, then reopen it.
- Restore the name and last saved step after closing the app. Persist them in a
  separate local preference file. Do not put QR secrets or invitations in it;
  an invitation must be reopened after the application process exits.
- Before approval, a pending device link can be cancelled to continue
  independently. After approval, preserve the linked identity and complete its
  delivery. If approval races cancellation, show the resulting linked profile.
- Save setup completion before Windows relaunch. Other platforms explain that
  the user must fully close and reopen Mosh to apply the adapter.

## Components and persistence

`MoshApp` wraps the router in `FirstRunGate` before mounting conversations or
starting their auto-poll loop. The production provider overrides enable the
gate; isolated app tests explicitly opt in with scripted disk/native seams.
`OnboardMenu` remains the conversation launcher.

`FirstRunStore` writes `first-run.json` in the existing application support
directory. Version 1 has `displayName`, `step` and `completed`; names are trimmed
and limited to 64 characters. A temporary file is flushed and renamed into place,
and writes are serialized. Save failures keep the form available for retry;
unknown or corrupt records do not silently become a fresh installation.

`FirstRunController` restores the name into the existing invite flow once at
startup. Settings adds a Profile section with the shared `DisplayNameForm` and
initials `Avatar`. Name edits persist before updating the invite flow and retain
its port, peer and pending invite state.

Device linking already supports importing a trusted installation's QR image or
private link on desktop and camera scanning on Android. Approval happens on the
trusted installation. Installations with existing conversations cannot adopt a
different Mosh user. See [device linking](device-linking.md).

The existing network settings save a physical adapter choice. The running node
applies it after restart; Windows offers app relaunch. A global VPN prompt can
appear above any route on later launches. During the first-run launch, the wizard
owns this choice and suppresses the duplicate global prompt.
Automatic VPN/default-route detection currently works on Windows only. Other
platforms must not claim that a VPN was detected; they require a manual app
restart to apply a changed adapter.

Reading the device-link snapshot starts Moss, even on a fresh installation, so
the network step cannot claim that a saved adapter is already active. Existing
conversation reads must succeed before an installation is classified as empty.
Confirmed conversation or device history skips setup even if another read fails.
Preserve restored joining and committed delivery states.

## Layout and assets

Use the existing palette: `bg0` #0B0C0D, `bg1` #111315, `moss` #B7D84A,
`fg1` #ECEEEA and `fg2` #A8AEB0. Typography uses the shared platform font stack.
The card follows the reference's split composition for name and network; device
linking uses the reference's centered illustration and form. At narrow widths,
the illustration and form stack vertically. Setup's primary buttons are 52px.

The three illustrations are bundled in `assets/onboarding/` with their original
RGBA transparency. Their generation prompts are recorded in
[the asset notes](../../assets/onboarding/README.md).

Size exception: `SetupFrame._illustration`, `_DisplayNameFormState.build`, and
`_FirstRunNetworkFormState.build` exceed the 50-line function budget because they
declare localized widget trees. They contain no protocol or persistence logic;
their containing types and files stay within the 200/400-line budgets.
Test registration functions enumerate independent cases and exceed the function
budget; individual test callbacks remain small.

## Known limits

An older standalone installation with no conversations or device-link history
is indistinguishable from a fresh installation through the existing APIs and
receives setup. First-run classification also recognizes org records, revoked
devices and active linking state. Native construction errors can be cached for
the process lifetime; the load error offers retry and explains when to restart.

## Checks

Verify first launch, subsequent launch, interrupted setup, name restoration,
device-link success and failure, network save and restart, invite continuation,
and narrow-window layout with focused tests using `test/support/`.

Run Dart formatting, `flutter analyze` and `flutter test --coverage`. The tests
verify translucent pixels and transparent margins in all three image assets.
Rust APIs, generated bridge bindings and native wire/storage formats are unchanged.

Validation on 2026-10-02: full Flutter suite passed 1,125 tests with five existing
skips; the final 51 focused setup tests passed, and analysis found no issues.
Focused setup tests collected 98% line and 91% branch coverage for the new code
using `--branch-coverage`. Tests cover all three steps with enlarged Russian text
on desktop and narrow screens. Windows relaunch and Android camera behavior use the
existing tested seams here; this change has not been exercised on native devices.
