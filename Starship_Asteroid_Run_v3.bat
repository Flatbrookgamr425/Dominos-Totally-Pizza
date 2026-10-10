@echo off
setlocal EnableExtensions
 title STARSHIP: ASTEROID RUN
color 0B
set "PSFILE=%TEMP%\Starship_Asteroid_Run_%RANDOM%_%RANDOM%.ps1"
set "MARKERLINE="
for /f "tokens=1 delims=:" %%A in ('findstr /n /x /c:"::PS_SCRIPT_START::" "%~f0"') do set "MARKERLINE=%%A"
if not defined MARKERLINE (
    echo ERROR: Could not locate the embedded game code.
    echo The download may be incomplete.
    echo.
    pause
    exit /b 1
)
more +%MARKERLINE% "%~f0" > "%PSFILE%"
if not exist "%PSFILE%" (
    echo ERROR: Could not extract the game script.
    echo.
    pause
    exit /b 1
)
where powershell.exe >nul 2>&1
if errorlevel 1 (
    echo ERROR: Windows PowerShell was not found.
    echo.
    pause
    del "%PSFILE%" >nul 2>&1
    exit /b 1
)
echo Starting STARSHIP: ASTEROID RUN...
echo If something fails, this window will stay open.
echo.
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%PSFILE%"
set "GAME_EXIT=%ERRORLEVEL%"
del "%PSFILE%" >nul 2>&1
echo.
if not "%GAME_EXIT%"=="0" echo PowerShell exited with code %GAME_EXIT%.
echo Press any key to close this window.
pause >nul
exit /b %GAME_EXIT%
::PS_SCRIPT_START::
$ErrorActionPreference = 'Stop'
$W = 54
$H = 18
$shipX = 8
$rand = New-Object System.Random
$best = 0

function Draw-Scene {
    param([int]$ShipY, [array]$Rocks, [array]$Stars, [int]$Score, [string]$Message)
    # Use a one-dimensional character list so this works in Windows PowerShell 5.1.
    # Multi-dimensional indexing such as $grid[$row, $column] caused the parser error.
    $grid = [System.Collections.Generic.List[char]]::new()
    for ($i = 0; $i -lt ($script:H * $script:W); $i++) {
        $grid.Add([char]' ')
    }
    foreach ($s in $Stars) {
        if ($s.X -ge 0 -and $s.X -lt $script:W -and $s.Y -ge 0 -and $s.Y -lt $script:H) {
            $grid[($s.Y * $script:W + $s.X)] = [char]$s.C
        }
    }
    foreach ($r in $Rocks) {
        if ($r.X -ge 0 -and $r.X -lt $script:W -and $r.Y -ge 0 -and $r.Y -lt $script:H) {
            $grid[($r.Y * $script:W + $r.X)] = [char]'@'
        }
        if ($r.Big -and $r.Y -ge 0 -and $r.Y -lt $script:H) {
            if ($r.X -gt 0 -and $r.X -lt $script:W) {
                $grid[($r.Y * $script:W + ($r.X - 1))] = [char]'('
            }
            if ($r.X -ge 0 -and $r.X -lt ($script:W - 1)) {
                $grid[($r.Y * $script:W + ($r.X + 1))] = [char]')'
            }
        }
    }
    if ($ShipY -ge 1 -and $ShipY -lt ($script:H - 1)) {
        $grid[($ShipY * $script:W + $script:shipX)] = [char]'>'
        $grid[($ShipY * $script:W + ($script:shipX - 1))] = [char]'='
        $grid[(($ShipY - 1) * $script:W + ($script:shipX - 1))] = [char]'/'
        $grid[(($ShipY + 1) * $script:W + ($script:shipX - 1))] = [char]'\'
    }
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine(' STARSHIP: ASTEROID RUN      SPACE = THRUST UP      Q = QUIT')
    [void]$sb.AppendLine((' SCORE: {0,-6} BEST: {1,-6} Avoid the @ asteroids!' -f $Score, $script:best))
    [void]$sb.AppendLine('+' + ('-' * $script:W) + '+')
    for ($yy = 0; $yy -lt $script:H; $yy++) {
        [void]$sb.Append('|')
        for ($xx = 0; $xx -lt $script:W; $xx++) {
            [void]$sb.Append($grid[($yy * $script:W + $xx)])
        }
        [void]$sb.AppendLine('|')
    }
    [void]$sb.AppendLine('+' + ('-' * $script:W) + '+')
    if ($Message) { [void]$sb.AppendLine($Message) }
    [Console]::SetCursorPosition(0, 0)
    [Console]::Write($sb.ToString())
}

function Start-Run {
    $shipY = [int]($script:H / 2)
    $velocity = 0.0
    $rocks = New-Object System.Collections.ArrayList
    $stars = New-Object System.Collections.ArrayList
    for ($i = 0; $i -lt 48; $i++) {
        $c = '.'
        if ($script:rand.Next(0, 5) -eq 0) { $c = '+' }
        [void]$stars.Add([pscustomobject]@{ X = $script:rand.Next(0, $script:W); Y = $script:rand.Next(0, $script:H); C = $c })
    }
    $score = 0
    $ticks = 0
    $dead = $false
    while (-not $dead) {
        $ticks++
        while ([Console]::KeyAvailable) {
            $key = [Console]::ReadKey($true)
            if ($key.Key -eq [ConsoleKey]::Spacebar) { $velocity = -1.8 }
            if ($key.Key -eq [ConsoleKey]::Q -or $key.Key -eq [ConsoleKey]::Escape) { return 'quit' }
        }
        $velocity += 0.16
        if ($velocity -gt 1.2) { $velocity = 1.2 }
        $shipY += [int][Math]::Round($velocity, [MidpointRounding]::AwayFromZero)
        if ($shipY -lt 1 -or $shipY -gt ($script:H - 2)) { $dead = $true; break }
        foreach ($s in $stars) {
            $s.X--
            if ($s.X -lt 0) { $s.X = $script:W - 1; $s.Y = $script:rand.Next(0, $script:H) }
        }
        if (($ticks % 9) -eq 0) {
            [void]$rocks.Add([pscustomobject]@{ X = $script:W - 2; Y = $script:rand.Next(1, $script:H - 1); Big = ($script:rand.Next(0, 4) -eq 0); Counted = $false })
        }
        for ($i = $rocks.Count - 1; $i -ge 0; $i--) {
            $r = $rocks[$i]
            $r.X--
            if (-not $r.Counted -and $r.X -lt $script:shipX) { $score++; $r.Counted = $true }
            if ($r.X -lt 0) { $rocks.RemoveAt($i); continue }
            if ([Math]::Abs($r.X - $script:shipX) -le 1 -and [Math]::Abs($r.Y - $shipY) -le 1) { $dead = $true; break }
        }
        Draw-Scene -ShipY $shipY -Rocks @($rocks) -Stars @($stars) -Score $score -Message ''
        Start-Sleep -Milliseconds 85
    }
    if ($score -gt $script:best) { $script:best = $score }
    Draw-Scene -ShipY $shipY -Rocks @($rocks) -Stars @($stars) -Score $score -Message (" CRASH! Final score: $score   Best: $script:best   Press R to retry or Q to quit.")
    while ($true) {
        $k = [Console]::ReadKey($true)
        if ($k.Key -eq [ConsoleKey]::R) { return 'retry' }
        if ($k.Key -eq [ConsoleKey]::Q -or $k.Key -eq [ConsoleKey]::Escape) { return 'quit' }
    }
}

try {
    $host.UI.RawUI.WindowTitle = 'STARSHIP: ASTEROID RUN'
    try { [Console]::CursorVisible = $false } catch {}
    Clear-Host
    Write-Host 'STARSHIP: ASTEROID RUN' -ForegroundColor Cyan
    Write-Host ''
    Write-Host 'Pilot your ship through a field of asteroids.'
    Write-Host 'Press SPACE to thrust upward. Release to drift down.'
    Write-Host 'Avoid @ asteroids. Press Q any time to quit.'
    Write-Host ''
    Write-Host 'Press any key to launch...'
    [void][Console]::ReadKey($true)
    while ($true) {
        Clear-Host
        $result = Start-Run
        if ($result -eq 'quit') { break }
    }
    try { [Console]::CursorVisible = $true } catch {}
    Clear-Host
    Write-Host 'Flight ended. Thanks for playing!' -ForegroundColor Cyan
}
catch {
    try { [Console]::CursorVisible = $true; Clear-Host } catch {}
    Write-Host 'The game hit an error:' -ForegroundColor Red
    Write-Host ($_ | Out-String) -ForegroundColor Yellow
    Write-Host ''
    Write-Host 'Please take a screenshot of this message.'
    try { [void][Console]::ReadKey($true) } catch { Read-Host 'Press Enter to close' }
    exit 1
}
