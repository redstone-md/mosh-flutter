# Issue 94: full Windows caller attribution

The owner still measures 12.909% of one core and 1.474 Mbit/s after warmup
with `cd6df31b`. Linux native profiling does not reproduce that Windows
workload. No further application optimization is justified by flat leaves.

Use the previously verified full-GUI fixture on the isolated measurement
branch `test/windows-idle-current`. Install the exact configured EXE from
run 39861533400, verify its checksum, public manifest, all five binary hashes
and the matching original native PDB. Do not rebuild or patch the application,
Moss, persisted contracts or generated bridge.

1. Establish and acknowledge one fictional text in each of eight real DMs,
   stop all counterparts, and create two groups and one channel. Require
   exact inventories and no outstanding invitations.
2. Open a saved offline DM through the shipping GUI and verify its composer
   through the existing MSAA driver. Warm for eight minutes. Measure ninety
   seconds visible, then ninety seconds minimized, recording process CPU,
   RSS, exact-PID instructions, control-validated network bytes and caller
   stacks. Record hardware and binary fingerprints. Check and record HWND
   visibility/minimized state before collector launch and after processing;
   these checks also bracket setup/processing. Record focus without requiring
   it, since collector consoles can take it.
3. Reuse the corrected CPU collector. Export caller stacks using pinned
   PerfView v4.0.0 and matching native symbols. Independently retain only
   stacks with the selected PID, remove process arguments and module paths,
   and report discarded foreign/unrooted weight. Verify this with synthetic
   foreign-process, metadata and cyclic-input tests before dispatch.
4. After exit, reopen the real store through the API and check inventories.
   Upload only selected aggregates; never upload raw traces, stores, keys,
   log files or unfiltered PerfView XML. Owned disposable runner processes
   can be stopped during cleanup. User installations are never touched.

This is exploratory attribution, not a causal benchmark or an acceptance
gate. Sequential public-network windows have different traffic and topology.
MSAA inspection enables Flutter semantics; fictional history and runner
hardware also differ from the owner. Unknown Go/AOT/native unwind frames
remain explicit. Do not subtract windows to claim rendering cost, treat
sample shares as process CPU, or call a nonreproducing fixture a fixed bug.

Next runtime work requires a ranked caller hypothesis and a reproducible
before/after check. No production behavior changes in this measurement step.

## Existing owner trace

If the current GUI fixture does not reproduce the owner load, reprocess the
already recorded owner `raw/cpu.etl` with the same exact-PID PerfView extension
and original native PDB. A portable PowerShell 5.1 reader avoids requiring
Python or another recording on the owner's computer. It strips process
arguments, module paths and thread names. Its shareable ZIP contains only
selected caller paths and build identity; raw traces and logs remain local.
Before delivery, check synthetic privacy/foreign-PID/cycle cases, compare a
live control with the existing Python parser and reprocess a trace from the
exact installed release through the packaged entry point. Verify ZIP entries,
weight conservation and unchanged input trace. No production runtime change.
