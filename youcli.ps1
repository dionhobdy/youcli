<# 
YouCLI - A PowerShell CLI YouTube Client 
Author: Dion Hobdy
GitHub: https://github.com/dionhobdy/YouCLI
License: MIT License
Description: A command-line interface for interacting with YouTube, allowing users to search for videos, select a video and watch it on VLC player when the video is selected.
#>

# Output a multiline intro message displaying the title and ascii art
Write-Host @"
⠀⠀⢀⣀⣠⣤⣤⣤⣤⣤⣤⣤⣤⣤⣤⣤⣤⣤⣤⣤⣤⣄⣀⡀⠀⠀
⠀⣴⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣦⠀
⠀⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⠀
⢰⣿⣿⣿⣿⣿⣿⣿⣿⣿⡟⠻⢿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⡆
⢸⣿⣿⣿⣿⣿⣿⣿⣿⣿⡇⠀⠀⠈⠛⠿⣿⣿⣿⣿⣿⣿⣿⣿⣿⡇
⢸⣿⣿⣿⣿⣿⣿⣿⣿⣿⡇⠀⠀⠀⠀⠀⢈⣹⣿⣿⣿⣿⣿⣿⣿⡇
⢸⣿⣿⣿⣿⣿⣿⣿⣿⣿⡇⠀⠀⢀⣤⣶⣿⣿⣿⣿⣿⣿⣿⣿⣿⡇
⠸⣿⣿⣿⣿⣿⣿⣿⣿⣿⣧⣴⣾⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⠇
⠀⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⠀
⠀⠻⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⠟⠀
⠀⠀⠈⠉⠙⠛⠛⠛⠛⠛⠛⠛⠛⠛⠛⠛⠛⠛⠛⠛⠛⠋⠉⠁
"@ -ForegroundColor Red

Write-Host @"
 __ __         _____ __    _____ 
|  |  |___ _ _|     |  |  |     |
|_   _| . | | |   --|  |__|-   -|
  |_| |___|___|_____|_____|_____|                      
"@

Write-Host

$script:YtDlpCommand = $null
$script:VlcCommand = $null

function Wait-ForExit {
    try {
        Read-Host "Press Enter to continue..." | Out-Null
    } catch {
    }
}

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

function Resolve-StreamUrl {
    param(
        [Parameter(Mandatory = $true)]
        [string]$VideoUrl
    )

    $streamOutput = & $script:YtDlpCommand $VideoUrl "-f" "best[acodec!=none][vcodec!=none]/best" "-g" "--no-playlist" "--socket-timeout" "15" 2>&1
    if ($LASTEXITCODE -ne 0) {
        return $null
    }

    $streamUrl = $streamOutput | Where-Object {
        ($_ -is [string]) -and ($_ -match "^https?://")
    } | Select-Object -First 1

    return $streamUrl
}

function Start-VlcPlayback {
    param(
        [Parameter(Mandatory = $true)]
        [string]$PlaybackUrl,

        [Parameter(Mandatory = $true)]
        [string]$FallbackUrl
    )

    $vlcArgs = @("--width=800", "--height=450", "--network-caching=1500", $PlaybackUrl)
    $vlcProcess = Start-Process -FilePath $script:VlcCommand -ArgumentList $vlcArgs -PassThru

    Start-Sleep -Seconds 2
    if ($vlcProcess.HasExited) {
        Write-Host "VLC closed unexpectedly. Retrying with a simpler launch..." -ForegroundColor Yellow
        Start-Process -FilePath $script:VlcCommand -ArgumentList @("--width=800", "--height=450", $FallbackUrl) | Out-Null
    }
}

#Function to check if ffmpeg is installed
function Check-FFmpeg {
    $ffmpegPath = "C:\ffmpeg\bin\ffmpeg.exe"
    if (Test-Path $ffmpegPath) {
        Write-Host "✅ FFmpeg is installed." -ForegroundColor Green
        Write-Host "Checking for VLC player..." -ForegroundColor Cyan
        # Call Check-VLC function if path is valid
        Check-VLC
    } else {
        Write-Host "⚠️ FFmpeg is not installed. Please install FFmpeg to use this feature." -ForegroundColor Yellow
        Write-Host "You can download FFmpeg from: https://ffmpeg.org/" -ForegroundColor Cyan
        Write-Host "Exiting YouCLI..." -ForegroundColor Red
        Write-Host
        Wait-ForExit
    }
}

# Function to check if VLC is installed
function Check-VLC {
    $vlcPath = "C:\Program Files\VideoLAN\VLC\vlc.exe"
    $vlcPath32 = "C:\Program Files (x86)\VideoLAN\VLC\vlc.exe"
    if ((Test-Path $vlcPath) -or (Test-Path $vlcPath32)) {
        if (Test-Path $vlcPath) {
            $script:VlcCommand = $vlcPath
        } else {
            $script:VlcCommand = $vlcPath32
        }

        Write-Host "✅ VLC player is installed." -ForegroundColor Green
        Write-Host "Welcome to YouCLI" -ForegroundColor Cyan
        Write-Host
        # Ensure yt-dlp is available before searching
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
        # Call Search-Youtube function if paths are valid
        Search-YouTube
    } else {
        Write-Host "⚠️ VLC player is not installed. Please install VLC to use this feature." -ForegroundColor Yellow
        Write-Host "You can download VLC from: https://www.videolan.org/" -ForegroundColor Cyan
        Write-Host "Exiting YouCLI..." -ForegroundColor Red
        Write-Host
        Wait-ForExit
    }
}

# Function to search YouTube and return video results
function Search-YouTube {
    Write-Host "Type 'Exit' to close YouCLI." -ForegroundColor DarkCyan
    Write-Host

    while ($true) {
        $query = Read-Host "🔍 Enter a search query for YouTube"
        if ([string]::IsNullOrWhiteSpace($query)) {
            Write-Host "Search query cannot be empty." -ForegroundColor Yellow
            Write-Host
            continue
        }

        if ($query.Trim().ToLower() -eq "exit") {
            Write-Host "Exiting YouCLI..." -ForegroundColor Cyan
            break
        }

        $modeInput = Read-Host "Search mode: [D]ate or [R]elevance (default: Relevance)"
        $searchSource = "ytsearch"
        if (-not [string]::IsNullOrWhiteSpace($modeInput)) {
            switch ($modeInput.Trim().ToLower()) {
                "d" { $searchSource = "ytsearchdate" }
                "date" { $searchSource = "ytsearchdate" }
                "r" { $searchSource = "ytsearch" }
                "relevance" { $searchSource = "ytsearch" }
                default {
                    Write-Host "Unknown mode. Using Relevance." -ForegroundColor Yellow
                }
            }
        }

        Write-Host "Searching YouTube..." -ForegroundColor Cyan

        $ytDlpArgs = @(
            "${searchSource}5:$query",
            "--print", "%(title)s|%(webpage_url)s",
            "--flat-playlist",
            "--ignore-errors",
            "--no-warnings",
            "--no-playlist",
            "--socket-timeout", "15"
        )
        $output = & $script:YtDlpCommand @ytDlpArgs 2>&1

        if ($LASTEXITCODE -ne 0) {
            Write-Host "Search failed while calling yt-dlp." -ForegroundColor Red
            if ($output) {
                $output | Select-Object -First 3 | ForEach-Object { Write-Host $_ }
            }
            Write-Host
            continue
        }

        $results = $output | Where-Object {
            ($_ -is [string]) -and ($_ -match "\|https?://")
        }

        Write-Host "📋 Search Results:" -ForegroundColor Green
        if (-not $results) {
            Write-Host "No results found." -ForegroundColor Yellow
            if ($output) {
                Write-Host "yt-dlp output:" -ForegroundColor DarkYellow
                $output | Select-Object -First 3 | ForEach-Object { Write-Host $_ }
            }
            Write-Host
            continue
        }

        $videoResults = @()
        foreach ($line in $results) {
            $parts = $line -split "\|", 2
            if ($parts.Count -eq 2) {
                $videoResults += [PSCustomObject]@{
                    Title = $parts[0].Trim()
                    Url = $parts[1].Trim()
                }
            }
        }

        if (-not $videoResults) {
            Write-Host "No playable results found." -ForegroundColor Yellow
            Write-Host
            continue
        }

        for ($index = 0; $index -lt $videoResults.Count; $index++) {
            Write-Host ("[{0}] {1}" -f ($index + 1), $videoResults[$index].Title)
        }

        Write-Host
        $selection = Read-Host "Select a video number to play in VLC (or type 'skip')"
        if ($selection.Trim().ToLower() -eq "skip") {
            Write-Host
            continue
        }

        [int]$selectedIndex = 0
        if (-not [int]::TryParse($selection, [ref]$selectedIndex) -or $selectedIndex -lt 1 -or $selectedIndex -gt $videoResults.Count) {
            Write-Host "Invalid selection." -ForegroundColor Yellow
            Write-Host
            continue
        }

        $selectedVideo = $videoResults[$selectedIndex - 1]
        Write-Host "Opening in VLC: $($selectedVideo.Title)" -ForegroundColor Cyan
        $streamUrl = Resolve-StreamUrl -VideoUrl $selectedVideo.Url
        if (-not $streamUrl) {
            Write-Host "Could not resolve a playable stream URL for this video." -ForegroundColor Yellow
            Write-Host "Try another result or update yt-dlp." -ForegroundColor Yellow
            Write-Host
            continue
        }

        Start-VlcPlayback -PlaybackUrl $streamUrl -FallbackUrl $selectedVideo.Url
        Write-Host
    }
}

try {
    Check-VLC
} catch {
    Write-Host "❌ YouCLI encountered an error:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Yellow
    Wait-ForExit
    exit 1
}