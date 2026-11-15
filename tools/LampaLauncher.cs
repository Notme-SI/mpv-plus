// Compatibility entry point for Lampa Desktop's fixed player-name list.
// The actual player and all configuration live in the parent mpv+ directory.
using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Threading;
internal static class LampaLauncher {
    [StructLayout(LayoutKind.Sequential)]
    private struct FlashInfo {
        public uint Size;
        public IntPtr Window;
        public uint Flags, Count, Timeout;
    }

    [DllImport("user32.dll")] private static extern bool SetForegroundWindow(IntPtr window);
    [DllImport("user32.dll")] private static extern bool IsIconic(IntPtr window);
    [DllImport("user32.dll")] private static extern bool ShowWindowAsync(IntPtr window, int command);
    [DllImport("user32.dll")] private static extern bool FlashWindowEx(ref FlashInfo info);
    [DllImport("user32.dll")] private static extern bool AllowSetForegroundWindow(int processId);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)]
    private static extern int MessageBox(IntPtr window, string text, string caption, uint type);

    private static void Activate(IntPtr window) {
        if (IsIconic(window)) ShowWindowAsync(window, 9); // SW_RESTORE
        if (SetForegroundWindow(window)) return;
        var info = new FlashInfo { Size = (uint)Marshal.SizeOf(typeof(FlashInfo)),
            Window = window, Flags = 2, Count = 3 }; // FLASHW_TRAY
        FlashWindowEx(ref info);
    }

    private static string SelectedMedia(string[] args) {
        var media = new System.Collections.Generic.List<string>();
        int selected = 0;
        bool filesOnly = false;
        foreach (string arg in args) {
            if (!filesOnly && arg == "--") { filesOnly = true; continue; }
            if (!filesOnly && arg.StartsWith("--playlist-start=", StringComparison.Ordinal)) {
                int.TryParse(arg.Substring("--playlist-start=".Length), out selected);
            }
            if (filesOnly || !arg.StartsWith("-", StringComparison.Ordinal)) media.Add(arg);
        }
        return selected >= 0 && selected < media.Count ? media[selected] : null;
    }

    private static int Run(ProcessStartInfo start, string media) {
        if (String.IsNullOrEmpty(media)) {
            using (var child = Process.Start(start)) { child.WaitForExit(); return child.ExitCode; }
        }
        string key;
        using (var sha = SHA256.Create()) {
            var bytes = Encoding.UTF8.GetBytes(start.WorkingDirectory.ToUpperInvariant() + "\n" + media);
            key = @"Local\mpv-plus-" + BitConverter.ToString(sha.ComputeHash(bytes)).Replace("-", "");
        }
        // Open the event before the mutex so a duplicate can always notify the owner.
        using (var activate = new EventWaitHandle(false, EventResetMode.AutoReset, key + "-activate"))
        using (var mutex = new Mutex(false, key + "-launch")) {
            bool owns;
            try { owns = mutex.WaitOne(0); }
            catch (AbandonedMutexException) { owns = true; }
            if (!owns) { activate.Set(); return 0; }
            try {
                using (var child = Process.Start(start)) {
                    AllowSetForegroundWindow(child.Id);
                    bool pending = true;
                    bool shown = false;
                    while (!child.HasExited) {
                        pending |= activate.WaitOne(100);
                        if (!pending) continue;
                        child.Refresh();
                        if (child.HasExited) break;
                        IntPtr window = child.MainWindowHandle;
                        if (window == IntPtr.Zero) continue;
                        Activate(window);
                        pending = false;
                        shown = true;
                    }
                    if (child.ExitCode != 0 && !shown) {
                        MessageBox(IntPtr.Zero, "Не удалось открыть видео.", "mpv+", 0x00040010);
                    }
                    return child.ExitCode;
                }
            } finally { mutex.ReleaseMutex(); }
        }
    }
    private static string Quote(string value) {
        var result = new StringBuilder("\"");
        int slashes = 0;
        foreach (char c in value) {
            if (c == '\\') { slashes++; continue; }
            if (c == '"') result.Append('\\', slashes * 2 + 1);
            else result.Append('\\', slashes);
            slashes = 0;
            result.Append(c);
        }
        return result.Append('\\', slashes * 2).Append('"').ToString();
    }
    [STAThread]
    public static int Main(string[] args) {
        string root = AppDomain.CurrentDomain.BaseDirectory;
        if (!File.Exists(Path.Combine(root, "mpv+.exe"))) root = Directory.GetParent(root.TrimEnd(Path.DirectorySeparatorChar)).FullName;
        string media = SelectedMedia(args);
        var command = new StringBuilder(String.IsNullOrEmpty(media) ? "" : "--force-window=immediate");
        foreach (string arg in args) { if (command.Length > 0) command.Append(' '); command.Append(Quote(arg)); }
        var start = new ProcessStartInfo(Path.Combine(root, "mpv+.exe"), command.ToString());
        start.UseShellExecute = false;
        start.WorkingDirectory = root;
        try { return Run(start, media); }
        catch {
            MessageBox(IntPtr.Zero, "Не удалось запустить mpv+.", "mpv+", 0x00040010);
            return 1;
        }
    }
}
