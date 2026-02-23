<#
Search module for YouCLI.
This file is dot-sourced by the main script.
#>

<#
.SYNOPSIS
Reads search input with optional previous-query recall.

.DESCRIPTION
Captures user keystrokes directly from the console so the search prompt supports
basic line editing and UpArrow recall of the last query. Falls back to Read-Host
when input/output is redirected and raw key handling is not available.

.PARAMETER Prompt
Prompt text shown to the user before input is captured.

.PARAMETER PreviousQuery
Optional previous search text inserted when the user presses UpArrow.

.OUTPUTS
System.String
#>
function Read-SearchQueryWithHistory {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Prompt,

        [string]$PreviousQuery
    )

    if ([Console]::IsInputRedirected -or [Console]::IsOutputRedirected) {
        return Read-Host $Prompt
    }

    Write-Host $Prompt -NoNewline
    Write-Host ": " -NoNewline
    $buffer = ""

    while ($true) {
        $keyInfo = [Console]::ReadKey($true)

        switch ($keyInfo.Key) {
            "Enter" {
                Write-Host
                return $buffer
            }
            "Backspace" {
                if ($buffer.Length -gt 0) {
                    $buffer = $buffer.Substring(0, $buffer.Length - 1)
                    Write-Host "`b `b" -NoNewline
                }
            }
            "UpArrow" {
                if (-not [string]::IsNullOrWhiteSpace($PreviousQuery)) {
                    while ($buffer.Length -gt 0) {
                        $buffer = $buffer.Substring(0, $buffer.Length - 1)
                        Write-Host "`b `b" -NoNewline
                    }

                    $buffer = $PreviousQuery
                    Write-Host $buffer -NoNewline
                }
            }
            default {
                $typedChar = $keyInfo.KeyChar
                if (-not [char]::IsControl($typedChar)) {
                    $buffer += $typedChar
                    Write-Host $typedChar -NoNewline
                }
            }
        }
    }
}

<#
.SYNOPSIS
Determines whether a result should be treated as a live stream.

.DESCRIPTION
Evaluates multiple metadata fields returned by yt-dlp (`live_status`, `is_live`,
and `duration_string`) so live streams can be clearly marked in result lists.

.PARAMETER LiveStatus
The raw live status field from yt-dlp output.

.PARAMETER IsLive
Boolean-like live flag returned by yt-dlp.

.PARAMETER DurationString
Duration label that may contain the value "live".

.OUTPUTS
System.Boolean
#>
function Test-IsLiveVideo {
    param(
        [string]$LiveStatus,
        [string]$IsLive,
        [string]$DurationString
    )

    if ($IsLive -match '^(?i:true|1)$') {
        return $true
    }

    if ($LiveStatus -match '^(?i:is_live|live)$') {
        return $true
    }

    if ($DurationString -match '^(?i:live)$') {
        return $true
    }

    return $false
}

<#
.SYNOPSIS
Runs the interactive YouTube search workflow.

.DESCRIPTION
Prompts for a search query, calls yt-dlp to fetch result metadata, transforms
output into structured video objects, displays results, and routes user choices
to playback. The results view remains active after playback so users can choose
multiple items, and supports prefixed result commands such as `-play 3`.
#>
function Search-YouTube {
    Write-Host "Type 'Back' to reload search." -ForegroundColor DarkCyan
    Write-Host "Type 'Menu' to return to Main Menu." -ForegroundColor DarkCyan
    Write-Host "Type 'Exit' to close YouCLI." -ForegroundColor DarkCyan
    Write-Host

    $previousSearchQuery = $null
    $clearBeforePrompt = $false

    while ($true) {
        if ($clearBeforePrompt) {
            Clear-Host
            Show-YouCliBanner
            Write-Host "Type 'Back' to reload search." -ForegroundColor DarkCyan
            Write-Host "Type 'Menu' to return to Main Menu." -ForegroundColor DarkCyan
            Write-Host "Type 'Exit' to close YouCLI." -ForegroundColor DarkCyan
            Write-Host
            $clearBeforePrompt = $false
        }

        $query = Read-SearchQueryWithHistory -Prompt "Enter a search query for YouTube" -PreviousQuery $previousSearchQuery
        if ([string]::IsNullOrWhiteSpace($query)) {
            Write-Host "Search query cannot be empty." -ForegroundColor Yellow
            Write-Host
            continue
        }

        $normalized = $query.Trim().ToLower()
        if ($normalized -eq "back") {
            Write-Host
            continue
        }

        if ($normalized -eq "menu") {
            return
        }

        if ($normalized -eq "exit") {
            Write-Host "Exiting YouCLI..." -ForegroundColor Cyan
            exit 0
        }

        $previousSearchQuery = $query

        $searchSource = $script:Settings.SearchSource
        if ([string]::IsNullOrWhiteSpace($searchSource)) {
            $searchSource = "ytsearch"
        }

        $maxResults = [int]$script:Settings.MaxResults
        if ($maxResults -lt 1) {
            $maxResults = 5
        }

        $ytDlpArgs = @(
            "${searchSource}${maxResults}:$query",
            "--print", "%(title)s|%(webpage_url)s|%(live_status)s|%(is_live)s|%(duration_string)s|%(uploader)s",
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
            ($_ -is [string]) -and ($_ -match '\|https?://')
        }

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
            $parts = $line -split '\|', 6
            if ($parts.Count -ge 2) {
                $liveStatus = ""
                $isLive = ""
                $durationString = ""
                $channelName = ""

                if ($parts.Count -ge 3) { $liveStatus = $parts[2].Trim() }
                if ($parts.Count -ge 4) { $isLive = $parts[3].Trim() }
                if ($parts.Count -ge 5) { $durationString = $parts[4].Trim() }
                if ($parts.Count -ge 6) { $channelName = $parts[5].Trim() }

                $videoResults += [PSCustomObject]@{
                    Title = $parts[0].Trim()
                    Url = $parts[1].Trim()
                    ChannelName = $channelName
                    IsLive = (Test-IsLiveVideo -LiveStatus $liveStatus -IsLive $isLive -DurationString $durationString)
                }
            }
        }

        if (-not $videoResults) {
            Write-Host "No playable results found." -ForegroundColor Yellow
            Write-Host
            continue
        }

        :selectionLoop while ($true) {
            Clear-Host
            Show-YouCliBanner
            Show-VideoList -VideoList $videoResults -Heading "Search Results"

            Write-Host "prefix: -" -ForegroundColor DarkGray
            Write-Host "back bookmark copyurl display menu play queue" -ForegroundColor DarkGray
            Write-Host "i.e. [prefix]queue [number]" -ForegroundColor DarkGray
            if ($script:RecentPlayedVideos -and $script:RecentPlayedVideos.Count -gt 0) {
                $recentPreview = $script:RecentPlayedVideos | Select-Object -First 5
                Write-Host "Recent:" -ForegroundColor DarkGray
                foreach ($recentItem in $recentPreview) {
                    Write-Host ("- {0}" -f $recentItem) -ForegroundColor DarkGray
                }
            }

            $selection = Read-Host "Input Request"
            if ([string]::IsNullOrWhiteSpace($selection)) {
                Write-Host "Please enter a value." -ForegroundColor Yellow
                continue
            }

            $requestText = $selection.Trim()
            $requestParts = $requestText -split '\s+', 2
            $requestCommand = $requestParts[0].ToLower()
            $requestArg = ""
            if ($requestParts.Count -ge 2) {
                $requestArg = $requestParts[1].Trim()
            }

            $resolveIndex = {
                param([string]$rawIndex)
                [int]$selectedIndex = 0
                if (-not [int]::TryParse($rawIndex, [ref]$selectedIndex) -or $selectedIndex -lt 1 -or $selectedIndex -gt $videoResults.Count) {
                    Write-Host "Invalid selection. Use commands like -play 3, -queue 2, -bookmark 1, -copyurl 4." -ForegroundColor Yellow
                    return $null
                }
                return $selectedIndex
            }

            switch ($requestCommand) {
                "-back" {
                    $clearBeforePrompt = $true
                    Write-Host
                    break selectionLoop
                }
                "-menu" {
                    return
                }
                "-exit" {
                    Write-Host "Exiting YouCLI..." -ForegroundColor Cyan
                    exit 0
                }
                "-display" {
                    continue selectionLoop
                }
                "-play" {
                    $selectedIndex = & $resolveIndex $requestArg
                    if ($null -eq $selectedIndex) {
                        continue
                    }

                    $selectedVideo = $videoResults[$selectedIndex - 1]
                    Play-VideoObject -Video $selectedVideo

                    $recentLabel = $selectedVideo.Title
                    if ($selectedVideo.PSObject.Properties.Name -contains "ChannelName" -and -not [string]::IsNullOrWhiteSpace($selectedVideo.ChannelName)) {
                        $recentLabel = "{0} [{1}]" -f $selectedVideo.Title, $selectedVideo.ChannelName
                    }

                    $script:RecentPlayedVideos = @($recentLabel) + @($script:RecentPlayedVideos | Where-Object { $_ -ne $recentLabel })
                    if ($script:RecentPlayedVideos.Count -gt 5) {
                        $script:RecentPlayedVideos = @($script:RecentPlayedVideos | Select-Object -First 5)
                    }

                    Write-Host
                    continue selectionLoop
                }
                "-queue" {
                    $selectedIndex = & $resolveIndex $requestArg
                    if ($null -eq $selectedIndex) {
                        continue
                    }

                    $selectedVideo = $videoResults[$selectedIndex - 1]
                    $script:Queue += [PSCustomObject]@{
                        Title = $selectedVideo.Title
                        Url = $selectedVideo.Url
                    }
                    Save-Queue
                    Write-Host "Added to queue." -ForegroundColor Green
                    continue selectionLoop
                }
                "-bookmark" {
                    $selectedIndex = & $resolveIndex $requestArg
                    if ($null -eq $selectedIndex) {
                        continue
                    }

                    $selectedVideo = $videoResults[$selectedIndex - 1]
                    $script:Bookmarks += [PSCustomObject]@{
                        Title = $selectedVideo.Title
                        Url = $selectedVideo.Url
                    }
                    Save-Bookmarks
                    Write-Host "Added to bookmarks." -ForegroundColor Green
                    continue selectionLoop
                }
                "-copyurl" {
                    $selectedIndex = & $resolveIndex $requestArg
                    if ($null -eq $selectedIndex) {
                        continue
                    }

                    $selectedVideo = $videoResults[$selectedIndex - 1]
                    try {
                        Set-Clipboard -Value $selectedVideo.Url
                        Write-Host "Video URL copied to clipboard." -ForegroundColor Green
                    } catch {
                        Write-Host "Could not copy URL to clipboard." -ForegroundColor Yellow
                    }
                    continue selectionLoop
                }
                default {
                    Write-Host "Invalid request. Use: -play N, -queue N, -bookmark N, -display, -copyurl N, -back, -menu, -exit" -ForegroundColor Yellow
                    continue selectionLoop
                }
            }
        }

        Write-Host
    }
}
