# Stop only the collector's unique ETW session and read its final loss counters.
function Stop-MoshNetworkTrace([string]$SessionName) {
    if (-not ('MoshTraceControl' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
public static class MoshTraceControl {
    [StructLayout(LayoutKind.Sequential)] struct Wnode {
        public uint BufferSize, ProviderId;
        public ulong HistoricalContext;
        public long TimeStamp;
        public Guid Guid;
        public uint ClientContext, Flags;
    }
    [StructLayout(LayoutKind.Sequential)] struct Properties {
        public Wnode Wnode;
        public uint BufferSize, MinimumBuffers, MaximumBuffers, MaximumFileSize;
        public uint LogFileMode, FlushTimer, EnableFlags;
        public int AgeLimit;
        public uint NumberOfBuffers, FreeBuffers, EventsLost, BuffersWritten;
        public uint LogBuffersLost, RealTimeBuffersLost;
        public IntPtr LoggerThreadId;
        public uint LogFileNameOffset, LoggerNameOffset;
    }
    [DllImport("advapi32.dll", CharSet=CharSet.Unicode, EntryPoint="ControlTraceW")]
    static extern uint ControlTrace(ulong handle, string name, IntPtr props, uint code);
    public static uint[] Stop(string name) {
        int header = Marshal.SizeOf(typeof(Properties));
        int length = header + 4096;
        IntPtr buffer = Marshal.AllocHGlobal(length);
        try {
            Marshal.Copy(new byte[length], 0, buffer, length);
            var props = new Properties();
            props.Wnode.BufferSize = (uint)length;
            props.LoggerNameOffset = (uint)header;
            props.LogFileNameOffset = (uint)(header + 2048);
            Marshal.StructureToPtr(props, buffer, false);
            uint status = ControlTrace(0, name, buffer, 1);
            if (status != 0) throw new Win32Exception((int)status);
            props = (Properties)Marshal.PtrToStructure(buffer, typeof(Properties));
            return new uint[] { props.EventsLost, props.LogBuffersLost, props.RealTimeBuffersLost };
        } finally { Marshal.FreeHGlobal(buffer); }
    }
}
'@
    }
    $loss = [MoshTraceControl]::Stop($SessionName)
    return @{ events_lost = $loss[0]; log_buffers_lost = $loss[1]; realtime_buffers_lost = $loss[2] }
}
