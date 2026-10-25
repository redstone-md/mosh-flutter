# Issue 94: validate the local deletion actor once per history snapshot

## Current Windows evidence

[Configured-release GUI run 40128660130](https://github.com/redstone-md/mosh-flutter/actions/runs/40128660130)
passes at measurement source `c4136405`, runtime `54135ec0`. The original
installer, all five binary hashes and original PDB match the owner capture.
The private artifact SHA-256 is
`abd8c62fc5944a3932f3ae961300b1d2a5e796d078d95ef9f62288344753926b`.
It contains only 27 JSON files; CRCs pass. The eight real offline DMs each have
100 acknowledged messages, plus two groups and one channel. Restoring the store
preserves all 800 bodies and inventory, digest
`c21241d354aee8750eed51232ab487bed2121eb65d9aa7eae00d6d37f4160def`.

| Observation | Visible | Minimized |
| --- | ---: | ---: |
| CPU, one logical core | 9.598% | 11.015% |
| CPU across four logical processors | 2.400% | 2.754% |
| Mean external traffic | 0.086 Mbit/s | 0.287 Mbit/s |
| Median working set | 115.26 MiB | 116.71 MiB |
| Raw instruction / caller weights | 11,721 / 11,721 | 12,011 / 12,011 |
| Broken unwind weights | 1,542 | 1,973 |

Both captures are complete and control-validated, with zero loss and exactly
reconciled protocol/second/endpoint byte totals. Raw/module/caller totals
reconcile; no foreign or unrooted caller weight is present. The host is an
AMD EPYC 7763 VM with four logical processors. Sequential public-network
windows, different hardware and software rendering prevent causal comparisons
with each other or the owner's machine. The owner's high working set and
reported 100–150 Mbit/s are not reproduced.

| Inclusive project caller | Visible weights | Minimized weights |
| --- | ---: | ---: |
| DM session snapshot | 809 | 812 |
| DM list API | 782 | 779 |
| Message origin verification | 328 | 312 |
| Ownership-proof parsing/verification | 267 | 259 |
| Local identity open | 178 | 180 |
| Global DM tick | 168 | 155 |

These nested weights overlap and are not exclusive CPU milliseconds. Software
rasterization occurs in 3,144/3,122 weights; it cannot explain the physical
owner's GPU cost. No strict Ed25519 verification frame is observed. The
bounded cryptographic fact cache still performs transcript parsing/hashing.

## Ranked hypotheses and scope

1. Local actor authorization repeats for each eligible message. Source confirms
   `snapshot::messages` calls `DeletionAuthority::permitted` for every row;
   each call parses the same local account proof through `is_revoked`.
   Prediction: one immutable history snapshot can reduce local revocation/proof
   evaluations from N to one while returning byte-identical message metadata.
2. Full-history list serialization and per-message proof work also scale with
   history. Those remain separate candidates; this change preserves list shape
   and per-origin checks rather than adding a new bridge contract.
3. Renderer and network/runtime work contribute the remaining cost. A local
   permission correction cannot claim to fix them or the owner's whole CPU.

Opportunity for hypothesis 1: impact 2 × confidence 5 / effort 2 = 5.

Introduce a private borrowed snapshot permission evaluator. It lazily validates
the local actor once while holding an immutable borrow of the current authority.
It lives only for that `messages` call; a new snapshot rechecks current proof,
membership and revocation. Empty/ineligible histories do no extra actor work.
Direct deletion commands retain fresh checks. Per-message origin signatures,
author/account matching, admin rules, ordering and all returned fields remain.
No global authorization cache, public API, wire, storage, dependency, Flutter,
timer, discovery or Moss source change is included.

## Checks

Extend the existing shared snapshot seam with a red regression: multiple signed
own messages preserve full expected rows but currently repeat local actor checks.
Keep forged origins, certificate changes, role loss and issuer revocation tests
green. Verify lazy behavior for rows that cannot offer shared deletion.
Use the existing release API worker and restored acknowledged history for
twenty alternating before/after pairs, checking complete message and permission
goldens. Report its history size and isolated-network limits explicitly.
Run formatting, build, focused/full native tests, Clippy, independent review and
CodeAnt comments/nitpicks before handing over a configured Windows installer.
Issue 94 and physical Android background acceptance stay open.

The [implementation and matched comparison](issue-94-snapshot-authority.results.md)
record the final behavior, validation and acceptance limits.
