<#
Core module for YouCLI.
This file is dot-sourced by the main script.
#>

<#
.SYNOPSIS
Prints the YouCLI startup banner and logo text.

.DESCRIPTION
Renders the decorative ASCII art and title block used to brand the interface.
This function is called whenever the main menu refreshes so users always have
clear visual context that they are in the YouCLI home screen.
#>
function Show-YouCliBanner {
    Write-Host @"
⠀⠀⠀⠀⢠⣾⣿⣶⣤⣀⡀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠘⣿⣿⣿⣿⣿⣿⣷⣦⣄⣀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣶⣤⣄⣀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⢻⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣷⣦⣤⣀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⢸⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⠆⠀⠀⠀⠀
⠀⠀⠀⠀⠀⣼⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⡿⠟⠛⠉⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⠿⠛⠋⠉⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⢠⣿⣿⣿⣿⣿⣿⡿⠟⠋⠉⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠘⢿⣿⠿⠛⠉⠁⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
"@

    Write-Host @"
 __ __         _____ __    _____ 
|  |  |___ _ _|     |  |  |     |
|_   _| . | | |   --|  |__|-   -|
  |_| |___|___|_____|_____|_____|                      
"@

    Write-Host
}

<#
.SYNOPSIS
Pauses execution until the user presses Enter.

.DESCRIPTION
Provides a safe pause point after errors or exit notices so the console window
does not close immediately and users can read status messages before continuing.
#>
function Wait-ForExit {
    try {
        Read-Host "Press Enter to continue..." | Out-Null
    } catch {
    }
}

<#
.SYNOPSIS
Finds the yt-dlp executable path used by YouCLI.

.DESCRIPTION
Attempts to resolve yt-dlp from PATH first, then falls back to a standard
Chocolatey install location. Returns the executable path when found, otherwise
returns null so the caller can display install guidance.

.OUTPUTS
System.String or null.
#>
function Resolve-YtDlp {
    $ytDlpCommand = Get-Command yt-dlp -ErrorAction SilentlyContinue
    if ($ytDlpCommand) {
        return $ytDlpCommand.Source
    }

    $chocoYtDlpPath = "C:\ProgramData\chocolatey\bin\yt-dlp.exe"
    if (Test-Path $chocoYtDlpPath) {
        return $chocoYtDlpPath
    }

    return $null
}

<#
.SYNOPSIS
Validates VLC and yt-dlp availability before launching the app workflow.

.DESCRIPTION
Detects VLC installation in common 64-bit and 32-bit paths, then resolves
yt-dlp, initializes application data, and starts the main menu. If required
dependencies are missing, it displays actionable install instructions and
pauses before returning.
#>
function Check-VLC {
    $vlcPath = "C:\Program Files\VideoLAN\VLC\vlc.exe"
    $vlcPath32 = "C:\Program Files (x86)\VideoLAN\VLC\vlc.exe"
    if ((Test-Path $vlcPath) -or (Test-Path $vlcPath32)) {
        if (Test-Path $vlcPath) {
            $script:VlcCommand = $vlcPath
        } else {
            $script:VlcCommand = $vlcPath32
        }

        $script:YtDlpCommand = Resolve-YtDlp
        if (-not $script:YtDlpCommand) {
            Write-Host "⚠️ yt-dlp is not installed or not in PATH." -ForegroundColor Yellow
            Write-Host "Install with: winget install yt-dlp.yt-dlp" -ForegroundColor Cyan
            Write-Host "Or via pip: python -m pip install -U yt-dlp" -ForegroundColor Cyan
            Write-Host "Exiting YouCLI..." -ForegroundColor Red
            Write-Host
            Wait-ForExit
            return
        }
        Initialize-YouCliData
        Start-MainMenu
    } else {
        Write-Host "⚠️ VLC player is not installed. Please install VLC to use this feature." -ForegroundColor Yellow
        Write-Host "You can download VLC from: https://www.videolan.org/" -ForegroundColor Cyan
        Write-Host "Exiting YouCLI..." -ForegroundColor Red
        Write-Host
        Wait-ForExit
    }
}
