@echo off
setlocal EnableExtensions
 title STARSHIP: ASTEROID RUN - SCROLL WHEEL
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
echo Starting STARSHIP: ASTEROID RUN (SCROLL WHEEL CONTROLS)...
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

# Read native Windows console input so mouse-wheel events can control the ship.
Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.InteropServices;

public static class StarshipConsoleInput
{
    private const int STD_INPUT_HANDLE = -10;
    private const uint ENABLE_MOUSE_INPUT = 0x0010;
    private const uint ENABLE_QUICK_EDIT_MODE = 0x0040;
    private const uint ENABLE_EXTENDED_FLAGS = 0x0080;
    private const ushort KEY_EVENT = 0x0001;
    private const ushort MOUSE_EVENT = 0x0002;
    private const uint MOUSE_WHEELED = 0x0004;

    [StructLayout(LayoutKind.Sequential)]
    public struct COORD { public short X; public short Y; }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct KEY_EVENT_RECORD
    {
        [MarshalAs(UnmanagedType.Bool)] public bool KeyDown;
        public ushort RepeatCount;
        public ushort VirtualKeyCode;
        public ushort VirtualScanCode;
        public char UnicodeChar;
        public uint ControlKeyState;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct MOUSE_EVENT_RECORD
    {
        public COORD MousePosition;
        public uint ButtonState;
        public uint ControlKeyState;
        public uint EventFlags;
    }

    [StructLayout(LayoutKind.Explicit)]
    public struct EVENT_UNION
    {
        [FieldOffset(0)] public KEY_EVENT_RECORD KeyEvent;
        [FieldOffset(0)] public MOUSE_EVENT_RECORD MouseEvent;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct INPUT_RECORD
    {
        public ushort EventType;
        public EVENT_UNION Event;
    }

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr GetStdHandle(int nStdHandle);
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool GetConsoleMode(IntPtr hConsoleHandle, out uint lpMode);
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool SetConsoleMode(IntPtr hConsoleHandle, uint dwMode);
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool GetNumberOfConsoleInputEvents(IntPtr hConsoleInput, out uint lpcNumberOfEvents);
    [DllImport("kernel32.dll", SetLastError = true, EntryPoint = "ReadConsoleInputW", CharSet = CharSet.Unicode)]
    private static extern bool ReadConsoleInput(IntPtr hConsoleInput, [Out] INPUT_RECORD[] lpBuffer, uint nLength, out uint lpNumberOfEventsRead);

    private static IntPtr inputHandle = IntPtr.Zero;
    private static uint oldMode;
    private static bool modeSaved = false;
    private static readonly Queue<ushort> keys = new Queue<ushort>();
    private static int wheelDelta = 0;

    public static void Initialize()
    {
        inputHandle = GetStdHandle(STD_INPUT_HANDLE);
        if (inputHandle == IntPtr.Zero || inputHandle == new IntPtr(-1))
            throw new InvalidOperationException("Could not access the Windows console input handle.");
        uint mode;
        if (!GetConsoleMode(inputHandle, out mode))
            throw new Win32Exception(Marshal.GetLastWin32Error(), "Could not read console input mode.");
        oldMode = mode;
        modeSaved = true;
        uint newMode = (mode | ENABLE_MOUSE_INPUT | ENABLE_EXTENDED_FLAGS) & ~ENABLE_QUICK_EDIT_MODE;
        if (!SetConsoleMode(inputHandle, newMode))
            throw new Win32Exception(Marshal.GetLastWin32Error(), "Could not enable mouse-wheel input.");
    }

    public static void Restore()
    {
        if (modeSaved && inputHandle != IntPtr.Zero)
        {
            SetConsoleMode(inputHandle, oldMode);
            modeSaved = false;
        }
    }

    public static void Poll()
    {
        if (inputHandle == IntPtr.Zero) return;
        uint available;
        while (GetNumberOfConsoleInputEvents(inputHandle, out available) && available > 0)
        {
            uint n = Math.Min(available, 128U);
            INPUT_RECORD[] records = new INPUT_RECORD[n];
            uint read;
            if (!ReadConsoleInput(inputHandle, records, n, out read) || read == 0) return;
            for (int i = 0; i < read; i++)
            {
                INPUT_RECORD record = records[i];
                if (record.EventType == KEY_EVENT && record.Event.KeyEvent.KeyDown)
                {
                    if (keys.Count < 128) keys.Enqueue(record.Event.KeyEvent.VirtualKeyCode);
                }
                else if (record.EventType == MOUSE_EVENT && record.Event.MouseEvent.EventFlags == MOUSE_WHEELED)
                {
                    int delta = unchecked((short)((record.Event.MouseEvent.ButtonState >> 16) & 0xFFFF));
                    wheelDelta += delta;
                }
            }
        }
    }

    public static int NextKey()
    {
        return keys.Count > 0 ? keys.Dequeue() : 0;
    }

    public static int TakeWheelDelta()
    {
        int result = wheelDelta;
        wheelDelta = 0;
        return result;
    }
}
'@
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
    [void]$sb.AppendLine(' STARSHIP: ASTEROID RUN   SCROLL WHEEL = MOVE   Q = QUIT')
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
    $script:wheelRemainder = 0
    $shipY = [int]($script:H / 2)
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
        [StarshipConsoleInput]::Poll()
        $script:wheelRemainder += [StarshipConsoleInput]::TakeWheelDelta()
        # A standard wheel notch is 120 units. Wheel up moves the ship up;
        # wheel down moves it down. Keep partial deltas until a full notch arrives.
        while ($script:wheelRemainder -ge 120) {
            if ($shipY -gt 1) { $shipY-- }
            $script:wheelRemainder -= 120
        }
        while ($script:wheelRemainder -le -120) {
            if ($shipY -lt ($script:H - 2)) { $shipY++ }
            $script:wheelRemainder += 120
        }
        $keyCode = [StarshipConsoleInput]::NextKey()
        while ($keyCode -ne 0) {
            if ($keyCode -eq 81 -or $keyCode -eq 27) { return 'quit' }
            $keyCode = [StarshipConsoleInput]::NextKey()
        }
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
        [StarshipConsoleInput]::Poll()
        $keyCode = [StarshipConsoleInput]::NextKey()
        while ($keyCode -ne 0) {
            if ($keyCode -eq 82) { return 'retry' }
            if ($keyCode -eq 81 -or $keyCode -eq 27) { return 'quit' }
            $keyCode = [StarshipConsoleInput]::NextKey()
        }
        Start-Sleep -Milliseconds 50
    }
}

try {
    $host.UI.RawUI.WindowTitle = 'STARSHIP: ASTEROID RUN'
    try { [Console]::CursorVisible = $false } catch {}
    Clear-Host
    Write-Host 'STARSHIP: ASTEROID RUN' -ForegroundColor white
    Write-Host ''
    Write-Host 'Pilot your ship through a field of asteroids.'
    Write-Host 'Scroll the mouse wheel UP or DOWN to move your ship.'
    Write-Host 'Avoid @ asteroids. Press Q any time to quit.'
    Write-Host ''
    Write-Host 'Press any key to launch...'
    [void][Console]::ReadKey($true)
    [StarshipConsoleInput]::Initialize()
    Write-Host 'Keep the mouse pointer over this window while scrolling.'
    Start-Sleep -Milliseconds 700
    while ($true) {
        Clear-Host
        $result = Start-Run
        if ($result -eq 'quit') { break }
    }
    try { [StarshipConsoleInput]::Restore() } catch {}
    try { [Console]::CursorVisible = $true } catch {}
    Clear-Host
    Write-Host 'Flight ended. Thanks for playing!' -ForegroundColor Cyan
}
catch {
    try { [StarshipConsoleInput]::Restore() } catch {}
    try { [Console]::CursorVisible = $true; Clear-Host } catch {}
    Write-Host 'The game hit an error:' -ForegroundColor Red
    Write-Host ($_ | Out-String) -ForegroundColor Yellow
    Write-Host ''
    Write-Host 'Please take a screenshot of this message.'
    try { [void][Console]::ReadKey($true) } catch { Read-Host 'Press Enter to close' }
    exit 1
}
