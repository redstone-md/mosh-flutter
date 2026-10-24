# Issue 94: known-recipient DM discovery

Implementation: Mosh `f9727ccf`, pinned Moss `979a634`. This follows the
[approved plan](issue-94-dm-discovery.plan.md). Owner idle acceptance and Android
background-call/battery acceptance remain open. No merge or release is implied.

## Behavior and compatibility

Mosh opts a DM into KnownPeers only after every current MLS signer maps to a
live authenticated device route and the existing connection requests succeed.
Incomplete/legacy membership stays Automatic. Admission, removal and local
revocation refresh the policy; this cache never grants membership.

KnownPeers suppresses that room's topic rendezvous/provider publication and
unrelated speculative GRAFTs. Opaque room mappings determine scope. Identity
publication, subscriptions, relays, groups, channels and unconfigured consumers
keep their existing behavior. The C symbol is optional; an older library keeps
Automatic without preventing startup.

Two delivery defects surfaced during verification:

- Disconnecting a relay target silently removed its transit route. The surviving
  endpoint retained an apparently connected route and stopped retrying. Route
  removal now uses the existing bounded, one-shot expired-route close mechanism.
  Duplicate retirement cannot recreate a consumed close.
- The retained explicit-target worker tried known addresses and connected
  relays but did not resolve an unknown ID. After those attempts fail, only
  opted-in recipients now reuse the existing identity resolver, cancellation
  and retry backoff. No second scheduler or wire change was added.

## Functional verification

- Real direct delivery to an unchanged endpoint survives 32 seconds offline
  without registering its connection request again.
- Real encrypted relay delivery and automatic return after 32 seconds pass.
- An independent directory seeded with the target's genuine provider record
  lets an initially unknown recipient deliver through its separate attachment.
  Automatic and cancelled attempts do not opt into this lookup. The same test
  fails on the preceding worker and passes three times with the race detector.
  Directory seeding is a controlled fixture; it does not claim general overlay
  record replication beyond existing behavior.
- Two separate processes load actual current and baseline shared libraries;
  the baseline lacks the new symbol. Bidirectional delivery passes before and
  after 32 seconds offline. The current library SHA-256 is
  `b62e17c2ca4f21c1dee53fbd1c4e226ea7e56cc7fde967bcd139d629effce669`;
  the baseline is
  `3475f2776f20941301bde5adcc35328b6cb2f2b0719af3820c4185c90b646222`.
- Authenticated Rust membership tests cover incomplete mapping, admission,
  removal and local revocation. The real C-ABI round trip propagates invalid
  native policy errors; missing-symbol startup retains the old behavior.

Full Go tests, full race tests and vet pass on Moss `979a634`;
[Moss CI](https://github.com/redstone-md/moss/actions/runs/40053195644) also
passes Ubuntu/Windows tests and the fast-package race suite. The policy module
has 61/62 covered statements (98.39%); shared relay retirement has 14/14 (100%).
Rust policy line coverage is 85.71%, with 95.12% for the optional FFI adapter;
the Rust coverage tool reports no branch data. Independent Standards and Spec
reviews found no remaining findings after the duplicate-retirement fix.

[Mosh runtime CI](https://github.com/redstone-md/mosh-flutter/actions/runs/40053208125)
passes at `f9727ccf`, including Rust suites, Flutter tests, bridge drift, real
multi-device DM/linking, native audio/video on Linux/macOS/Windows, Windows
integration, Android arm64 debug packaging and both desktop packages. The
separate configured Windows build below uses the full release profile.

The first local Rust full-library run lost its executable when another local
build replaced it: 12 child-process tests reported OS error 2. All 12 passed
when rerun sequentially without rebuilding. Platform CI supplies independent
full-suite verification; this orchestration failure is not a product assertion.

## Measurement method

The older synthetic fixture had complete authenticated mapping in only two of
eight DMs. Its other six correctly retained Automatic. It cannot establish an
eight-room optimization, nor does it establish the owner's actual membership
state.

A fresh upper-bound fixture has eight DMs with 100 real acknowledged messages
each, two groups and one channel. All eight authenticated route sets were confirmed
before their counterparts stopped. Each observation restores the same saved
state and verifies the message golden. A private compiler overlay counts
decoded inbound and successful outbound JSON envelopes and distinguishes topic
discovery from identity lookup. It records only type/count/size.

The A/B/A control uses the same Rust worker and instrumented Moss binary.
Only a private diagnostic override translates KnownPeers requests to Automatic
in the A windows. Warmup is 120 seconds, followed by a 65-second counter window.
Requests for names, each conversation list and the selected DM run once per
second, compensating for processing time. Observed median periods are
1.001/1.001/1.002 seconds, with individual periods up to 1.64 seconds; late
work is not queued for catch-up. Elapsed timestamps identify warmup; sample
indexes are not interpreted as seconds.

All three native windows complete with the same message golden, eight requested
KnownPeers policies and zero recorder drops. Only the middle window applies
the eight policies.

| Per 65-second window | Automatic A1 | KnownPeers | Automatic A2 |
| --- | ---: | ---: | ---: |
| DM topic-discovery starts | 120 | 0 | 120 |
| Addressed identity-lookup starts | 0 | 16 | 0 |
| Other-room discovery starts | 32 | 32 | 32 |
| All outbound GRAFTs | 857 | 232 | 771 |
| All inbound PRUNEs | 864 | 232 | 768 |
| Classified JSON rate, Mbit/s | 0.175 | 0.140 | 0.170 |
| Connected peers, start → end | 13 → 13 | 14 → 14 | 14 → 14 |

The reversible disappearance of DM topic lookups, with unchanged other-room
starts, establishes the scoped reduction in that work. Sixteen identity lookups
retain addressed recovery for the offline recipients. Total GRAFTs and bytes
also depend on public topology; these rates do not establish an isolated
whole-process CPU or wire-rate improvement.

Classified JSON excludes malformed packets, handshakes, other streams
and OS overhead. The native worker uses the development/test profile, and other
verification work overlaps part of its first window; its CPU is not used as a
release CPU budget or causal improvement. Public topology can change. Session
byte totals are discarded because replacing sessions can reset them.

## Windows release verification

The [full release build](https://github.com/redstone-md/mosh-flutter/actions/runs/40053211809)
at `f9727ccf` passes. Installer SHA-256:
`92a7cc79d088cd0fc2f1ce440e6f48406f3a490f0394b1a414d5371373dde05f`.
All five unpacked application binary hashes match the original symbol manifest;
the Rust DLL also matches the separately uploaded copy. DLL and PDB share GUID
`AFE22585-D3BA-4781-87F3-E4204D15FFE1`, age 1. The original PDB SHA-256 is
`f6944c88b287e5ec9db74fa962720eee31b1f3750756ce299ffd93dae571eb91`.

The Moss DLL reports Go 1.25.9 and exports the optional room-policy symbol.
The parallel-codegen step is skipped: the committed Rust release profile keeps
fat LTO and one codegen unit. The public PLUS manifest pins production billing,
issuer verification and configured purchases.

Measurement-only branch `test/windows-idle-current`, commit `e4f628e5`, pins
this installer, its hash and its source commit. It changes only the three
artifact inputs in the existing harness; it is not a merge candidate. The
[installed-GUI run](https://github.com/redstone-md/mosh-flutter/actions/runs/40054832189)
passes with 800 acknowledged messages, the original 480-second warmup,
visible/minimized windows and restored-inventory checks. The before/after body
digest is `c21241d354aee8750eed51232ab487bed2121eb65d9aa7eae00d6d37f4160def`.
All five binary hashes equal the verified installer. Both network windows are
control-validated, loss-free and reconcile endpoint/per-second/total bytes.
This unchanged Windows harness does not expose applied policy counts; eight
saved DMs must not be interpreted as proof that eight rooms opted in. The native
control above separately verifies all eight complete recipient sets and policies.

| Current installed Windows GUI | Open window | Minimized window |
| --- | ---: | ---: |
| Process age at capture start | 508.81 s | 659.20 s |
| CPU, one logical core | 8.907% | 8.973% |
| Mean external network rate | 0.120 Mbit/s | 0.124 Mbit/s |
| Median working set | 110.12 MiB | 112.90 MiB |
| Caller weights including software rendering | 18.84% | 21.36% |

The current runner is an AMD EPYC 9V45 with four logical processors; the earlier
baseline used an EPYC 9V74. The CPU readings are higher than that baseline and
do not establish improvement. Hardware, public topology, policy applicability
and software rendering prevent treating these separate runs as a causal CPU
A/B. The rendering percentages are inclusive sampled weights, not CPU duration.
This run proves installed-application behavior and records current budgets;
it does not explain the owner's complete remaining CPU usage.

## Remaining acceptance

The [owner capture from 2026-10-24](issue-94-owner-cpu-20261024.results.md)
matches all five shipping binary hashes and records lower observed traffic
and CPU. Matching [caller paths and signature results](issue-94-shared-verification.results.md)
now attribute part of the remaining work. The implementation, native control
and runtime CI are verified; whole-owner CPU/network acceptance remains open.
Native query reductions alone do not close issue 94, prove the original
reported 100–150 Mbit/s source, or establish Android background behavior.
