<#
Data module for YouCLI.
This file is dot-sourced by the main script.
#>

<#
.SYNOPSIS
Initializes YouCLI data directories and persisted state files.

.DESCRIPTION
Ensures required folders and JSON files exist, then loads settings, bookmarks,
and queue data into script-level variables. It validates user-configurable
values such as max search results and safely falls back to defaults if any file
is missing or malformed.
#>
function Initialize-YouCliData {
    if (-not (Test-Path $script:AppDataDir)) {
        New-Item -ItemType Directory -Path $script:AppDataDir -Force | Out-Null
    }

    if (-not (Test-Path $script:LogsDir)) {
        New-Item -ItemType Directory -Path $script:LogsDir -Force | Out-Null
    }

    if (-not (Test-Path $script:SettingsPath)) {
        $script:Settings | ConvertTo-Json | Set-Content -Path $script:SettingsPath -Encoding UTF8
    }

    if (-not (Test-Path $script:BookmarksPath)) {
        @() | ConvertTo-Json | Set-Content -Path $script:BookmarksPath -Encoding UTF8
    }

    if (-not (Test-Path $script:QueuePath)) {
        @() | ConvertTo-Json | Set-Content -Path $script:QueuePath -Encoding UTF8
    }

    try {
        $loadedSettings = Get-Content -Path $script:SettingsPath -Raw | ConvertFrom-Json
        if ($loadedSettings) {
            if ($loadedSettings.PSObject.Properties.Name -contains "SearchSource") {
                $script:Settings.SearchSource = $loadedSettings.SearchSource
            }
            if ($loadedSettings.PSObject.Properties.Name -contains "MaxResults") {
                $max = [int]$loadedSettings.MaxResults
                $script:Settings.MaxResults = [Math]::Min([Math]::Max($max, 1), 25)
            }
        }
    } catch {
        $script:Settings = [ordered]@{
            SearchSource = "ytsearch"
            MaxResults = 5
        }
        $script:Settings | ConvertTo-Json | Set-Content -Path $script:SettingsPath -Encoding UTF8
    }

    try {
        $loadedBookmarks = Get-Content -Path $script:BookmarksPath -Raw | ConvertFrom-Json
        if ($null -eq $loadedBookmarks) {
            $script:Bookmarks = @()
        } elseif ($loadedBookmarks -is [System.Array]) {
            $script:Bookmarks = @($loadedBookmarks)
        } else {
            $script:Bookmarks = @($loadedBookmarks)
        }
    } catch {
        $script:Bookmarks = @()
        @() | ConvertTo-Json | Set-Content -Path $script:BookmarksPath -Encoding UTF8
    }

    try {
        $loadedQueue = Get-Content -Path $script:QueuePath -Raw | ConvertFrom-Json
        if ($null -eq $loadedQueue) {
            $script:Queue = @()
        } elseif ($loadedQueue -is [System.Array]) {
            $script:Queue = @($loadedQueue)
        } else {
            $script:Queue = @($loadedQueue)
        }
    } catch {
        $script:Queue = @()
        @() | ConvertTo-Json | Set-Content -Path $script:QueuePath -Encoding UTF8
    }
}

<#
.SYNOPSIS
Persists current settings to disk.

.DESCRIPTION
Serializes the in-memory settings object to JSON and writes it to the settings
file path so user preferences survive restarts.
#>
function Save-Settings {
    $script:Settings | ConvertTo-Json | Set-Content -Path $script:SettingsPath -Encoding UTF8
}

<#
.SYNOPSIS
Persists bookmark entries to disk.

.DESCRIPTION
Serializes the bookmark collection with sufficient depth for object fields and
saves it to the bookmarks JSON file.
#>
function Save-Bookmarks {
    $script:Bookmarks | ConvertTo-Json -Depth 5 | Set-Content -Path $script:BookmarksPath -Encoding UTF8
}

<#
.SYNOPSIS
Persists queue entries to disk.

.DESCRIPTION
Serializes the queue collection to JSON and writes it to the queue file so the
watch queue remains available between sessions.
#>
function Save-Queue {
    $script:Queue | ConvertTo-Json -Depth 5 | Set-Content -Path $script:QueuePath -Encoding UTF8
}
