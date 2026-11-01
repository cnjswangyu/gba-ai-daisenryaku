param([int]$GamePid = 0, [switch]$Show, [switch]$Place)
Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class GbaWindows {
 public delegate bool EnumProc(IntPtr h, IntPtr arg);
 [StructLayout(LayoutKind.Sequential)] public struct Rect { public int Left, Top, Right, Bottom; }
 [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc p, IntPtr a);
 [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
 [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h,StringBuilder b,int n);
 [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h,StringBuilder b,int n);
 [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
 [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
 [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h,out Rect r);
 [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h,int n);
 [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h,IntPtr after,int x,int y,int w,int ht,uint flags);
 [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
 [DllImport("user32.dll")] public static extern IntPtr GetThreadDesktop(uint thread);
 [DllImport("user32.dll")] public static extern IntPtr GetProcessWindowStation();
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] public static extern bool GetUserObjectInformation(IntPtr obj,int index,StringBuilder b,int n,out int required);
 [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
 public static string ObjectName(IntPtr obj) { int n; var b=new StringBuilder(256); return GetUserObjectInformation(obj,2,b,512,out n)?b.ToString():"unknown"; }
}
'@
$targetGames = @(Get-Process EmuHawk -ErrorAction SilentlyContinue | Where-Object { $GamePid -eq 0 -or $_.Id -eq $GamePid })
$gameIds = @($targetGames | ForEach-Object Id)
$diagWindows = [System.Collections.Generic.List[object]]::new()
$enumerateGameWindows = [GbaWindows+EnumProc] {
 param($handle,$arg)
 [uint32]$ownerPid = 0
 $thread = [GbaWindows]::GetWindowThreadProcessId($handle,[ref]$ownerPid)
 if ($gameIds -contains [int]$ownerPid) {
  $title=[System.Text.StringBuilder]::new(256)
  $class=[System.Text.StringBuilder]::new(256)
  [void][GbaWindows]::GetWindowText($handle,$title,256)
  [void][GbaWindows]::GetClassName($handle,$class,256)
  $rect=[GbaWindows+Rect]::new()
  [void][GbaWindows]::GetWindowRect($handle,[ref]$rect)
  $visible=[GbaWindows]::IsWindowVisible($handle)
  if ($Show -and $visible -and $title.ToString() -like '*BizHawk' -and $rect.Right-$rect.Left -gt 100 -and $rect.Bottom-$rect.Top -gt 100) {
   [void][GbaWindows]::ShowWindow($handle,9)
   if ($Place) { [void][GbaWindows]::SetWindowPos($handle,[IntPtr]::Zero,80,80,1000,760,0x0040) }
   else { [void][GbaWindows]::SetWindowPos($handle,[IntPtr]::Zero,0,0,0,0,0x0043) }
   [void][GbaWindows]::SetForegroundWindow($handle)
   [void][GbaWindows]::GetWindowRect($handle,[ref]$rect)
  }
  $diagWindows.Add([pscustomobject]@{Pid=$ownerPid;Handle=$handle.ToInt64();Title=$title.ToString();Class=$class.ToString();Visible=$visible;Minimized=[GbaWindows]::IsIconic($handle);Rect=@($rect.Left,$rect.Top,$rect.Right,$rect.Bottom);Desktop=[GbaWindows]::ObjectName([GbaWindows]::GetThreadDesktop($thread))})
 }
 return $true
}
[void][GbaWindows]::EnumWindows($enumerateGameWindows,[IntPtr]::Zero)
[pscustomobject]@{Session=[System.Diagnostics.Process]::GetCurrentProcess().SessionId;WindowStation=[GbaWindows]::ObjectName([GbaWindows]::GetProcessWindowStation());Desktop=[GbaWindows]::ObjectName([GbaWindows]::GetThreadDesktop([GbaWindows]::GetCurrentThreadId()));GameSessions=@($targetGames | ForEach-Object { @{Pid=$_.Id;Session=$_.SessionId} });Windows=$diagWindows.ToArray()} | ConvertTo-Json -Depth 6
