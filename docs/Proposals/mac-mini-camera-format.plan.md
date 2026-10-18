# Mac Mini USB camera startup

## Evidence and scope

The 2026-10-18 report concerns Mosh 0.22.0 and USB 2.0 Camera
`0x143000000c456366` (vendor 3141, product 25446). The new chat connected
before capture failed. Its later transport loss and the older MLS error are
separate investigations.

The system log shows selection of 1280×720 YUVS at 10 fps followed by a
roughly 30 fps duration. In the pinned AVFoundation backend, `set_all` replaces
the selected format on every resolution match, retains a range from an earlier
format, and ignores FourCC. That is a concrete source defect; whether it is the
only cause on this device still requires a physical rerun.

## Plan

1. Select the native format and its own supported duration together, matching
   resolution and nokhwa's pixel-format descriptor. Log the native FourCC;
   nokhwa normalizes several native codes to the same descriptor. Preserve
   native fractional frame timing. Balance the
   existing configuration lock without changing its public API.
2. Report bounded native mode information, startup phase, helper stderr, output
   failure and exit status through the existing application log. Never log
   image bytes or media/account secrets.
3. Verify patch reconstruction and hashes, formatting and compilation/static
   checks available on this Linux host. The user requested no test runs.
4. Document the physical acceptance: affected Mac Mini local preview and first
   frames, then transmission to the Air. Neither compilation nor an unchanged
   permissions database establishes hardware acceptance.

## Ranked hypotheses and limits

1. Mismatched native format/range: supported directly by the source loop and
   consistent with the reported 10/30 fps transition. A matched native pair
   removes that invalid combination.
2. Another configuration/open-stream failure: stderr and exit diagnostics
   distinguish it on the next run; current application logs discard both.
3. Driver/device contention or capture-session behavior: remains possible if
   the matched format still fails. Inspect actual native modes before choosing
   a lower supported mode; do not force an unadvertised FPS.

Keep current resolution preferences, permissions, sandboxing, public bridge and
binary capture protocol unchanged. No new dependency is needed. macOS SDK
compilation and the affected physical device are unavailable on this host.

## Default camera settings (additional user request)

Rename Sound to Sound & Video (Звук и видео). Reuse the existing device picker
for a desktop camera card. Add a backward-compatible optional camera ID to the
existing audio-devices preference file; each setter preserves the other picks.
Expose helper inventory and camera preference access through the existing native
call bridge and regenerate bindings. Inventory must not open a stream or call.
Save only stable platform IDs. On first camera enable, resolve the saved camera
against asynchronous inventory and fall back to default when missing; voice-only
preparation must not wait for camera enumeration. Per-call choices and active
calls remain independent. Check Flutter analysis, generated binding drift and
Rust compilation/lint without running tests.

## Verification on Linux

On 2026-10-18 the helper and core library compile with their locked dependency
graphs. Clippy passes for the helper and core (all targets) with warnings denied;
Flutter analysis and localization generation pass. Repeating bridge generation
produces byte-identical bindings after the standard Rust formatting step. The
complete macOS dependency patch reconstructs from its verified upstream archive
to the pinned source hash. Independent read-only spec/standards reviews found
and corrected the loss of camera-enumeration errors before the settings picker.

No tests were run, as requested. No macOS SDK compilation or physical camera
acceptance is claimed. A new macOS build and the affected Mac Mini's local
preview/first frames, then Mac Mini → Air video, remain outstanding.

CodeAnt's review of PR #90 identified that synchronous default-camera resolution
could delay voice-only preparation by the inventory helper's three-second bound.
The native owner now resolves the initial saved camera only when video starts,
using its existing asynchronous inventory. Explicit per-call choices supersede
the pending default; failed inventory still allows the documented default fallback.
Call choices carry explicit camera-selection intent so microphone/speaker/on-off
commands cannot restore an old ID after asynchronous default resolution. Both
sides of the local bridge and its generated bindings are updated together;
the network and binary camera frame protocols are unchanged.
