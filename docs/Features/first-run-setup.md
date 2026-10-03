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
different Mosh user. Cancelling the import or pending link returns to the setup
device choices; a failed cancellation retains the current flow for retry. A
linked identity or committed delivery remains visible if approval wins the race.
See [device linking](device-linking.md).

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
`fg1` #ECEEEA and `fg2` #A8AEB0. Typography uses the app's bundled Inter
(`assets/fonts/`, OFL). Its balanced metrics keep labels optically centered in
buttons and step markers; the former Segoe UI fallback sat 1–2px low.
Wide windows use the reference's illustration on the left and controls on the
right for all three steps. Narrow windows stack these blocks. The outer card
fills the available viewport below the titlebar with the same inset on all four
sides. Its centered content is capped at 640px when stacked and 1160px in two
columns; the form column retains its 480px maximum width on desktop.

Each step has one primary task heading, then its explanation, directly above
its controls. Wide layouts follow the reference: the heading starts the form
column, left-aligned, while the left column holds artwork and its caption.
Stacked layouts center the heading above the artwork. The heading uses the
existing 23px/600 type token; desktop illustration captions use the secondary
19px token in primary ink with a muted body. Narrow screens omit these
repeated captions. The step indicator is one continuous track joining its
markers. The name step starts directly with the name field below its heading
and explanation, without an initials avatar or its reserved spacing. Settings
retains the live initials preview in the shared name editor. The name step keeps
its factual encryption note after the
form in narrow layouts with room for supporting content. The two initial device
choices share a neutral outlined
style; a linked profile gets one filled Continue action. Back is secondary.

Setup reuses native Flutter controls and the existing `MoshSelect`. Its local
theme gives field text the 14px body token, every action label 15px/600, and
filled, outlined and Back actions a 48px minimum height. The setup style is the
receiver of `ButtonStyle.merge`: the app theme's `styleFrom` fills every slot,
so merging the other way silently restored the 12px app label. Buttons can grow
for wrapped labels and enlarged text. Settings keeps its existing density.

The card has equal outer padding within the safe area below the titlebar.
Its content centers horizontally and vertically inside the padded card.
`SetupSizing` reads the viewport's width and height, including the reduced
height when a keyboard opens. It adjusts decorative image sizes and spacing.
Progress circles grow with their text instead of clipping enlarged numbers.
Where the step labels would crowd, the indicator shows all three markers and
only the current step's label. It never squeezes every label into a narrow slot.
Text and controls keep their native readable sizes; the layout never scales the
entire form with a paint transform.

Two columns require 740px of content width at normal text scale; enlarged text
raises this threshold. A stable `Flex` changes direction and fit, preserving
unsaved names, imported links and adapter selections across resizing. Stacked
illustrations are limited to 120px for name/network. In stacked viewports below
600px of available height, artwork and secondary captions yield space to the form.
The former fixed-height divider no longer sets a minimum card height.

Spacing follows a 4px grid: compact/regular outer padding 12/32px, card padding
16/32px, section gaps 16/32px and column gaps 32/48px. Heading and explanation
are grouped with 12px; controls follow with 24px. Control text remains readable
and respects system text scaling.
The shared window titlebar also accounts for text scale when replacing the
Peer status label with its compact icon, so completion does not expose an
overflowing chat header at 200% text size.

The scroll view inside the card gives its content the inner viewport's minimum
height, following
[Flutter's constrained scroll layout](https://docs.flutter.dev/cookbook/lists/spaced-items).
It centers content that fits, and scrolls larger content for small windows,
enlarged text, keyboard input or expanded device-link states. The outer frame
stays stationary and keeps its insets even while the content scrolls. The
minimum-height constraint permits growth without fixed text heights or
intrinsic measurement. Regression tests
require all three default steps to fit at 1280×680 and 900×700 in Russian, and
verify equal insets, content centering, internal scrolling, image resizing,
name preservation and keyboard access.

The three illustrations are bundled in `assets/onboarding/` with their original
RGBA transparency. Their generation prompts are recorded in
[the asset notes](../../assets/onboarding/README.md).

The titlebar, card, progress indicator and responsive frame stay mounted across
steps. Only the body below progress participates in the
[shared-axis transition](https://pub.dev/documentation/animations/latest/animations/SharedAxisTransition-class.html):
the outgoing body fades for 120ms while the incoming body appears over 240ms,
using `Cubic(.23, 1, .32, 1)` and a 3% horizontal slide. Back reverses direction.
The glass illustration independently scales from 97% to 100%. Progress markers
blend their highlight and checkmark over 120ms. The shell never fades or slides;
outgoing and incoming content overlap instead of leaving a blank frame.

`SetupStepTransition` creates each visited panel once and then keeps it offstage.
Returning preserves unsaved names, imported links and adapter selections. Hidden
panels exclude pointers, focus, semantics and child tickers; the visible panel
pauses input only during its entrance. Native owners remain the existing shared
providers. Interrupted transitions retarget from their current opacity/position.
Initial/restored steps, same-step updates, resize and save errors do not replay
motion. The cache lasts only for this wizard and writes no additional preferences.

`SetupStableLayout` reserves the first body's natural height plus up to four
section gaps in two columns, or eight in stacked layouts, within the viewport
budget. The extra stacked reserve accommodates the shorter name form without
shifting the shell when taller steps enter. This keeps default-step card geometry
and progress coordinates steady. Expanded import/error content can grow beyond
the baseline without making that extra height permanent. A viewport, text-scale
or locale change remeasures the baseline while retaining field state. This uses
ordinary layout constraints; animation changes only opacity, translation and
the illustration's scale. A loading device snapshot uses a compact spinner
until its existing settings/import UI is available.

Platform reduced motion retains the fade and removes translation and scale,
including preference changes during a transition. New transitions use Flutter's
default shortened fade so controls become available on the next frame. The wizard
precaches all three illustrations. Advancing the name form confirms its save
by showing the device step; Settings retains its saved confirmation.

Size exceptions: `_DisplayNameFormState.build` and `_FirstRunDeviceStepState.build`
exceed the 50-line function budget because each declares one localized form.
Protocol and persistence logic stay outside these builds; their containing types
and files stay within the 200/400-line budgets. Layout, theme and step-heading
logic are separate small components.
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

Restored-step motion checks observe the first painted frame and an intermediate
frame before settling animations. Pointer-blocking checks tap the outgoing
Back action, whose accidental execution would navigate to a different step.
Preview PNG exports support manual inspection; they do not compare pixel output.

Run Dart formatting, `flutter analyze` and `flutter test --coverage`. The tests
verify translucent pixels and transparent margins in all three image assets.
Rust APIs, generated bridge bindings and native wire/storage formats are unchanged.

Validation on 2026-10-02: full Flutter suite passed 1,125 tests with five existing
skips; the final 51 focused setup tests passed, and analysis found no issues.
Focused setup tests collected 98% line and 91% branch coverage for the new code
using `--branch-coverage`. Tests cover all three steps with enlarged Russian text
on desktop and narrow screens. Windows relaunch and Android camera behavior use the
existing tested seams here; this change has not been exercised on native devices.

Responsive layout validation on 2026-10-03: analysis found no issues and the full
Flutter suite passed 1,135 tests with the same five skips. Nine regression cases
cover short windows, vertical centering, illustration sizing, unsaved names
during resizing and keyboard access. Changed production files collected 99.5%
line and 98.4% branch coverage. Rendered previews were checked for all three
steps in short desktop windows, a taller desktop window and a narrow phone
viewport. The layout fix has not yet been checked on a physical Windows device.

The hierarchy pass adds 48 viewport/text-scale cases for all three steps, from
320×568 and phone landscape through tablets, short desktops and 2560×1440,
at normal and 200% text size. These cases exercise the next action and completion
into chats. Additional cases check heading order, equal device-choice emphasis,
linked-profile continuation, Tab/Enter navigation, retryable save errors and
preserved imported links and adapter selections. Flutter's text-contrast,
labeled-target and Android tap-target guidelines pass on all three default steps.

Final hierarchy validation on 2026-10-03: analysis found no issues, and the full
suite passed 1,197 tests with five existing skips. Coverage for the nine changed
production files was 98.5% line and 90.8% branch. The optional preview run passed
79 layout/state cases with readable sans-serif and Material icon fonts; rendered
desktop, tablet, phone, small-window and error/import states were inspected.
The final 320×568 name preview includes the full card and primary action without
the optional illustration or encryption caption.

Reference-alignment pass on 2026-10-03 bundled Inter, fixed the dropped setup
button label (12px → 15px), reduced actions to 48px, moved the wide task heading into the
form column, restored primary ink to the welcome caption and joined the step
track. The onboarding suite and the 48-case viewport matrix pass with previews
rendered at 1280×680, 900×700, 1920×1080, phone and 200% text. Native Windows verification
remains outstanding; the previews exercise the real Flutter tree in widget tests.

Content-transition validation on 2026-10-03: analysis and formatting are clean;
the full Flutter suite passed 1,219 tests with five existing skips. Two additional
round-trip cases passed afterward, covering unfinished device import and unsaved
adapter selection. The 23 focused motion/state cases also cover interruptions,
reduced motion, semantics, keyboard access, resize, save errors and ticker
disposal. Shell regression tests verify the same card render object, progress
element and screen coordinates throughout default-step transitions on desktop
and phone. Actual Flutter frames were rendered every 16ms for all three
transitions at 1280×680 and 390×844. The five changed production files collected
99.2% line and 92.5% branch coverage. Frame pacing on a physical Windows device
remains unmeasured.

Name-step simplification on 2026-10-03 removes the avatar and its trailing gap
from setup. Formatting and analysis are clean; 174 focused onboarding/Profile
tests passed with rendered previews, including the 48 viewport/text-scale cases
and persistent-shell transitions. The three changed production files collected
97.5% line and 98.1% branch coverage. Desktop and phone previews were inspected.

Equal-inset validation on 2026-10-03: 184 focused onboarding/Profile tests passed
with previews, including the 48 viewport/text-scale cases. Nine regression cases
verify equal frame insets on all three steps at desktop and phone sizes; a tenth
checks internal scrolling with 200% text in a small window. Persistent-shell,
resize, keyboard and accessibility checks pass. Formatting and analysis are clean.
Both changed production files collected 100% line and branch coverage. Desktop
and phone previews were inspected; physical Windows verification remains pending.

Motion-test review on 2026-10-03 strengthens restored-frame and outgoing-pointer
checks. In an isolated worktree, the old checks passed with an unwanted initial
entrance and with clickable outgoing controls; the revised checks rejected both
faults. All 20 motion tests pass on the unchanged production behavior. The full
Flutter suite passed 1,232 tests with five existing skips; formatting and analysis
are clean.
