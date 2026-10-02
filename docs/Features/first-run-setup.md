# First-run setup

Status: design interview in progress. Implementation has not started.

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

## Existing behavior and components

The app currently opens `/sessions` without a setup gate. `OnboardMenu` is a
conversation launcher, and `inviteFlowProvider` keeps the entered display name
only for the current process. Settings has no persistent profile name or avatar.

Device linking already supports importing a trusted installation's QR image or
private link on desktop and camera scanning on Android. Approval happens on the
trusted installation. Installations with existing conversations cannot adopt a
different Mosh user. See [device linking](device-linking.md).

The existing network settings save a physical adapter choice. The running node
applies it after restart; Windows offers app relaunch. A global VPN prompt can
appear above any route and must be coordinated with the wizard's network step.

## Open decisions

- Restoring progress after interrupted setup.
- Leaving a pending device-link exchange to continue as the first device.
- Finishing setup when applying the network choice requires restart.

## Planned checks

Verify first launch, subsequent launch, interrupted setup, name restoration,
device-link success and failure, network save and restart, invite continuation,
and narrow-window layout with focused tests using `test/support/`.

Run Dart formatting, `flutter analyze` and `flutter test` after implementation.
Run Rust and binding checks if the final design requires core API changes.
