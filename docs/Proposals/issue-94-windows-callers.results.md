# Issue 94: Windows GUI caller attribution

The exact configured Windows release completes the saved-chat fixture and
caller capture, but does not reproduce the owner's residual load. This is a
measurement result, not another application optimization or idle acceptance.

## Release and fixture

[Full GUI run 39890690495](https://github.com/redstone-md/mosh-flutter/actions/runs/39890690495)
uses measurement commit `cd5e9c72` on `test/windows-idle-current`. It installs
the existing `cd6df31b` release from run 39861533400 without rebuilding Mosh.
The installer checksum, production PLUS manifest, all five installed binary
hashes and original native DLL/PDB identity match the owner's latest capture.
Moss remains `eb79f38`; no product or Moss runtime is changed.

The disposable installation establishes eight real DMs, acknowledges one
fictional text in each, stops all counterparts and creates two groups and one
channel. The shipping GUI opens a saved offline DM through MSAA. After eight
minutes of warmup, it captures ninety seconds visible and ninety seconds
minimized. HWND visibility/minimized state and PID are checked before collector
launch and after processing; focus is also recorded. These checks bracket
setup and processing as well as the timed capture. After exit, the native
API reopens the same store: inventories remain 8/2/1, invitations remain empty
and all eight message bodies retain SHA-256
`83038d2c5f1760a2f7f6e87bd57477a547d36a6c9ccfffd17fc30eb8ffd446f9`.

The host is an AMD EPYC 7763 VM with four logical processors. Network controls
pass, all loss counters are zero, and endpoint/per-second bytes reconcile in
both windows. CPU values below come from process counters, not sample counts.

| Observation | Visible | Minimized |
| --- | ---: | ---: |
| CPU, one logical core | 1.261% | 3.750% |
| Process-counter interval | 89.238 s | 89.575 s |
| Network interval | 90.628 s | 90.951 s |
| Combined external network mean | 0.261 Mbit/s | 0.193 Mbit/s |
| Working-set median | 94.63 MiB | 91.11 MiB |
| Exact-PID instruction / caller weight | 5,536 / 5,536 | 6,123 / 6,123 |

These are sequential public-mesh observations, not a paired optimization
comparison. Their traffic/topology changes, software-rendered VM, enabled
Flutter semantics and small fictional history differ from the owner's
installation. The minimized window having higher process CPU establishes no
causal rendering effect. CPU counters, network buckets and sampled stacks
also have overlapping but differently timed collection windows.

## Callers and limits

Pinned PerfView v4.0.0 exports the selected `TraceProcess` through its documented
extension API. An independent reader retains only paths rooted in the exact
PID, strips process arguments/module paths and reports skipped weight. Both
windows conserve all instruction weights; none is excluded as foreign or
unrooted. Original native symbols resolve useful Rust callers.

`DeviceIdentity::open` appears inclusively in 357 visible weights (6.45%) and
317 minimized weights (5.18%). Actual paths include DM/group/channel deletion
authority construction, DM receive/service work and device-link service.
For example, DM list snapshots load the local identity while constructing
message account proofs, and validate the unchanged roster. This confirms
repeated identity work as a candidate, without attributing the whole owner
CPU or bandwidth problem to it. Inclusive paths overlap.

The VM's software rasterizer also appears inclusively in roughly 24% of
weights. It cannot quantify rendering cost on the owner's physical GPU.
Native/Go/AOT unwinds remain incomplete: `BROKEN` occurs in 1,834 visible and
1,946 minimized weights. Many Go and Flutter frames lack names. Do not turn
these sample shares into process CPU milliseconds, identify a caller from a
shared crypto leaf alone, or treat conserved weights as complete unwinds.

Two earlier attempts collected valid visible process/network samples but
failed in PerfView's stock headless stack export, before the minimized and
store-restoration checks. They measured 3.220% / 0.227 Mbit/s and
2.818% / 0.225 Mbit/s on the same CPU class. They are partial observations,
not completed full-GUI checks.

The corrected exporter uses exact process selection and `SaveAsXml` without
GUI state. A [twelve-second live control](https://github.com/redstone-md/mosh-flutter/actions/runs/39890438432)
conserves 12,639 instruction/caller weights. Its unresolved managed JIT frames
are expected because CLR rundown is disabled; it verifies PID selection and
export operation, not native symbol quality. Focused synthetic tests cover
foreign/unrooted processes, cyclic stacks and metadata removal. Independent
Standards/Spec reviews also caught and corrected unsanitized error-log export;
only restricted error identifiers may enter shareable diagnostics.

## Owner caller trace received

The owner has now reprocessed the original trace successfully. All five
original binary hashes and the trace checksum match. The selected PID has
9,924 caller weights; 1,154 foreign weights are excluded. The trace confirms
redundant roster-prefix hashing, separately exposes Windows adapter-enumeration
cost below unresolved Moss frames, and retains substantial broken/unresolved
stacks. See the [owner attribution and matched roster-prefix results](issue-94-roster-prefix.results.md)
for the focused runtime fix and its limits.

## Existing-trace export

The existing owner ZIP remains valid at 12.909% of one core and 1.474 Mbit/s;
these lower-load CI windows do not replace it. Its private original
`raw/cpu.etl` supplied those caller chains without another recording
or app installation. A separately tested portable reader uses the original
PDB, checks the report's five binary hashes, selects the exact PID and keeps
raw traces/logs local. Only sanitized caller paths and build identity enter
its output ZIP.

The [portable-export Windows run](https://github.com/redstone-md/mosh-flutter/actions/runs/39895119355)
passes at measurement commit `85460f9b`. Both readers conserve 13,119 live
control weights across seventeen paths after applying identical metadata
normalization. Synthetic checks also preserve case-sensitive native symbols
and reject foreign-only/cyclic input. The exporter script successfully
reprocesses a trace from the exact installed release, verifies unchanged input
SHA-256 and checks that its report contains exactly `callers.json` and
`identity.json`. That earlier test did not cover the CMD entry with inherited
PowerShell 7 module paths or a downloaded DLL's blocking mark.

The [corrected portable bundle](https://github.com/redstone-md/mosh-flutter/actions/runs/39906509936/artifacts/12480608428)
at `917ad7a9` is 36,018,427 bytes and contains nine expected files. Its SHA-256 is
`ff61f807d36544130e67da5b6f71ef05ee9c5b609a8cd279e744cb86888936cf`.
The sidecar verifies, scripts match source after Windows line-ending
normalization, and embedded PDB/PerfView checksums match the originals.
The actual CMD entry now passes with both owner failure conditions present.
The helper also retains module-relative addresses for unresolved frames with
a recorded Moss module association. Unassigned or conflicting module frames
remain unknown. The CI-only conflict-test extension is absent from the bundle.
Extract its inner `mosh-existing-cpu-export.zip` and run
`Start-Existing-CPU.cmd` on the owner's Windows computer. It defaults to the
existing `cpu-20261023-000926` directory under LocalAppData/Mosh/Diagnostics;
if moved, it asks for the folder containing `binary-manifest.json` and `raw/`.
Send only the resulting `mosh-callers-report.zip` at the printed path.

The first matched runtime change from that attribution is recorded in the
linked roster-prefix results. The owner also exposed download-mark and mixed
PowerShell launcher defects; the actual-CMD regression and fixes pass in
[run 39906509936](https://github.com/redstone-md/mosh-flutter/actions/runs/39906509936)
on the auxiliary measurement branch. Issue 94 and Android background-call/battery acceptance
remain open. No merge or release is included.
