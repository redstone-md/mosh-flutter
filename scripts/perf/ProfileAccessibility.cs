using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using Accessibility;

// Flutter 3.44 exposes MSAA; its UIA provider is disabled by default.
public static class ProfileAccessibility {
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    static extern IntPtr FindWindowEx(IntPtr parent, IntPtr after, string name, string title);
    [DllImport("oleacc.dll")]
    static extern int AccessibleObjectFromWindow(IntPtr hwnd, uint id, ref Guid iid,
        [MarshalAs(UnmanagedType.Interface)] out IAccessible value);
    [DllImport("oleacc.dll")]
    static extern int AccessibleChildren(IAccessible parent, int start, int count,
        [Out, MarshalAs(UnmanagedType.LPArray, ArraySubType = UnmanagedType.Struct, SizeParamIndex = 2)] object[] children,
        out int obtained);

    public sealed class Row {
        public string Name;
        public int X, Y, Width, Height;
    }

    public static Row[] Read(IntPtr window) {
        var rows = new List<Row>();
        IntPtr view = FindWindowEx(window, IntPtr.Zero, "FLUTTERVIEW", null);
        if (view == IntPtr.Zero) return rows.ToArray();
        Guid iid = new Guid("618736e0-3c3d-11cf-810c-00aa00389b71");
        IAccessible root;
        if (AccessibleObjectFromWindow(view, unchecked((uint)-4), ref iid, out root) == 0) {
            try { Walk(root, rows, 0); }
            finally { Marshal.ReleaseComObject(root); }
        }
        return rows.ToArray();
    }

    static void Add(IAccessible value, object id, List<Row> rows) {
        var row = new Row { Name = value.get_accName(id) ?? "" };
        value.accLocation(out row.X, out row.Y, out row.Width, out row.Height, id);
        rows.Add(row);
    }

    static void Walk(IAccessible value, List<Row> rows, int depth) {
        if (depth > 40 || rows.Count > 5000) return;
        Add(value, 0, rows);
        int count = value.accChildCount;
        if (count <= 0) return;
        var children = new object[Math.Min(count, 5000)];
        int obtained;
        if (AccessibleChildren(value, 0, children.Length, children, out obtained) < 0) return;
        for (int i = 0; i < obtained; i++) {
            var child = children[i] as IAccessible;
            try {
                if (child != null) Walk(child, rows, depth + 1);
                else if (children[i] is int) Add(value, children[i], rows);
            } catch (COMException) { /* The live tree can change during traversal. */ }
            finally { if (child != null) Marshal.ReleaseComObject(child); }
        }
    }
}
