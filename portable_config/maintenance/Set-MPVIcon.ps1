param(
    [Parameter(Mandatory=$true)][string]$ExecutablePath,
    [Parameter(Mandatory=$true)][string]$IconPath,
    [switch]$InspectOnly
)
$ErrorActionPreference='Stop'
if($PSVersionTable.PSVersion.Major -eq 5) { $env:PSModulePath=[Environment]::GetEnvironmentVariable('PSModulePath','Machine') }
if(-not ('MpvLampa.IconResource' -as [type])) {
Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.ComponentModel;
namespace MpvLampa {
public static class IconResource {
    delegate bool NameCallback(IntPtr module, IntPtr type, IntPtr name, IntPtr param);
    delegate bool LangCallback(IntPtr module, IntPtr type, IntPtr name, ushort lang, IntPtr param);
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    static extern IntPtr LoadLibraryExW(string path, IntPtr file, uint flags);
    [DllImport("kernel32.dll")] static extern bool FreeLibrary(IntPtr module);
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    static extern bool EnumResourceNamesW(IntPtr module, IntPtr type, NameCallback callback, IntPtr param);
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    static extern bool EnumResourceLanguagesW(IntPtr module, IntPtr type, IntPtr name, LangCallback callback, IntPtr param);
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    static extern IntPtr BeginUpdateResourceW(string path, bool deleteExisting);
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    static extern bool UpdateResourceW(IntPtr update, IntPtr type, IntPtr name, ushort lang, byte[] data, uint size);
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    static extern bool EndUpdateResourceW(IntPtr update, bool discard);
    class Resource { public int Type; public int Id; public string Name; public ushort Lang; }
    static List<Resource> ReadIcons(string path) {
        var result=new List<Resource>();
        IntPtr module=LoadLibraryExW(path,IntPtr.Zero,0x22);
        if(module==IntPtr.Zero) throw new Win32Exception();
        try {
            foreach(int type in new int[]{3,14}) {
                NameCallback names=delegate(IntPtr m,IntPtr t,IntPtr n,IntPtr p) {
                    bool numeric=((ulong)n.ToInt64()>>16)==0;
                    int id=numeric?n.ToInt32():0;
                    string name=numeric?null:Marshal.PtrToStringUni(n);
                    LangCallback langs=delegate(IntPtr lm,IntPtr lt,IntPtr ln,ushort lang,IntPtr lp) {
                        result.Add(new Resource{Type=type,Id=id,Name=name,Lang=lang});return true;
                    };
                    if(!EnumResourceLanguagesW(m,t,n,langs,IntPtr.Zero)) throw new Win32Exception();
                    return true;
                };
                if(!EnumResourceNamesW(module,(IntPtr)type,names,IntPtr.Zero)) {
                    int error=Marshal.GetLastWin32Error();
                    if(error!=1813 && error!=1814) throw new Win32Exception(error);
                }
            }
        } finally { FreeLibrary(module); }
        return result;
    }
    static void Put(IntPtr update,Resource resource,byte[] data) {
        IntPtr name=resource.Name==null?(IntPtr)resource.Id:Marshal.StringToHGlobalUni(resource.Name);
        try {
            if(!UpdateResourceW(update,(IntPtr)resource.Type,name,resource.Lang,data,data==null?0:(uint)data.Length))
                throw new Win32Exception();
        } finally { if(resource.Name!=null) Marshal.FreeHGlobal(name); }
    }
    public static string Describe(string path) {
        var resources=ReadIcons(path);int icons=0,groups=0;
        foreach(var r in resources) if(r.Type==3) icons++;else groups++;
        return "Icon images: "+icons+"; icon groups: "+groups;
    }
    public static void Apply(string path,string iconPath) {
        byte[] ico=File.ReadAllBytes(iconPath);
        if(ico.Length<6 || BitConverter.ToUInt16(ico,0)!=0 || BitConverter.ToUInt16(ico,2)!=1)
            throw new InvalidDataException("Invalid ICO header");
        int count=BitConverter.ToUInt16(ico,4);
        if(count==0 || count>256 || ico.Length<6+16*count) throw new InvalidDataException("Invalid ICO directory");
        var images=new List<byte[]>();
        byte[] group=new byte[6+14*count];Buffer.BlockCopy(ico,0,group,0,6);
        for(int i=0;i<count;i++) {
            int entry=6+16*i;uint size=BitConverter.ToUInt32(ico,entry+8),offset=BitConverter.ToUInt32(ico,entry+12);
            if(size==0 || (ulong)size+offset>(ulong)ico.Length) throw new InvalidDataException("Invalid ICO image");
            byte[] image=new byte[size];Buffer.BlockCopy(ico,(int)offset,image,0,(int)size);images.Add(image);
            Buffer.BlockCopy(ico,entry,group,6+14*i,12);
            Buffer.BlockCopy(BitConverter.GetBytes((ushort)(i+1)),0,group,6+14*i+12,2);
        }
        var resources=ReadIcons(path);
        var groups=new List<Resource>();var languages=new HashSet<ushort>();
        foreach(var r in resources) if(r.Type==14) { groups.Add(r);languages.Add(r.Lang); }
        if(groups.Count==0) { groups.Add(new Resource{Type=14,Id=1,Lang=0});languages.Add(0); }
        IntPtr update=BeginUpdateResourceW(path,false);
        if(update==IntPtr.Zero) throw new Win32Exception();
        try {
            // Only icon resources are replaced. All other resources and code remain intact.
            foreach(var r in resources) if(r.Type==3) Put(update,r,null);
            foreach(ushort lang in languages)
                for(int i=0;i<count;i++) Put(update,new Resource{Type=3,Id=i+1,Lang=lang},images[i]);
            foreach(var r in groups) Put(update,r,group);
            bool success=EndUpdateResourceW(update,false);update=IntPtr.Zero;
            if(!success) throw new Win32Exception();
        } finally { if(update!=IntPtr.Zero) EndUpdateResourceW(update,true); }
    }
}
}
'@
}
$ExecutablePath=(Resolve-Path -LiteralPath $ExecutablePath).Path
$IconPath=(Resolve-Path -LiteralPath $IconPath).Path
if($InspectOnly) { [MpvLampa.IconResource]::Describe($ExecutablePath);return }
$signature=Get-AuthenticodeSignature -LiteralPath $ExecutablePath
if($signature.Status -ne 'NotSigned') { throw 'Icon replacement requires an unsigned mpv binary; signed files are left unchanged.' }
[MpvLampa.IconResource]::Apply($ExecutablePath,$IconPath)
