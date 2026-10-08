# Issue 46: native media feasibility results

Status on 2026-10-08: **hold application adoption**. The isolated Linux tracer
bullet exchanges protected audio/video through real Moss processes. It does
not implement video calls in Mosh or finish the plan's first adoption gate.

## Implemented boundary

- Reconstruct pinned RingRTC sources with verified archive/tree hashes and three
  documented upstream patches. Reuse OpenMLS's source-preparation mechanism.
- Wrap Moss's directed packet send/callback API without changing its pinned source.
  Missing capabilities and invalid targets fail explicitly.
- Load an isolated native engine library in the same process as the existing
  Mosh/Moss adapter. The application has no RingRTC dependency or new bridge API.
- Run two independent installations with bounded queues, synthetic I420 input,
  native duplex audio, fresh directional SRTP keys and actual runtime statistics.
- Check real packet/stream callback coexistence in both registration orders.

Build and reproduction commands are in the [probe README](../../mosh-probe/media/README.md).
The [upstream patch notes](../../third_party/ringrtc-patches/README.md) explain the
ABI mismatch, reproduced video-track lifetime crash and build-output isolation.

## Inputs and observed results

| Input | Value |
| --- | --- |
| Host | Debian Linux x86_64, KVM, 16 exposed CPUs, AMD EPYC 7713 |
| Rust | 1.96.0; upstream RingRTC toolchain file requests 1.97.1 |
| RingRTC | 2.72.1, commit `331d601894f931337d24e9d56c68b94d28fc4555` |
| WebRTC | Upstream verified prebuilt artifact `7871n`, Linux x64 release |
| Moss | Commit `0effb8bb2cd318d2fb516cd2689083daaa5a1917` |
| Video | Synthetic changing I420 luma, requested 1280×720 at 30 fps |
| Audio | PulseAudio sine source and null output sink; physical devices absent |
| Route | Directed Moss packets between separate loopback installations |
| Negotiation | Trusted test pipes, fresh AES-256-GCM SRTP keys per direction |

The 60-second run received 1763 and 1762 decoded frames respectively. Of those,
1643 and 1642 were 1280×720; initial adaptation used smaller frames. Sampled
receive rates after ten seconds were approximately 28–30 fps. The last video
samples were 245 and 238 kbit/s. Runtime codec and encoder/decoder implementation
were **VP9/libvpx**, a software path. Neither fixture queue reported drops;
carrier sends reported no errors and maximum synchronous send durations of
1.315 and 2.406 ms. Both directions reported received audio packets and energy.

These are transport observations for a low-complexity synthetic source on a
virtual host. They do not measure camera quality, end-to-end delay, lip sync,
CPU/thermal behavior, speaker playback or Flutter responsiveness. Native build
and lint work also ran on this host during the measurements.

A separate 15-second run changed one byte in the caller's SRTP key supplied to
the callee. The callee decoded zero video frames and observed no received audio;
the reverse direction still decoded video and received audio. The runner passed
the negative authentication check. This proves rejection for that fixture, not
authenticated linked-device negotiation in the application.

A factory/offer check loaded the engine without Moss. Linux `strace -f -e
trace=network` recorded no `socket(AF_INET...)` or `socket(AF_INET6...)` calls.
PulseAudio uses local Unix sockets. This supports the injected-network boundary
for exercised factory/offer creation; it is not a relay or packet-egress audit
on every desktop platform.

Preparing the source again with `--offline` succeeded after the native build:
Cargo's output directory no longer contaminates the verified source tree.

## Packaging finding

Putting `mosh-core` and RingRTC in one Cargo dependency graph fails resolution:
OpenMLS's `hpke-rs 0.6` uses `libcrux-sha3 0.0.6` with `hax-lib =0.3.6`, while
RingRTC's mandatory libsignal graph uses `hpke-rs 0.7`, `libcrux-sha3 0.0.10`
and `hax-lib ^0.3.7`. The isolated shared-library boundary links and runs both
stacks in the same Linux process without patching cryptographic dependencies.
Both probe Cargo lockfiles are committed. Their license/dependency implications
still belong to application adoption review.

## Adoption gates still open

| Gate | Current evidence / missing work |
| --- | --- |
| Desktop packaging | Linux shared library and host build/run; macOS arm64/x64 and Windows debug have not run. |
| Directed carrier | Direct Moss transport works with bounded fixture queues; relay scheduling, aggregate/flow budgets and actual completion timing remain unproved. |
| Selected-device authentication | SRTP accepts valid and rejects wrong fixture keys; production device identity, caller confirmation, occupancy and key exchange are not implemented. |
| Capture and presentation | Synthetic decoded video and virtual audio work; camera capture, bounded child-window frame delivery and physical quality acceptance are absent. |

The pinned synchronous `Moss_SendToPeer` can spend five seconds opening a relay.
The probe drops packets queued for more than 50 ms before sending them, but it
cannot cancel a send already inside Moss. RingRTC records injected socket send
time at queue admission. No measured production capacity policy has been chosen.
For a started direct node, Moss's success also acknowledges its own outbound
queue, not the subsequent socket write. The reported fixture counters do not
measure that internal queue's residence time or eventual write failures.

Moss's callback sender key is copied from the envelope's **claim**, not supplied
as an authenticated connection identity. Production control authorization must
use linked-device proofs. SRTP fixture keys come from trusted pipes and cannot
be replaced by trusting that callback field.

The main application's voice pipeline remains the working baseline. The next
plan stage is gated on the missing proof above; no video button, new call
protocol, camera owner, renderer IPC or relay policy is shipped by this change.
User-provided desktop testing can add evidence using the probe instructions;
access to remote hosts is not required for the current handoff.

## Repository checks

- Focused directed-packet integration: passed, separate real Moss processes,
  including existing stream delivery in both callback-registration orders.
- Directed-packet refusal, absent symbols, NUL target and empty native buffer
  unit checks: four passed. Empty payloads also pass through both real processes.
- Node source/lock suite: 16 passed; aggregate coverage 90.64% lines / 86.81% branches.
  Shared source preparation itself: 92% lines / 80% branches.
- Core, engine and host clippy with warnings denied: passed.
- Directed-wrapper coverage from focused unit and independent-process checks:
  32/35 executable lines, 91.43%. Stable Rust did not emit branch counters.
- The initial bare Cargo suite passed 701 unit tests, then a public-network
  group-preview check timed out. The isolated retry passed in 33.74 seconds;
  the repository's real local-tracker wrapper passed it in 1.82 seconds.
  The full `node scripts/moss-test.mjs -j 2 --no-fail-fast` run then passed:
  701 unit tests and 49 integration checks, with 28 ignored test/helper entries.
  This matches the CI discovery setup rather than depending on the public mesh.
  After the empty-buffer regression fix, all four directed unit checks and the
  independent-process packet/stream check passed again; final core lint passed.

The final fixture disables Moss DHT/LAN discovery and trackers. Both the normal
and tampered-key media checks passed again with those settings. Source checksum
preparation is included in the existing pinned-source CI step.

## Standards review

Reviewed `12b074fd...c5991217` against root/core `AGENTS.md` and the code-review
smell baseline. No confirmed documented-standard breach was found. One
low-priority Feature Envy suggestion moved measurement serialization from the
engine command owner into `Measurements::snapshot()`, beside its recording code.
The suggestion is addressed; library result ownership, unload order and native
observer teardown were reviewed.
The final incremental review also checked empty-buffer safety, graceful worker
shutdown, fixture discovery isolation and CI source checks; it found no new issues.

## Spec review

No confirmed correctness mismatch or scope creep was found in the isolated
Linux proof. Four agreed adoption gates remain open: desktop packaging,
carrier completion/relay feedback, authenticated selected-device negotiation,
and physical capture/presentation quality. The plan requires "Windows debug and
both macOS architectures", "usable timing/loss feedback", "Authenticated
selected-device negotiation" and "child-window frame delivery"; those are
still missing rather than silently claimed by a passing synthetic run.

The optional review suggestion to check audio as well as video in the
tampered-key test is addressed. The rejected direction now must report neither
decoded video nor received audio; the reverse direction must receive both.

Review counts: Standards — one low-priority suggestion addressed, zero confirmed
breaches; Spec — four acknowledged open gates, zero confirmed stage-1 defects.
