# Issue 94: exact-process CPU attribution

The owner's `cpu-20261023-000926` capture matches all five `cd6df31b` binaries.
After sixteen minutes of warmup it records 12.909% of one core, 1.474 Mbit/s
mean network and 190.55 MiB median working set. Network control and byte sums
pass with zero event loss. Those process counters remain usable.

The two CPU exports disagree: CSV reports 11,078 weights and 673 for Moss;
PID-filtered instruction data contains 9,924 weights and 2,469 for Moss.
All 1,429 Rust weights resolve with the original PDB. Go ranges resolve
2,464 of 2,469 weights. CSV-derived module percentages cannot be used here.

The collector selects CSV data by process name and greatest CPU, while raw
instruction export selects the requested PID. PerfView v4.0.0 implements that
name-based selection in `SaveCPUStacksAsCsv`. That is unsafe for two matching
process names. The precise origin of every owner CSV misattribution cannot
be recovered without the private raw trace; do not assert it is established.

## Scope and checks

1. Extend the real Windows control test with a busier, same-name process and
   require summary weights to reconcile with the selected PID's raw samples.
   Run the regression before changing the collector.
2. Build the existing module-summary shape directly from PID-filtered
   instruction aggregates. Keep kernel and unmapped samples explicit; a
   kernel bucket is not an individual driver attribution. Remove the
   redundant, name-selected CSV export.
3. Test mapped, kernel-only, unmapped and foreign-PID input, plus the live
   same-name control. Retain ZIP privacy and actual network controls.
4. Run Windows diagnostics, independent Standards/Spec and CodeAnt review.
   Record the owner observations and corrected attribution limits.

Only diagnostic scripts and documentation change. No Mosh/Moss runtime,
public bridge contract, dependency or stored schema change. Existing JSON
field names and ZIP contents remain; module names remain diagnostic values.
Existing owner data can be analyzed without another recording. Further
application optimization requires a reproducible caller-level cost after
this attribution correction. Whole-Windows and Android acceptance stay open.
