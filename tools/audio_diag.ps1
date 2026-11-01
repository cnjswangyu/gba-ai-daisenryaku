param([switch]$UnmuteEmulator)
$ErrorActionPreference='Stop'
# Inspect Windows audio sessions without touching emulator/game input.
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Collections.Generic;
using System.Diagnostics;
namespace GbaAudio {
 [ComImport,Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")] class Enumerator {}
 [ComImport,Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"),InterfaceType(ComInterfaceType.InterfaceIsIUnknown)] interface Devices {
  void EnumAudioEndpoints(int flow,uint mask,out IntPtr devices);
  void GetDefaultAudioEndpoint(int flow,int role,out Device device);
  void GetDevice([MarshalAs(UnmanagedType.LPWStr)] string id,out Device device);
 }
 [ComImport,Guid("D666063F-1587-4E43-81F1-B948E807363F"),InterfaceType(ComInterfaceType.InterfaceIsIUnknown)] interface Device {
  void Activate(ref Guid iid,uint context,IntPtr parameters,[MarshalAs(UnmanagedType.IUnknown)] out object obj);
  void OpenPropertyStore(int mode,out IntPtr properties);
  void GetId([MarshalAs(UnmanagedType.LPWStr)] out string id);
 }
 [ComImport,Guid("77AA99A0-1BD6-484F-8BC7-2C654C9A9B6F"),InterfaceType(ComInterfaceType.InterfaceIsIUnknown)] interface Manager {
  void GetAudioSessionControl(IntPtr guid,uint flags,out IntPtr control);
  void GetSimpleAudioVolume(IntPtr guid,uint flags,out IntPtr volume);
  void GetSessionEnumerator(out Sessions sessions);
 }
 [ComImport,Guid("E2F5BB11-0570-40CA-ACDD-3AA01277DEE8"),InterfaceType(ComInterfaceType.InterfaceIsIUnknown)] interface Sessions {
  void GetCount(out int count);
  void GetSession(int index,out Control control);
 }
 [ComImport,Guid("BFB7FF88-7239-4FC9-8FA2-07C950BE9C6D"),InterfaceType(ComInterfaceType.InterfaceIsIUnknown)] interface Control {
  void GetState(out int state);
  void GetDisplayName([MarshalAs(UnmanagedType.LPWStr)] out string name);
  void SetDisplayName([MarshalAs(UnmanagedType.LPWStr)] string name,IntPtr context);
  void GetIconPath([MarshalAs(UnmanagedType.LPWStr)] out string path);
  void SetIconPath([MarshalAs(UnmanagedType.LPWStr)] string path,IntPtr context);
  void GetGroupingParam(out Guid grouping);
  void SetGroupingParam(ref Guid grouping,IntPtr context);
  void RegisterAudioSessionNotification(IntPtr notification);
  void UnregisterAudioSessionNotification(IntPtr notification);
  void GetSessionIdentifier([MarshalAs(UnmanagedType.LPWStr)] out string id);
  void GetSessionInstanceIdentifier([MarshalAs(UnmanagedType.LPWStr)] out string id);
  void GetProcessId(out uint pid);
 }
 [ComImport,Guid("87CE5498-68D6-44E5-9215-6DA47EF883D8"),InterfaceType(ComInterfaceType.InterfaceIsIUnknown)] interface Volume {
  void SetMasterVolume(float value,IntPtr context);
  void GetMasterVolume(out float value);
  void SetMute([MarshalAs(UnmanagedType.Bool)] bool mute,IntPtr context);
  void GetMute([MarshalAs(UnmanagedType.Bool)] out bool mute);
 }
 public class Row {public string Endpoint;public uint Pid;public string Process;public int State;public bool Muted;public float Volume;public bool Changed;}
 public static class Probe {
  public static Row[] Run(bool fix) {
   var rows=new List<Row>();var devices=(Devices)new Enumerator();
   var seen=new HashSet<string>();
   for(int role=0;role<3;role++) {
    Device dev;devices.GetDefaultAudioEndpoint(0,role,out dev);
    string endpoint;dev.GetId(out endpoint);if(!seen.Add(endpoint))continue;
    object obj;Guid iid=new Guid("77AA99A0-1BD6-484F-8BC7-2C654C9A9B6F");
    dev.Activate(ref iid,23,IntPtr.Zero,out obj);Sessions sessions;((Manager)obj).GetSessionEnumerator(out sessions);
    int count;sessions.GetCount(out count);
    for(int i=0;i<count;i++) {
     Control ctrl;sessions.GetSession(i,out ctrl);uint pid;int state;
     ctrl.GetProcessId(out pid);ctrl.GetState(out state);
     string name="system";try {if(pid!=0)name=Process.GetProcessById((int)pid).ProcessName;}catch {name="exited";}
     var vol=(Volume)ctrl;bool mute;float level;vol.GetMute(out mute);vol.GetMasterVolume(out level);
     bool changed=false;
     if(fix && name.Equals("EmuHawk",StringComparison.OrdinalIgnoreCase)) {
      if(mute){vol.SetMute(false,IntPtr.Zero);mute=false;changed=true;}
      if(level<0.01f){vol.SetMasterVolume(1f,IntPtr.Zero);level=1f;changed=true;}
     }
     rows.Add(new Row {Endpoint=endpoint,Pid=pid,Process=name,State=state,Muted=mute,Volume=level,Changed=changed});
    }
   }
   return rows.ToArray();
  }
 }
}
'@
[GbaAudio.Probe]::Run($UnmuteEmulator.IsPresent) | ConvertTo-Json -Depth 3
