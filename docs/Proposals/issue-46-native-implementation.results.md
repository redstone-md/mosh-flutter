# Issue 46: desktop implementation results

Date: 2026-10-09. Host: Debian Linux x86_64, Rust 1.96.0, Flutter 3.44.8.
RingRTC 2.72.1 / pinned WebRTC, nokhwa 0.10.11 and the reviewed complete macOS
patches. Dependency adoption was explicitly approved by the user. Windows/macOS
physical acceptance will be performed by the user; implementation and PR work
are authorized to continue with best-effort local validation.

## Implemented and observed

- One production native audio/video owner, selected-device public negotiation
  authenticated through real MLS and media carried by real Moss directed packets.
  Ephemeral X25519/HKDF keys stay in the isolated engine. The renderer never
  receives keys or creates an engine/capture/playback owner.
- Four independent public-API process scenarios passed with a local discovery
  tracker: receive-only connection; changing RGBA delivered through fresh native
  SRTP and camera off preserving the call; a blocked camera driver being reaped
  without ending reception; selected caller never offering media, ending both
  calls after the setup deadline. These use an explicit camera-driver fixture,
  not a physical camera, and the production core/engine/transport.
- Real Flutter desktop integration passed in 14 seconds: one app, one independent
  public-API peer and a separate renderer. It delivered 135 previews and 128
  remote frames, sent a chat message during video, killed/restored the renderer
  (two openings), and disabled camera while reception continued. Capture was the
  driver fixture; microphone consent was deliberately denied for receive-only.
- Real native duplex audio passed with a PulseAudio sine source and null sink.
  Both peers received nonzero decoded audio energy. Muting the caller stopped
  its received audio-packet rate at the peer while video and reverse audio
  continued. Concealment noise/decay is not treated as transmitted microphone
  data. This is virtual audio, not physical microphone/speaker acceptance.
- Signed MLS/Moss boundary scenarios cover current selected-leaf authorization,
  revocation, reordered camera-off control, selected confirmation arriving after
  newer media, stale terminals, partition occupancy, durable failure close and
  exclusion of incompatible mobile media. Current removal evidence stops the
  affected selected pair while unrelated device removals preserve it.
- Regression tests reproduced and fixed a TCP reset during a renderer frame
  write, recovery deadlines incorrectly anchored to call age, and an undersized
  native video/control layout. Preparation waits for initial preferences;
  call replacement cannot inherit capture consent. Native preparation failure
  is surfaced once, and device-command failure does not create a retry loop.
  Overlapping failed binds retain the last working presentation client; late
  obsolete preparation and unbind cannot restore a stopped client. Rejected
  worker operations return an error through the public prepare/choices boundary.
- Standard Linux Flutter debug packaging passed, including the real engine,
  executable capture helper and GPL/AGPL/Apache notices. The source preparer,
  native Rust lint/tests, binding generation and widget checks run locally.
  Native CI lanes build and run real process checks on Windows/macOS/Linux.

The earlier [candidate measurements](issue-46-native-media.results.md) and
[frame IPC measurements](../Features/voice-calls.md#decoded-video-presentation-46)
remain separate evidence: a 10-second synthetic I420 720p30 candidate run copied
290/288 decoded frames with export age 15/14 ms; the 720p renderer fixture restored
its child and admitted 88/90 then 81/90 frames. They do not establish physical
capture, thermal behavior or complete sustained production 720p30 quality.

## Verification and coverage

Windows CI reproduced `0xc0000005` while releasing the native audio COM object.
The engine now keeps a thread-bound MTA apartment alive until every native
endpoint field is released. After that change, 14 engine tests and two capture
tests passed on Windows. Three consecutive CDB runs passed all four independent
API scenarios (12/12), with successful child-process exits and no access
violations. The normal CI lane also exercises receive-only connection and
teardown in three independent engine processes. Temporary debug probes and
debugger workflow switches have been removed. This does not establish physical
camera or microphone behavior.

The initial full core suite passed: 713 library tests and 50 integration tests,
with explicit native scenarios run separately. Eight final native-owner tests
and all four native process scenarios passed after review fixes.
Flutter passed 1844 tests with four
skips. Format, analyzer, clippy and a second-generation binding drift check
passed. Real network tests use `scripts/moss-test.mjs`. Native engine tests exercise real
WebRTC/SRTP, receive-only video and independent camera off. Capture cadence and
capability selection have focused tests, and macOS padded-BGRA validation runs
on Linux. The old feasibility probe shares the production decoder sink.

The instrumented native core owner/process checks covered 1048/1158 production
lines (90.5%), excluding test-only lines.
The production engine loaded through its C ABI in four independent process
scenarios covered 766/852 lines (89.9%), including 143/158 ABI lines. All four
scenarios passed with instrumentation; the engine's separate 13-test run also
passed with the virtual duplex audio fixture enabled.
The Flutter client/view/owner checks covered 320/344 lines (93.0%) and 102/126
branches (81.0%). A delayed captured-slot regression also verifies that the
encoder and preview admission count time waiting after pipe receipt.
Rust branch instrumentation is unavailable on the pinned
stable toolchain. Physical capture/permission and platform-specific code are
outside these host measurements; their coverage is not claimed.

## Remaining acceptance gates

- Physical Windows/macOS camera, microphone, speaker, permission refusal,
  unplug/replug and sustained 720p30 quality, A/V skew, CPU/thermal and UI checks.
  The previous user-run Windows probe is evidence for that candidate, not the
  newly packaged nokhwa helper or shipping native adapter.
- macOS CI built the engine and camera helper, passed lint/unit tests and all
  four independent process scenarios. A universal x86_64/arm64 application and
  DMG passed signing verification and menu tests. Helper architecture checks and
  signing order have command-boundary regressions; physical permissions remain
  a host acceptance check. The earlier Linux cross-target attempt lacked an
  Apple SDK and does not establish macOS behavior.
- Moss's existing relay has per-source limits but no aggregate node budget or
  audio/message reservations. Client pacing/priority is implemented; aggregate
  relay pressure and completion feedback remain separate library work. Root
  AGENTS.md forbids editing Moss source in this repository task.
- Native desktop and legacy Android/iOS media are incompatible. Authenticated
  offer admission excludes incompatible installations instead of selecting a
  silent call. Mobile native integration remains separately scoped.
- Hardware encoding is reported only when the engine reports it; no hardware
  guarantee is inferred. Direct/relayed route selection and bitrate caps are
  implemented, but relay load and complete quality targets are not accepted by
  the short virtual-device runs.

The PR references #46 rather than declaring every adoption gate complete.

## Narrow size exceptions

Generated bindings, Cargo locks, license texts and complete upstream patches
retain their generated/upstream structure. Native `library::Engine::new` (54 lines) and
`endpoint::Endpoint::new` (56 lines) are linear construction sequences: keeping the
library symbols and borrowed native lifetimes together makes teardown order
reviewable. `packets::send_loop` is a 52-line single sender loop with bounded
priority/budget/deadline decisions. The native engine's command dispatch remains
one cohesive owner over its endpoint/negotiator/queues. Real integration scenario
functions exceed 50 lines where one ordered process/UI lifecycle must be tested.
New production source files remain below 400 lines; UI admission, media binding,
presentation and native telemetry are separate modules.
