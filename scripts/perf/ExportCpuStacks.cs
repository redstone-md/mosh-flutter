using System;
using Microsoft.Diagnostics.Tracing.Etlx;
using Microsoft.Diagnostics.Tracing.Parsers.Kernel;
using Microsoft.Diagnostics.Tracing.Stacks;
using PerfViewExtensibility;

// PerfView's documented extension boundary; use its stack reader/writer.
public sealed class Commands : CommandEnvironment {
    public void SaveExactCpuStacks(string trace, string processId, string output) {
        try {
            using (var file = OpenETLFile(trace)) {
                TraceProcess target = null;
                foreach (var process in file.Processes) {
                    if (process.ProcessID != int.Parse(processId)) continue;
                    if (target != null) throw new InvalidOperationException("Selected PID reused in trace");
                    target = process;
                }
                if (target == null) throw new InvalidOperationException("Selected PID absent from trace");
                if (!string.Equals(target.Name, "mosh", StringComparison.OrdinalIgnoreCase))
                    throw new InvalidOperationException("Selected process is not Mosh");
                file.SetFilterProcess(target);
                var events = target.EventsInProcess.Filter(e => e is SampledProfileTraceData);
                var source = new MossStackSource(events, target);
                var stacks = new Stacks(CopyStackSource.Clone(source), "CPU", file);
                stacks.LookupWarmSymbols(10);
                stacks.SaveAsXml(output, true, false);
            }
        } catch (Exception error) {
            // The built-in command dispatcher discards the inner stack trace.
            LogFile.WriteLine(error.ToString());
            throw;
        }
    }
}

// Preserve unresolved Go code as RVAs; absolute addresses and module paths stay local.
internal sealed class MossStackSource : TraceEventStackSource {
    private readonly TraceProcess process;

    public MossStackSource(TraceEvents events, TraceProcess process) : base(events) {
        this.process = process;
    }

    public override string GetFrameName(StackSourceFrameIndex frame, bool verbose) {
        string name = base.GetFrameName(frame, verbose);
        if (!name.EndsWith("!?", StringComparison.Ordinal)) return name;
        int index = (int)frame - (int)StackSourceFrameIndex.Start;
        if (index < 0 || index >= TraceLog.CodeAddresses.Count) return name;
        ulong address = TraceLog.CodeAddresses.Address((CodeAddressIndex)index);
        ulong? offset = null;
        foreach (var module in process.LoadedModules) {
            if (!string.Equals(module.Name, "moss", StringComparison.OrdinalIgnoreCase)) continue;
            if (address < module.ImageBase) continue;
            ulong candidate = address - module.ImageBase;
            if (candidate >= (ulong)module.ModuleFile.ImageSize) continue;
            if (offset.HasValue && offset.Value != candidate) return name;
            offset = candidate;
        }
        return offset.HasValue ? "moss!+0x" + offset.Value.ToString("x") : name;
    }
}
