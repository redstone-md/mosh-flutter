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
