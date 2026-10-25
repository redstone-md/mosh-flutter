# Issue #94: observe readiness integration in the Windows GUI

## Boundary

Use the actual `moss.dll` from the configured installer at Mosh `b81f5f13`,
which pins Moss `fcdc338`. Preserve the previously verified `aa17f31e` GUI,
Rust DLL, Flutter DLL, AOT snapshot and native symbols. Two application copies
differ only in Moss. Verify all five binary hashes before comparing anything.
Both installers and native-symbol manifests are checked before use. This
avoids attributing unrelated compiler/packaging changes to the dependency.

Reuse the existing real-bridge fixture and collector. No product source,
production pin, dependency, application contract or user settings change on
this measurement branch. The integration pin lives separately on
`perf/desktop-idle-network`; neither branch is merged or released here.

## Method

Two ephemeral Windows jobs run opposite orders: before/after and after/before.
The initial run is triggered only by this workflow file changing on the
measurement branch, after its immutable installer identity is recorded.
Each job opens the actual candidate EXE, verifies its saved chat/composer and
seeds
eight real DMs with 100 acknowledged messages each, two groups and a channel.
Its post-close inventory must retain every message. It then prepares both
baseline application copies before either measurement. Counterpart
installations stop before idle measurements. The same saved fixture
and cryptographic identities are reused for the second variant on that host.
The reuse option requires GitHub Actions and an owned synthetic-fixture marker;
ordinary profiling still refuses an existing application data directory.

Each variant opens the saved chat, warms for 480 seconds, and records separate
90-second visible/minimized windows. Existing HWND, process CPU/network and
caller checks remain. Native inventories before and after retain every message,
zero pending invitations and the expected 8/2/1 chat counts. The comparison
fails on any application-binary change beyond Moss, unexpected DLL fingerprint,
changed history, missing fixture reuse or an incomplete network control.

The published artifact contains aggregate JSON and synthetic-fixture metadata
only. It excludes raw traces, fixture stores, keys, binaries and native symbols.
Installer source, Moss source, DLL hash, hardware, order and fixture reuse are
recorded. Original symbol artifacts remain separate from the profile report.

## Limits and checks

The two pairs are integration observations, not a statistical benchmark or a
deterministic network replay. Public peers, traffic and connection activity
change between windows; sequential visible/minimized windows do not isolate
window state as a cause. VM software rendering and profiling overhead differ
from the owner's physical hardware. No owner CPU gain or Android background
acceptance follows from a passing run.

Run existing parser tests plus focused comparison acceptance/rejection checks,
Python compilation, workflow lint and independent Standards/Spec review.
The actual Windows jobs validate fixture reuse and packaged-library loading.
The existing deterministic Moss regression/race tests and paired wait benchmark
remain the evidence for the polling mechanism and its allocation improvement.
