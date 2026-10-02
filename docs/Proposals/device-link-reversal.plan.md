# Trusted-device QR linking

The settings interview approved reversing the pairing direction, including
bridge signatures, versioned pending-exchange storage and Android camera scan.
Keep work on `feat/settings-redesign`; publish the completed Devices screen for
the next local development-build review.

## Scope and sequence

1. Public runtime/bridge tracer: the authorizing installation creates a v2 QR;
   an eligible joining installation imports it and sends its independent,
   signed descriptor. Freeze that descriptor before offering the signed roster.
   The joining installation displays a code bound to both descriptors and the
   roster; the authorizing installation enters it before the atomic addition.
2. Preserve the existing encrypted directed stream, strict signatures, signed
   roster, consumed invitation ids, compare-and-swap persistence, approval
   delivery journal and durable-save acknowledgement. Resume authenticated v2
   joining exchanges. Refuse v1 invitation imports; restore already authenticated
   v1 pending requests only for their pinned exchange until expiry, so previously
   committed deliveries/receipts still finish. Preserve identities and history.
3. Expose explicit authorizing/joining role in snapshots. Regenerate the bridge.
   Restyle the existing roster/removal view and present two step-by-step actions.
   Add Android camera scan with bundled `mobile_scanner`; image/link import
   remains available on all platforms.
4. Verify and publish the complete screen; wait for the user's build review.

## Checks and risks

Tests use the existing agreed public runtime/snapshot and bridge seams with
real encrypted persistence, independent Moss processes and isolated discovery.
Cover wrong code, descriptor substitution, another scanner attempting the same
invitation, expiry, cancellation, replay, restart and committed v1 recovery.
Keep existing linked-DM/history/removal scenarios working with the new direction.
Use production-themed responsive Flutter layout tests, actual QR encoding and
decoding, plus the native Devices UI path where its platform gate permits.

Run Cargo build, fmt, tests and clippy; bridge generation and binding drift;
Flutter formatting, analysis and tests; Android arm64 build. Desktop image/link
flows remain usable without a camera. Physical camera/audio/window behavior
still requires the user's local build.

## Completed verification

The Devices stage is implemented on 2026-10-02. Flutter analysis, formatting
and the full suite pass: 1032 tests, five existing native-library skips. The
production-themed native UI probe passes with an independent Moss process.
The full Rust suite, build, fmt and clippy pass. Regenerated bindings have no
drift. The Android arm64 debug APK includes the offline scanner model and an
optional camera hardware requirement.

Changed production line coverage is 94.6% in Dart and 94.1% in Rust; Dart branch
coverage is 88.5%. Rust branch coverage is unavailable in the stable toolchain.
Both code-review tracks have no remaining findings. Tests reproduce and cover
full-descriptor code binding and delayed approval after a newer signed removal.
Authenticated legacy delivery/restart and roster removal remain operational.

Desktop and narrow captures are checked. Publish this complete stage, then
wait for the user's local Devices review before beginning Connection. Physical
Android camera and Windows native behavior remain local verification items.
