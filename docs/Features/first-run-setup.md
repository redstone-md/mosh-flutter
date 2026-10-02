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

- Name requirements, avatar scope and the meaning of changing a saved name.
- Device-link skip path and recovery during a pending exchange.
- Automatic network selection versus choosing a physical adapter.
- First-run detection for existing installations, interrupted setup and invite
  links received before setup is complete.

## Planned checks

Verify first launch, subsequent launch, interrupted setup, name restoration,
device-link success and failure, network save and restart, invite continuation,
and narrow-window layout with focused tests using `test/support/`.

Run Dart formatting, `flutter analyze` and `flutter test` after implementation.
Run Rust and binding checks if the final design requires core API changes.
