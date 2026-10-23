using System;
using Microsoft.Diagnostics.Tracing.Etlx;
using PerfViewExtensibility;

// PerfView's documented extension boundary; use its stack reader/writer.
public sealed class Commands : CommandEnvironment {
    public void SaveExactCpuStacks(string trace, string processId, string output) {
        try {
            using (var file = OpenETLFile(trace)) {
                TraceProcess target = null;
                foreach (var process in file.Processes)
                    if (process.ProcessID == int.Parse(processId)) target = process;
                if (target == null) throw new InvalidOperationException("Selected PID absent from trace");
                file.SetFilterProcess(target);
                var stacks = file.CPUStacks();
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
