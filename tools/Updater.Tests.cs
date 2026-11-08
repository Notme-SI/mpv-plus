using System;
using System.Collections.Generic;
using System.IO;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
internal static class UpdaterTests {
    [DllImport("shell32.dll", CharSet=CharSet.Unicode)] private static extern IntPtr CommandLineToArgvW(string command, out int count);
    [DllImport("kernel32.dll")] private static extern IntPtr LocalFree(IntPtr memory);
    private static void Assert(bool condition, string message) { if (!condition) throw new Exception(message); }
    private static void Reject(Action action) { bool rejected=false; try { action(); } catch (InvalidDataException) { rejected=true; } Assert(rejected,"Unsafe release metadata must be rejected"); }
    [STAThread] public static int Main() {
        Assert(UpdateData.VersionOf("v1.1.10") > UpdateData.VersionOf("1.1.9"),"Compare numeric versions");
        Reject(delegate { UpdateData.VersionOf("v1.1.3-preview"); });
        string[] inputs={"C:\\mpv+\\", "C:\\My Player\\mpv+.exe", "имя с пробелами", "value\"quoted", "\\\\server\\folder\\"};
        foreach(string value in inputs) {
            int count; IntPtr parsed=CommandLineToArgvW("updater.exe "+UpdateData.Quote(value),out count);
            try { Assert(count==2 && Marshal.PtrToStringUni(Marshal.ReadIntPtr(parsed,IntPtr.Size))==value,"Arguments survive Windows command-line parsing"); } finally { LocalFree(parsed); }
        }
        string metadata="{\"tag_name\":\"v1.2.0\",\"draft\":false,\"prerelease\":false,\"assets\":[{\"name\":\"mpv+-1.2.0-Setup.exe\",\"browser_download_url\":\"https://github.com/Notme-SI/mpv-plus/releases/download/v1.2.0/mpv%2B-1.2.0-Setup.exe\",\"digest\":\"sha256:"+new string('a',64)+"\"}]}";
        Assert(UpdateData.Text(UpdateData.SetupAsset(UpdateData.Parse(metadata)),"name")=="mpv+-1.2.0-Setup.exe","Select the exact release installer");
        Reject(delegate { UpdateData.SetupAsset(UpdateData.Parse(metadata.Replace("github.com/Notme-SI","example.com/Notme-SI"))); });
        Reject(delegate { UpdateData.SetupAsset(UpdateData.Parse(metadata.Replace("sha256:","sha1:"))); });
        Reject(delegate { UpdateData.SetupAsset(UpdateData.Parse(metadata.Replace("\"draft\":false","\"draft\":true"))); });
        Reject(delegate { UpdateData.SetupAsset(UpdateData.Parse(metadata.Replace("-Setup.exe\",","-Other.exe\","))); });
        var partial = UpdateData.Parse("{\"result\":\"partial\",\"updated\":2,\"skipped\":1}");
        Assert(UpdateData.IsComponentResult("Update",1,partial),"A committed partial update is a result, not a fatal error");
        Assert(!UpdateData.IsComponentResult("Update",1,null),"A failed update without a final report is fatal");
        Assert(!UpdateData.IsComponentResult("Update",1,UpdateData.Parse("{\"result\":\"checked\"}")),"A preflight report cannot confirm installation");
        Assert(!UpdateData.IsComponentResult("Update",1,UpdateData.Parse("{\"result\":\"updated\"}")),"A nonzero exit cannot report full success");
        string file=Path.GetTempFileName();
        try {
            File.WriteAllText(file,"fixture",Encoding.UTF8); string digest;
            using(var sha=SHA256.Create()) digest="sha256:"+BitConverter.ToString(sha.ComputeHash(File.ReadAllBytes(file))).Replace("-","").ToLowerInvariant();
            UpdateData.VerifyHash(file,digest);
            File.AppendAllText(file,"changed"); Reject(delegate { UpdateData.VerifyHash(file,digest); });
        } finally { File.Delete(file); }
        Console.WriteLine("NATIVE_UPDATER_TESTS_OK"); return 0;
    }
}
