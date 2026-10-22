# Issue 94: attribute the remaining Windows idle CPU

The owner confirms the configured installer from run 39692467913 and the same
8-offline-DM / 2-group / 1-channel profile. The 2026-10-22 capture is complete,
control-validated and has zero ETW loss: 1.416 Mbit/s and 16.02% of one logical
core, versus 1.537 Mbit/s and 16.45% previously. The ZIP has no binary hash.
Whole-application acceptance remains open; native retry counts alone do not
explain this remainder.

## Measurement scope

Use an isolated diagnostic branch and the already-built, checksum-verified
Windows installer. Compile only a small pure-Dart client of the existing FRB
API. Build no replacement product DLL and change no production behavior.
Generate eight real established DMs with independent counterpart processes;
confirm delivered fixture messages, then stop those counterparts. Create two
groups and a unique empty public channel. All identities/data are fictional.

Run sequentially on one Windows runner:

1. Real release DLL through the Dart API client, with the same one-second UI
   reads and a warmed offline fixture.
2. The installed release Mosh.exe using that fixture and the normal Windows
   credential store. Open a saved offline DM through Windows accessibility, warm up,
   measure visible and hidden-window phases.
3. Capture process CPU/RSS and per-thread CPU, descriptions and start modules.
   Record source/artifact hashes, hardware and actual window/fixture checks.

Use an eight-minute warmup and 120-second measurement windows. This first
probe separates native and renderer/service costs; public topology, synthetic
history and missing paid entitlement prevent claiming a controlled owner-host
CPU estimate. Ranking must precede any new optimization.

## Risks and checks

The fixture must live only on the ephemeral runner. Refuse an existing app data
directory. Upload only aggregate measurements and validated fictional app UI
state, never credentials, stores, invitation URIs or raw system traces.
Keep the two performance PRs unchanged by this diagnostic branch. Reuse the
registered network-diagnostics workflow for dispatch; no main merge or deploy.
Validate the Dart client by AOT compilation and its real API/fixture assertions;
validate scripts statically before dispatch. Failed GUI or fixture checks must
fail the run rather than producing a misleading idle comparison.

Flutter 3.44's engine enables semantics on an MSAA request; its UIA provider is
disabled by default. The first native profile passes (4.294% of one logical
core), but UIA only exposes the FLUTTERVIEW host. Use the built-in MSAA API for
the GUI check. `measure_native=false` builds the same real fixture but skips
the repeated headless warmup/measurement while validating GUI automation;
its native summary is null and cannot establish a same-host native/GUI ratio.
References: [Flutter engine](https://github.com/flutter/flutter/blob/3.44.8/engine/src/flutter/shell/platform/windows/flutter_window.cc),
[AccessibleChildren](https://learn.microsoft.com/en-us/windows/win32/api/oleacc/nf-oleacc-accessiblechildren).
