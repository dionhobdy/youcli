<# 
YouCLI - A PowerShell CLI YouTube Client 
Author: Dion Hobdy
GitHub: https://github.com/dionhobdy/YouCLI
License: MIT License
Description: A command-line interface for interacting with YouTube, allowing users to search for videos, select a video and watch it on VLC player when the video is selected.
#>

$script:YtDlpCommand = $null
$script:VlcCommand = $null
$script:AppDataDir = Join-Path $PSScriptRoot "src\data"
$script:LogsDir = Join-Path $script:AppDataDir "logs"
$script:SettingsPath = Join-Path $script:AppDataDir "settings.json"
$script:BookmarksPath = Join-Path $script:AppDataDir "bookmarks.json"
$script:QueuePath = Join-Path $script:AppDataDir "queue.json"
$script:YtDlpDebugLogPath = Join-Path $script:LogsDir "yt-dlp-debug.log"
$script:Settings = [ordered]@{
    SearchSource = "ytsearch"
    MaxResults = 5
}
$script:Bookmarks = @()
$script:Queue = @()
$script:RecentPlayedVideos = @()

$script:ModuleScripts = @(
    "core.ps1",
    "data.ps1",
    "playback.ps1",
    "search.ps1",
    "settings.ps1",
    "bookmarks.ps1",
    "queue.ps1"
)

foreach ($moduleScript in $script:ModuleScripts) {
    $modulePath = Join-Path $PSScriptRoot ("src\{0}" -f $moduleScript)
    if (Test-Path $modulePath) {
        . $modulePath
    }
}

<#
.SYNOPSIS
Displays a numbered list of videos or items in the console.

.DESCRIPTION
Renders a heading and each item title in a consistent CLI format so users can
select results by index. If an item contains an `IsLive` property with a true
value, the function appends a visual LIVE marker in red. When the list is empty,
it prints an informative message and returns immediately.

.PARAMETER VideoList
The array of video/item objects to render. Expected to include at least a Title
property, and optionally IsLive and ChannelName properties.

.PARAMETER Heading
Optional label shown above the list to identify the current context.
#>
function Show-VideoList {
    param(
        [Parameter(Mandatory = $true)]
        [array]$VideoList,

        [string]$Heading = "Items"
    )

    Write-Host ("📋 {0}:" -f $Heading) -ForegroundColor Green
    if (-not $VideoList -or $VideoList.Count -eq 0) {
        Write-Host "No items found." -ForegroundColor Yellow
        Write-Host
        return
    }

    for ($index = 0; $index -lt $VideoList.Count; $index++) {
        $video = $VideoList[$index]

        if ($Heading -eq "Search Results") {
            $channelName = "Unknown Channel"
            if ($video.PSObject.Properties.Name -contains "ChannelName" -and -not [string]::IsNullOrWhiteSpace($video.ChannelName)) {
                $channelName = $video.ChannelName
            }

            Write-Host ("[{0}] {1} [{2}]" -f ($index + 1), $video.Title, $channelName)
            continue
        }

        if ($video.PSObject.Properties.Name -contains "IsLive" -and $video.IsLive) {
            Write-Host ("[{0}] {1} " -f ($index + 1), $video.Title) -NoNewline
            Write-Host "LIVE" -ForegroundColor Red
        } else {
            Write-Host ("[{0}] {1}" -f ($index + 1), $video.Title)
        }
    }
    Write-Host
}

<#
.SYNOPSIS
Runs the main interactive menu loop for YouCLI.

.DESCRIPTION
Continuously displays the app banner and top-level menu options, then routes
user input to the corresponding feature module (search, settings, bookmarks,
or queue). The loop only exits when the user selects the explicit exit option.
#>
function Start-MainMenu {
    while ($true) {
        Clear-Host
        Show-YouCliBanner
        Write-Host "[1] Search"
        Write-Host "[2] Settings"
        Write-Host "[3] Bookmarks"
        Write-Host "[4] Queue"
        Write-Host "[5] Exit"
        Write-Host

        $choice = Read-Host "Choose an option"
        Write-Host

        switch ($choice.Trim()) {
            "1" {
                Clear-Host
                Show-YouCliBanner
                Search-YouTube
            }
            "2" {
                Clear-Host
                Show-YouCliBanner
                Start-SettingsMenu
            }
            "3" {
                Clear-Host
                Show-YouCliBanner
                Start-BookmarksMenu
            }
            "4" {
                Clear-Host
                Show-YouCliBanner
                Start-QueueMenu
            }
            "5" {
                Write-Host "Exiting YouCLI..." -ForegroundColor Cyan
                return
            }
            default {
                Write-Host "Invalid option." -ForegroundColor Yellow
                Write-Host
            }
        }
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