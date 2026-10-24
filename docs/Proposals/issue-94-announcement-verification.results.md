# Issue 94: announcement verification reuse

## Evidence and scope

The owner capture before this memo attributes 898 of 10,430 selected instruction weights
(8.61%) to Go Edwards25519 leaves. These are sampled weights, not a whole-process
CPU budget or a recovered caller stack. A separate native fixture identifies
the announcement verification callers and observes 1,825 identical successful
inputs among 2,084 peer/status checks (87.57%). The observer executes every
original signature check. See the [preceding investigation](issue-94-windows-interfaces.results.md).

The user approved a further Moss-source exception for a bounded memo of these
successful cryptographic facts. Moss `82eb8b6` hashes the complete decoded public
key, signature and canonical signed payload. Fixed key/signature widths make
the tuple unambiguous. Only successful checks enter a lazy, per-node FIFO of at
most 1,024 SHA-256 keys. No payload buffers or private keys are retained.

Changed inputs and negative results still execute real verification. Eviction
only causes a future check to run again. No TTL is needed for this immutable
cryptographic fact; trust, freshness and admission are never inferred from it.
Crypto runs outside the cache lock, so concurrent misses may independently
verify the same input. Later hits reuse the successful result.

Both peer-announcement and supernode-status handlers retain all per-envelope
sender trust, address, capability, admission and forwarding decisions. Legacy
v1/v2 payload construction and malformed Noise-key rejection remain. Hole-punch,
relay, publish and handshake verification are outside this memo. Public Go/C
contracts, wire formats, dependencies, discovery cadence and routing are unchanged.

## Behavior proof and local verification

The behavior-preserving seam at `3361fc8` runs the original verifier for every
input. The new regression fails there: two identical valid announcements run
real crypto twice instead of once. At `82eb8b6` it passes.

Real-crypto tests cover changed key/payload/signature bytes, size failures,
negative-result retries, different valid identities, lazy allocation, FIFO
eviction and concurrent misses. Handler tests exercise forwarded-to-direct trust
updates, signed capability changes/revocation and unsigned capability rejection
with warm entries. Focused race tests and `go vet` pass. The new cache module
has 100% statement coverage; branch records are unavailable from Go's coverage
tool. Full local Go tests pass across all twenty tested packages, and the Linux
C-shared library builds with Go 1.25.9.

Independent Standards and Spec reviews of `3526e05...82eb8b6` report zero
findings. Existing oversized Node/handler exceptions are documented in Moss;
the new module and tests meet the supplied size limits.

## Matched Windows comparison

[Run 40030919399](https://github.com/redstone-md/mosh-flutter/actions/runs/40030919399)
uses measurement commit `3b45806a`, optimized Go 1.25.9 and one AMD EPYC 7763
runner with four logical processors. Both executables are built before timing:
uncached `3361fc8` and cached `82eb8b6`, with identical benchmark/golden sources.
Twenty pairs alternate execution order. Each sample measures 16,384 checks per
mode in cold 2,048-check batches; the repeated mode has 256 distinct signed
inputs per batch (87.5% repeats). Canonical v1/v2 peer and status claims use
deterministic public test seeds; no application identity or live network is used.

| Median timed component, per check | Uncached | Cached | Change |
| --- | ---: | ---: | ---: |
| Repeated valid mix | 63.022 µs | 8.465 µs | −86.57% |
| All unique valid inputs | 63.179 µs | 64.034 µs | +1.35% |
| All invalid signatures | 63.190 µs | 63.717 µs | +0.83% |

Every repeated-work pair improves. The numbers are Go benchmark elapsed times,
not Windows process CPU counters. Fixture signing is outside the timed region.
Every result is checked, and handler-state SHA-256 matches before/after:
`58aa13c04ab26bc2e26d6ca01e0e2fda05b083b16443d323bfcd7ab051d666ba`.
The artifact includes all samples, toolchain, hardware and binary hashes.

Ordering and tie-breaking are preserved because only a pure verification result
is reused; handler code and its order remain unchanged. Floating-point behavior
is inapplicable, and production RNG use is unchanged. An additional optimized
Linux CPU profile of the same repeated workload confirms that remaining real
Ed25519 checks still execute; those profiles are separate from Windows timing.

## Limits

This optimization removes repeated cryptographic work, not incoming network
packets. It does not establish a whole-Mosh CPU reduction, explain residual
bandwidth or close issue 94. Cache pressure can reduce hit rate while retaining
correct verification. Whole-Windows idle/network and Android background-call
and battery acceptance remain open. No merge or release is included.

The [subsequent exact-binary owner capture and bounded-history Windows run](issue-94-owner-20261023.results.md)
confirm removal of the old dominant curve hotspot while recording the remaining
CPU/network work. They do not close whole-application idle acceptance.
