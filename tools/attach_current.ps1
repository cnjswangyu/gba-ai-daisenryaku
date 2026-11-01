param([int]$GamePid=0,[Parameter(Mandatory=$true)][string]$ScriptPath)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type @'
using System; using System.Runtime.InteropServices;
public static class AttachMouse {
 [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
 [DllImport("user32.dll")] public static extern bool SetCursorPos(int x,int y);
 [DllImport("user32.dll")] public static extern void mouse_event(uint f,uint x,uint y,uint d,UIntPtr e);
}
'@
function Windows {
 $diag= & powershell -NoProfile -File "$PSScriptRoot/window_diag.ps1" -GamePid $GamePid | ConvertFrom-Json
 if($diag.Desktop -ne 'Default'){throw 'Run this CMD from your normal Windows desktop.'}
 @($diag.Windows | Where-Object Visible)
}
function Element($w){[System.Windows.Automation.AutomationElement]::FromHandle([intptr]$w.Handle)}
function FindName($e,$name){
 $e.FindFirst([System.Windows.Automation.TreeScope]::Descendants,
  [System.Windows.Automation.PropertyCondition]::new([System.Windows.Automation.AutomationElement]::NameProperty,$name))
}
function Click($e){
 if($null -eq $e){throw 'Required emulator control not found'}
 $r=$e.Current.BoundingRectangle
 if($r.IsEmpty){throw 'Emulator control is not visible'}
 [void][AttachMouse]::SetCursorPos([int]($r.X+$r.Width/2),[int]($r.Y+$r.Height/2))
 [AttachMouse]::mouse_event(2,0,0,0,[uintptr]::Zero)
 [AttachMouse]::mouse_event(4,0,0,0,[uintptr]::Zero)
 Start-Sleep -Milliseconds 250
}
function Expand($e){
 if($null -eq $e){throw 'Required menu not found'}
 $e.GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern).Expand()
 Start-Sleep -Milliseconds 250
}
function PopupItem($name){
 foreach($w in (Windows)){
  if($w.Title -eq '' -and $w.Class -like 'WindowsForms*'){
   $item=FindName (Element $w) $name
   if($item){return $item}
  }
 }
 throw "Menu item not found: $name"
}
$wins=Windows
$games=@($wins | Where-Object {$_.Title -like '*Daisenryaku*BizHawk'})
if($games.Count -ne 1){throw 'Open exactly one Daisenryaku game window, or supply --pid.'}
$game=$games[0]; $GamePid=[int]$game.Pid
[void][AttachMouse]::SetForegroundWindow([intptr]$game.Handle)
$shell=New-Object -ComObject WScript.Shell
$shell.SendKeys('{ESC}') # dismiss host menu only; game keyboard bridge is frame-driven
$console=Windows | Where-Object Title -eq 'Lua Console' | Select-Object -First 1
if(-not $console){
 Expand (FindName (Element $game) 'Tools')
 Click (PopupItem 'Lua Console')
 $console=Windows | Where-Object Title -eq 'Lua Console' | Select-Object -First 1
}
if(-not $console){throw 'Could not open Lua Console'}
[void][AttachMouse]::SetForegroundWindow([intptr]$console.Handle)
# New Session stops old controllers without restarting the emulator or loading state.
Expand (FindName (Element $console) 'File')
Click (PopupItem 'New Session')
foreach($w in (Windows | Where-Object {$_.Class -eq '#32770'})){
 $no=FindName (Element $w) 'No'
 if($no){Click $no}else{throw 'Lua session confirmation is open; close it and run again.'}
}
[void][AttachMouse]::SetForegroundWindow([intptr]$console.Handle)
Start-Sleep -Milliseconds 300
Click (FindName (Element $console) 'Open Script')
$dialog=$null
for($i=0;$i -lt 20;$i++){
 $dialog=Windows | Where-Object {$_.Class -eq '#32770'} | Select-Object -First 1
 if($dialog){break}; Start-Sleep -Milliseconds 200
}
if(-not $dialog){throw 'Open Script file dialog not found'}
[void][AttachMouse]::SetForegroundWindow([intptr]$dialog.Handle)
$shell.SendKeys('%n')
$escaped=$ScriptPath -replace '([+^%~(){}])','{$1}'
$shell.SendKeys($escaped); $shell.SendKeys('{ENTER}')
Start-Sleep -Milliseconds 600
[void][AttachMouse]::SetForegroundWindow([intptr]$game.Handle)
Write-Output "ATTACHED pid=$GamePid"
