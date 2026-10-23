using System;
using System.Reflection;
using Microsoft.Diagnostics.Tracing.Etlx;
using Microsoft.Diagnostics.Tracing.Parsers.Kernel;
using Microsoft.Diagnostics.Tracing.Stacks;

// Compiled only into the CI test extension, never the portable helper.
public sealed partial class Commands {
    public void AssertMossAttribution(string trace, string processId) {
        using (var file = OpenETLFile(trace)) {
            var target = file.Processes.LastProcessWithID(int.Parse(processId));
            TraceLoadedModule moss = null;
            foreach (var module in target.LoadedModules) {
                if (string.Equals(module.Name, "moss", StringComparison.OrdinalIgnoreCase)) moss = module;
            }
            if (moss == null) throw new InvalidOperationException("Moss fixture module absent");
            var events = target.EventsInProcess.Filter(e => e is SampledProfileTraceData);
            var plain = new TraceEventStackSource(events);
            var mapped = new MossStackSource(events, target);
            AssertConflict(plain, mapped, moss.ModuleFile, false);
            AssertConflict(plain, mapped, moss.ModuleFile, true);
            LogFile.WriteLine("Unassigned and explicitly non-Moss frames retain their attribution.");
        }
    }

    private static void AssertConflict(TraceEventStackSource plain, MossStackSource mapped,
                                      TraceModuleFile moss, bool associated) {
        var log = plain.TraceLog;
        for (int i = 0; i < log.CodeAddresses.Count; i++) {
            var code = (CodeAddressIndex)i;
            var moduleIndex = log.CodeAddresses.ModuleFileIndex(code);
            if ((moduleIndex != ModuleFileIndex.Invalid) != associated) continue;
            if (associated && string.Equals(log.CodeAddresses.ModuleFiles[moduleIndex].Name,
                                           "moss", StringComparison.OrdinalIgnoreCase)) continue;
            var frame = (StackSourceFrameIndex)((int)StackSourceFrameIndex.Start + i);
            string expected = plain.GetFrameName(frame, false);
            if (!expected.EndsWith("!?", StringComparison.Ordinal)) continue;
            ulong address = log.CodeAddresses.Address(code);
            if (address < 65536 || address >= 0x800000000000UL) continue;
            // Simulate an old Moss load overlapping this frame in the private TraceLog only.
            var imageBase = typeof(TraceModuleFile).GetField("imageBase", BindingFlags.Instance | BindingFlags.NonPublic);
            object saved = imageBase.GetValue(moss);
            try {
                imageBase.SetValue(moss, address - 128);
                if (mapped.GetFrameName(frame, false) != expected)
                    throw new InvalidOperationException("Conflicting frame was relabeled as Moss");
            } finally {
                imageBase.SetValue(moss, saved);
            }
            return;
        }
        throw new InvalidOperationException("Conflict fixture has no matching unresolved frame");
    }
}
