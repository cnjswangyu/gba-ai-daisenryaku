param([Parameter(Mandatory=$true)][string]$ScriptPath)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type @'
using System; using System.Runtime.InteropServices;
public static class AttachMouse2 {
 [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
 [DllImport("user32.dll")] public static extern bool SetCursorPos(int x,int y);
 [DllImport("user32.dll")] public static extern void mouse_event(uint f,uint x,uint y,uint d,UIntPtr e);
}
'@
function Windows { @($(Get-Process).Where({$_.MainWindowHandle -ne 0}) | ForEach-Object {
  [pscustomobject]@{ Handle=$_.MainWindowHandle; Title=$_.MainWindowTitle; Pid=$_.Id } }) }
function Click([IntPtr]$h){
 [AttachMouse2]::SetForegroundWindow($h) | Out-Null
 Start-Sleep -Milliseconds 150
}
function FindName($e,$name){
 $e.FindFirst([System.Windows.Automation.TreeScope]::Descendants,
  [System.Windows.Automation.PropertyCondition]::new([System.Windows.Automation.AutomationElement]::NameProperty,$name))
}
function FindId($e,$id){
 $e.FindFirst([System.Windows.Automation.TreeScope]::Descendants,
  [System.Windows.Automation.PropertyCondition]::new([System.Windows.Automation.AutomationElement]::AutomationIdProperty,$id))
}
function ClickEl($e){
 $r=$e.Current.BoundingRectangle
 [void][AttachMouse2]::SetCursorPos([int]($r.X+$r.Width/2),[int]($r.Y+$r.Height/2))
 [AttachMouse2]::mouse_event(2,0,0,0,[uintptr]::Zero)
 [AttachMouse2]::mouse_event(4,0,0,0,[uintptr]::Zero)
 Start-Sleep -Milliseconds 250
}
$console = [System.Windows.Automation.AutomationElement]::RootElement.FindFirst(
  [System.Windows.Automation.TreeScope]::Children,
  [System.Windows.Automation.PropertyCondition]::new(
    [System.Windows.Automation.AutomationElement]::NameProperty,'Lua Console'))
if(-not $console){throw 'Lua Console not open'}
ClickEl (FindName $console 'Open Script')
$dialog=$null
for($i=0;$i -lt 30;$i++){
 $dialog=[System.Windows.Automation.AutomationElement]::RootElement.FindFirst(
  [System.Windows.Automation.TreeScope]::Children,
  [System.Windows.Automation.PropertyCondition]::new(
    [System.Windows.Automation.AutomationElement]::ClassNameProperty,'#32770'))
 if($dialog){break}; Start-Sleep -Milliseconds 200
}
if(-not $dialog){throw 'Open Script dialog not found'}
$edit = FindId $dialog '1148'
if(-not $edit){ $edit = $dialog.FindFirst([System.Windows.Automation.TreeScope]::Descendants,
  [System.Windows.Automation.PropertyCondition]::new([System.Windows.Automation.AutomationElement]::ControlTypeProperty,
   [System.Windows.Automation.ControlType]::Edit)) }
if(-not $edit){throw 'filename edit not found'}
$edit.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).SetValue($ScriptPath)
Start-Sleep -Milliseconds 200
$ok = FindId $dialog '1'
if($ok){ ClickEl $ok } else { $edit.SetFocus(); (New-Object -ComObject WScript.Shell).SendKeys('{ENTER}') }
Start-Sleep -Milliseconds 800
Write-Output "SCRIPT-OPENED $ScriptPath"
