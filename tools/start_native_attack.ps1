$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$runDir = Join-Path $projectRoot 'shots\native_attack'
$emulatorPath = Join-Path $projectRoot 'tools\EmuHawk.exe'
$pidFile = Join-Path $runDir 'emulator_pid.txt'
$game = $null
if (Test-Path -LiteralPath $pidFile) {
    $savedPid = 0
    if ([int]::TryParse((Get-Content -LiteralPath $pidFile -Raw).Trim(), [ref]$savedPid)) {
        $candidate = Get-Process -Id $savedPid -ErrorAction SilentlyContinue
        if ($candidate -and $candidate.ProcessName -eq 'EmuHawk' -and $candidate.Path -eq $emulatorPath) {
            $game = $candidate
        }
    }
}
if (-not $game) {
    $pythonCommand = Get-Command python -ErrorAction SilentlyContinue
    $pythonPath = if ($pythonCommand) { $pythonCommand.Source } else { 'C:\ProgramData\anaconda3\python.exe' }
    Push-Location -LiteralPath $projectRoot
    try {
        & $pythonPath (Join-Path $projectRoot 'tools\native_attack.py') --build --load first_clear_start
        if ($LASTEXITCODE -ne 0) { throw 'Native attack bridge build failed.' }
        $romArg = '"' + (Join-Path $projectRoot 'roms\0219 - Daisenryaku.gba') + '"'
        $luaArg = '--lua="' + (Join-Path $projectRoot 'lua\native_attack.lua') + '"'
        $game = Start-Process -FilePath $emulatorPath -ArgumentList $romArg,$luaArg `
            -WorkingDirectory $projectRoot -WindowStyle Normal -PassThru `
            -RedirectStandardOutput (Join-Path $projectRoot 'logs\visible_emulator.log') `
            -RedirectStandardError (Join-Path $projectRoot 'logs\visible_emulator_error.log')
        Set-Content -LiteralPath $pidFile -Value $game.Id -Encoding ascii
        for ($attempt = 0; $attempt -lt 40; $attempt++) {
            $game.Refresh()
            if ($game.HasExited) { throw 'Emulator exited; inspect logs/visible_emulator_error.log.' }
            if ($game.MainWindowHandle -ne [IntPtr]::Zero) { break }
            Start-Sleep -Milliseconds 100
        }
    } finally { Pop-Location }
}
$windowInfo = & (Join-Path $projectRoot 'tools\window_diag.ps1') -GamePid $game.Id -Show | ConvertFrom-Json
$windowInfo | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $projectRoot 'logs\visible_window_verified.json') -Encoding utf8
Write-Host ('Emulator PID: ' + $game.Id + '; desktop: ' + $windowInfo.Desktop)
Write-Host 'Control: python tools/native_attack.py POSITION 0 18 29'
Write-Host '         python tools/native_attack.py ATTACK 0 0'
