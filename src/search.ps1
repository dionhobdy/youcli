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

function Format-VideoTimestamp {
    param([object]$Timestamp, [string]$UploadDate)

    if ($null -ne $Timestamp) {
        try {
            $unix = [int64]$Timestamp
            return [DateTimeOffset]::FromUnixTimeSeconds($unix).LocalDateTime.ToString("yyyy-MM-dd HH:mm")
        } catch {
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($UploadDate) -and $UploadDate -match '^\d{8}$') {
        try {
            return [datetime]::ParseExact($UploadDate, "yyyyMMdd", $null).ToString("yyyy-MM-dd")
        } catch {
        }
    }

    return "Unknown"
}

function Format-VideoCount {
    param([object]$CountValue)

    if ($null -eq $CountValue) {
        return "Unknown"
    }

    try {
        return ("{0:N0}" -f ([double]$CountValue))
    } catch {
        return "Unknown"
    }
}

function Format-VideoDescriptionPreview {
    param([string]$DescriptionText)

    if ([string]::IsNullOrWhiteSpace($DescriptionText)) {
        return "Description unavailable."
    }

    $normalized = $DescriptionText -replace "`r`n", "`n"
    $normalized = $normalized.Trim()

    if ($normalized.Length -gt 700) {
        $normalized = $normalized.Substring(0, 697) + "..."
    }

    return $normalized
}

function Format-VideoLength {
    param([object]$DurationSeconds, [string]$DurationString)

    if (-not [string]::IsNullOrWhiteSpace($DurationString)) {
        return $DurationString.Trim()
    }

    if ($null -eq $DurationSeconds) {
        return "Unknown"
    }

    try {
        $total = [int64]$DurationSeconds
        if ($total -lt 0) {
            return "Unknown"
        }

        $hours = [math]::Floor($total / 3600)
        $minutes = [math]::Floor(($total % 3600) / 60)
        $seconds = $total % 60

        if ($hours -gt 0) {
            return ("{0}:{1:D2}:{2:D2}" -f $hours, $minutes, $seconds)
        }

        return ("{0}:{1:D2}" -f $minutes, $seconds)
    } catch {
        return "Unknown"
    }
}

function Get-TopLikedComments {
    param(
        [object]$Comments,
        [int]$Limit = 3
    )

    if ($null -eq $Comments) {
        return @()
    }

    $commentList = @()
    if ($Comments -is [System.Array]) {
        $commentList = @($Comments)
    } else {
        $commentList = @($Comments)
    }

    if (-not $commentList -or $commentList.Count -eq 0) {
        return @()
    }

    $rankedComments = $commentList |
        Where-Object {
            $_ -and -not [string]::IsNullOrWhiteSpace([string]$_.text)
        } |
        Sort-Object -Property @{ Expression = {
            try {
                if ($null -ne $_.like_count) {
                    return [int64]$_.like_count
                }
            } catch {
            }
            return 0
        }; Descending = $true }

    $topComments = $rankedComments | Select-Object -First $Limit
    if (-not $topComments) {
        return @()
    }

    $formatted = foreach ($comment in $topComments) {
        $likes = 0
        try {
            if ($null -ne $comment.like_count) {
                $likes = [int64]$comment.like_count
            }
        } catch {
        }

        $text = [string]$comment.text
        $text = $text -replace '\s+', ' '
        if ($text.Length -gt 160) {
            $text = $text.Substring(0, 157) + "..."
        }

        $author = [string]$comment.author
        if ([string]::IsNullOrWhiteSpace($author)) {
            $author = "Unknown"
        }

        "[{0:N0}] {1}: {2}" -f $likes, $author, $text
    }

    return @($formatted)
}

function Get-SearchVideoDetails {
    param(
        [Parameter(Mandatory = $true)]
        [string]$VideoUrl,

        [string]$FallbackTitle,
        [string]$FallbackChannel
    )

    $defaultDetails = [PSCustomObject]@{
        Title = $FallbackTitle
        ChannelName = $FallbackChannel
        Timestamp = "Unknown"
        Length = "Unknown"
        ThumbnailUrl = ""
        Description = "Description unavailable."
        ViewCount = "Unknown"
        LikeCount = "Unknown"
        TopComments = @()
    }

    $jsonOutput = & $script:YtDlpCommand @("--dump-single-json", "--no-playlist", "--no-warnings", "--skip-download", "--get-comments", $VideoUrl) 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $jsonOutput) {
        return $defaultDetails
    }

    $jsonText = ($jsonOutput | Out-String).Trim()
    if ([string]::IsNullOrWhiteSpace($jsonText)) {
        return $defaultDetails
    }

    try {
        $videoData = $jsonText | ConvertFrom-Json
    } catch {
        return $defaultDetails
    }

    $title = if (-not [string]::IsNullOrWhiteSpace($videoData.title)) { $videoData.title } else { $FallbackTitle }
    $channel = if (-not [string]::IsNullOrWhiteSpace($videoData.uploader)) { $videoData.uploader } else { $FallbackChannel }
    if ([string]::IsNullOrWhiteSpace($channel) -and -not [string]::IsNullOrWhiteSpace($videoData.channel)) {
        $channel = $videoData.channel
    }

    return [PSCustomObject]@{
        Title = $title
        ChannelName = $channel
        Timestamp = (Format-VideoTimestamp -Timestamp $videoData.release_timestamp -UploadDate $videoData.upload_date)
        Length = (Format-VideoLength -DurationSeconds $videoData.duration -DurationString ([string]$videoData.duration_string))
        ThumbnailUrl = [string]$videoData.thumbnail
        Description = (Format-VideoDescriptionPreview -DescriptionText ([string]$videoData.description))
        ViewCount = (Format-VideoCount -CountValue $videoData.view_count)
        LikeCount = (Format-VideoCount -CountValue $videoData.like_count)
        TopComments = (Get-TopLikedComments -Comments $videoData.comments -Limit 3)
    }
}

function Resolve-ThumbnailJpgUrl {
    param([string]$ThumbnailUrl)

    if ([string]::IsNullOrWhiteSpace($ThumbnailUrl)) {
        return $null
    }

    $candidateUrls = @()
    if ($ThumbnailUrl -match "(?i)\.jpe?g($|\?)") {
        $candidateUrls += $ThumbnailUrl
    }

    if ($ThumbnailUrl -match "^https?://i\.ytimg\.com/vi_webp/([^/]+)/") {
        $videoId = $Matches[1]
        $candidateUrls += "https://i.ytimg.com/vi/$videoId/hqdefault.jpg"
        $candidateUrls += "https://i.ytimg.com/vi/$videoId/mqdefault.jpg"
    } elseif ($ThumbnailUrl -match "^https?://i\.ytimg\.com/vi/([^/]+)/") {
        $videoId = $Matches[1]
        $candidateUrls += "https://i.ytimg.com/vi/$videoId/hqdefault.jpg"
        $candidateUrls += "https://i.ytimg.com/vi/$videoId/mqdefault.jpg"
    }

    if ($candidateUrls.Count -eq 0) {
        $candidateUrls += $ThumbnailUrl
    }

    return ($candidateUrls | Select-Object -First 1)
}

function Try-RenderInlineKittyImageFromUrl {
    param([string]$ImageUrl)

    if ([string]::IsNullOrWhiteSpace($ImageUrl)) {
        return $false
    }

    try {
        if ([enum]::GetNames([System.Net.SecurityProtocolType]) -contains "Tls12") {
            [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12
        }

        $webClient = New-Object System.Net.WebClient
        $imageBytes = $webClient.DownloadData($ImageUrl)
        if (-not $imageBytes -or $imageBytes.Length -eq 0) {
            return $false
        }

        $base64Data = [Convert]::ToBase64String($imageBytes)
        $chunkSize = 4096
        $offset = 0
        $esc = [string][char]27
        $prefix = "${esc}_G"
        $terminator = "${esc}\"

        while ($offset -lt $base64Data.Length) {
            $length = [Math]::Min($chunkSize, $base64Data.Length - $offset)
            $chunk = $base64Data.Substring($offset, $length)
            $offset += $length

            $more = if ($offset -lt $base64Data.Length) { 1 } else { 0 }
            if ($offset -eq $length) {
                [Console]::Out.Write("${prefix}a=T,f=100,m=$more;$chunk$terminator")
            } else {
                [Console]::Out.Write("${prefix}m=$more;$chunk$terminator")
            }
        }

        [Console]::Out.WriteLine()
        return $true
    } catch {
        return $false
    }
}

function Try-RenderInlineItermImageFromUrl {
    param([string]$ImageUrl)

    if ([string]::IsNullOrWhiteSpace($ImageUrl)) {
        return $false
    }

    try {
        if ([enum]::GetNames([System.Net.SecurityProtocolType]) -contains "Tls12") {
            [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12
        }

        $webClient = New-Object System.Net.WebClient
        $imageBytes = $webClient.DownloadData($ImageUrl)
        if (-not $imageBytes -or $imageBytes.Length -eq 0) {
            return $false
        }

        $base64Data = [Convert]::ToBase64String($imageBytes)
        $esc = [string][char]27
        $bel = [string][char]7

        [Console]::Out.Write("${esc}]1337;File=inline=1;width=auto;height=auto;preserveAspectRatio=1:$base64Data$bel")
        [Console]::Out.WriteLine()
        return $true
    } catch {
        return $false
    }
}

function Try-RenderInlineWezTermImgcatFromUrl {
    param([string]$ImageUrl)

    if ([string]::IsNullOrWhiteSpace($ImageUrl)) {
        return $false
    }

    $weztermCommand = Get-Command wezterm -ErrorAction SilentlyContinue
    if (-not $weztermCommand) {
        return $false
    }

    try {
        if ([enum]::GetNames([System.Net.SecurityProtocolType]) -contains "Tls12") {
            [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12
        }

        $webClient = New-Object System.Net.WebClient
        $imageBytes = $webClient.DownloadData($ImageUrl)
        if (-not $imageBytes -or $imageBytes.Length -eq 0) {
            return $false
        }

        $attempts = @(
            @("imgcat", "-"),
            @("cli", "imgcat", "-")
        )

        foreach ($attempt in $attempts) {
            $startInfo = New-Object System.Diagnostics.ProcessStartInfo
            $startInfo.FileName = $weztermCommand.Source
            $startInfo.UseShellExecute = $false
            $startInfo.RedirectStandardInput = $true
            $startInfo.RedirectStandardError = $false
            $startInfo.RedirectStandardOutput = $false
            $startInfo.CreateNoWindow = $true
            $startInfo.ArgumentList.Clear()
            foreach ($arg in $attempt) {
                [void]$startInfo.ArgumentList.Add($arg)
            }

            $process = New-Object System.Diagnostics.Process
            $process.StartInfo = $startInfo

            $started = $process.Start()
            if (-not $started) {
                continue
            }

            $process.StandardInput.BaseStream.Write($imageBytes, 0, $imageBytes.Length)
            $process.StandardInput.BaseStream.Flush()
            $process.StandardInput.Close()

            $process.WaitForExit()
            if ($process.ExitCode -eq 0) {
                return $true
            }
        }
    } catch {
        return $false
    }

    return $false
}

function Show-InlineThumbnailOrLink {
    param([string]$ThumbnailUrl)

    $jpgUrl = Resolve-ThumbnailJpgUrl -ThumbnailUrl $ThumbnailUrl
    if ([string]::IsNullOrWhiteSpace($jpgUrl)) {
        Write-Host "Thumbnail preview unavailable." -ForegroundColor DarkGray
        return [PSCustomObject]@{
            Mode = "unavailable"
            Inline = $false
            Url = ""
            Detail = "no-thumbnail-url"
        }
    }

    $renderedInline = $false
    $renderMode = "link"
    $renderDetail = "fallback"
    $attemptLog = @()

    try {
        $isWezTermSession = (-not [string]::IsNullOrWhiteSpace($env:WEZTERM_PANE)) -or ($env:TERM_PROGRAM -eq "WezTerm") -or ($env:TERM -match "wezterm")
        $isKittySession = ($env:TERM -match "xterm-kitty")

        if ($isWezTermSession) {
            $renderedInline = Try-RenderInlineWezTermImgcatFromUrl -ImageUrl $jpgUrl
            if ($renderedInline) {
                $renderMode = "wezterm-imgcat-stdin"
                $renderDetail = "stdin-bytes"
            } else {
                $attemptLog += "wezterm-stdin=failed"

                $renderedInline = Try-RenderInlineItermImageFromUrl -ImageUrl $jpgUrl
                if ($renderedInline) {
                    $renderMode = "iterm-protocol"
                    $renderDetail = "inline-base64"
                } else {
                    $attemptLog += "iterm-protocol=failed"
                }
            }
        }

        if (-not $renderedInline -and $isWezTermSession) {
            $weztermCommand = Get-Command wezterm -ErrorAction SilentlyContinue
            if ($weztermCommand) {
                $directAttempts = @(
                    @("imgcat", "-"),
                    @("imgcat", $jpgUrl)
                )

                foreach ($attempt in $directAttempts) {
                    $attemptName = $attempt -join " "
                    $exitCode = 0
                    $output = @()

                    if ($attempt.Count -ge 2 -and $attempt[1] -eq "-") {
                        try {
                            if ([enum]::GetNames([System.Net.SecurityProtocolType]) -contains "Tls12") {
                                [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12
                            }
                            $webClient = New-Object System.Net.WebClient
                            $imageBytes = $webClient.DownloadData($jpgUrl)

                            $startInfo = New-Object System.Diagnostics.ProcessStartInfo
                            $startInfo.FileName = $weztermCommand.Source
                            $startInfo.UseShellExecute = $false
                            $startInfo.RedirectStandardInput = $true
                            $startInfo.RedirectStandardError = $true
                            $startInfo.RedirectStandardOutput = $true
                            $startInfo.CreateNoWindow = $true
                            $startInfo.ArgumentList.Clear()
                            [void]$startInfo.ArgumentList.Add("imgcat")
                            [void]$startInfo.ArgumentList.Add("-")

                            $process = New-Object System.Diagnostics.Process
                            $process.StartInfo = $startInfo
                            [void]$process.Start()

                            $process.StandardInput.BaseStream.Write($imageBytes, 0, $imageBytes.Length)
                            $process.StandardInput.BaseStream.Flush()
                            $process.StandardInput.Close()

                            $stdOut = $process.StandardOutput.ReadToEnd()
                            $stdErr = $process.StandardError.ReadToEnd()
                            $process.WaitForExit()

                            $exitCode = $process.ExitCode
                            $output = @($stdOut, $stdErr) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
                        } catch {
                            $exitCode = 1
                            $output = @($_.Exception.Message)
                        }
                    } else {
                        $output = & $weztermCommand.Source @attempt 2>&1
                        $exitCode = $LASTEXITCODE
                    }

                    if ($exitCode -eq 0) {
                        $renderedInline = $true
                        $renderMode = "wezterm-cli"
                        $renderDetail = $attemptName
                        break
                    }

                    $firstError = ($output | Select-Object -First 1)
                    if ($firstError) {
                        $attemptLog += ("{0}=exit{1}:{2}" -f $attemptName, $exitCode, $firstError)
                    } else {
                        $attemptLog += ("{0}=exit{1}" -f $attemptName, $exitCode)
                    }
                }
            } else {
                $attemptLog += "wezterm-command-missing"
            }
        }

        if (-not $renderedInline -and $isKittySession) {
            $renderedInline = Try-RenderInlineKittyImageFromUrl -ImageUrl $jpgUrl
            if ($renderedInline) {
                $renderMode = "graphics-protocol"
                $renderDetail = "in-memory"
            } else {
                $attemptLog += "kitty-protocol=failed"
            }
        }

        if (-not $renderedInline -and $env:TERM -match "xterm-kitty") {
            $kittenCommand = Get-Command kitten -ErrorAction SilentlyContinue
            if ($kittenCommand) {
                $kittyOutput = & $kittenCommand.Source icat $jpgUrl 2>&1
                if ($LASTEXITCODE -eq 0) {
                    $renderedInline = $true
                    $renderMode = "kitty-icat"
                    $renderDetail = "kitten icat"
                } else {
                    $kittyErr = ($kittyOutput | Select-Object -First 1)
                    if ($kittyErr) {
                        $attemptLog += ("kitten icat=exit{0}:{1}" -f $LASTEXITCODE, $kittyErr)
                    } else {
                        $attemptLog += ("kitten icat=exit{0}" -f $LASTEXITCODE)
                    }
                }
            }
        }
    } catch {
        $renderedInline = $false
        $renderMode = "error"
        $renderDetail = $_.Exception.Message
    }

    if (-not $renderedInline) {
        Write-Host ("Thumbnail JPG: {0}" -f $jpgUrl) -ForegroundColor DarkGray
        if ($renderMode -ne "error") {
            $renderMode = "link"
            if ($renderDetail -eq "fallback") {
                $renderDetail = "inline-not-supported-or-failed"
            }
        }
        if ($attemptLog.Count -gt 0) {
            $renderDetail = "{0}; attempts={1}" -f $renderDetail, ($attemptLog -join " | ")
        }
    }

    return [PSCustomObject]@{
        Mode = $renderMode
        Inline = $renderedInline
        Url = $jpgUrl
        Detail = $renderDetail
    }
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
    Write-Host "Type 'Back' to reload search." -ForegroundColor DarkGray
    Write-Host "Type 'Menu' to return to Main Menu." -ForegroundColor DarkGray
    Write-Host "Type 'Exit' to close YouCLI." -ForegroundColor DarkGray
    Write-Host

    $previousSearchQuery = $null
    $clearBeforePrompt = $false

    while ($true) {
        if ($clearBeforePrompt) {
            Clear-Host
            Show-YouCliBanner
            Write-Host "Type 'Back' to reload search." -ForegroundColor DarkGray
            Write-Host "Type 'Menu' to return to Main Menu." -ForegroundColor DarkGray
            Write-Host "Type 'Exit' to close YouCLI." -ForegroundColor DarkGray
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

        $videoDetailsCache = @{}

        :selectionLoop while ($true) {
            $prefix = Get-CommandPrefix
            Sync-QueueWithVlcPlayback
            Clear-Host
            Show-YouCliBanner
            Write-Host ("Enter a search query for YouTube: {0}" -f $query)
            Write-Host
            Show-VideoList -VideoList $videoResults -Heading "Search Results"

            Write-Host ("prefix: {0}" -f $prefix) -ForegroundColor DarkGray
            Write-Host "back bookmark copyurl display menu play queue" -ForegroundColor DarkGray
            Write-Host "i.e. [prefix]display [number]" -ForegroundColor DarkGray
            if ($script:RecentPlayedVideos -and $script:RecentPlayedVideos.Count -gt 0) {
                $recentPreview = $script:RecentPlayedVideos | Select-Object -First 5
                Write-Host "Recent:" -ForegroundColor DarkGray
                foreach ($recentItem in $recentPreview) {
                    Write-Host $recentItem -ForegroundColor DarkGray
                }
            }

            $selection = Read-Host "Input Request"
            if ([string]::IsNullOrWhiteSpace($selection)) {
                Write-Host "Please enter a value." -ForegroundColor Yellow
                continue
            }

            $requestText = $selection.Trim()
            $requestParts = $requestText -split '\s+', 2
            $requestCommand = ConvertTo-InternalCommand -CommandToken $requestParts[0]
            $requestArg = ""
            if ($requestParts.Count -ge 2) {
                $requestArg = $requestParts[1].Trim()
            }

            if ([string]::IsNullOrWhiteSpace($requestCommand)) {
                Write-Host ("Invalid request. Use: {0}play N, {0}queue N, {0}bookmark N, {0}display, {0}copyurl N, {0}back, {0}menu, {0}exit" -f $prefix) -ForegroundColor Yellow
                continue selectionLoop
            }

            $resolveIndex = {
                param([string]$rawIndex)
                [int]$selectedIndex = 0
                if (-not [int]::TryParse($rawIndex, [ref]$selectedIndex) -or $selectedIndex -lt 1 -or $selectedIndex -gt $videoResults.Count) {
                    Write-Host ("Invalid selection. Use commands like {0}play 3, {0}queue 2, {0}bookmark 1, {0}display 4." -f $prefix) -ForegroundColor Yellow
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
                    $selectedIndex = & $resolveIndex $requestArg
                    if ($null -eq $selectedIndex) {
                        continue selectionLoop
                    }

                    :detailLoop while ($true) {
                        $selectedVideo = $videoResults[$selectedIndex - 1]
                        $detailsKey = $selectedVideo.Url
                        if (-not $videoDetailsCache.ContainsKey($detailsKey)) {
                            $fallbackChannel = "Unknown Channel"
                            if ($selectedVideo.PSObject.Properties.Name -contains "ChannelName" -and -not [string]::IsNullOrWhiteSpace($selectedVideo.ChannelName)) {
                                $fallbackChannel = $selectedVideo.ChannelName
                            }
                            $videoDetailsCache[$detailsKey] = Get-SearchVideoDetails -VideoUrl $selectedVideo.Url -FallbackTitle $selectedVideo.Title -FallbackChannel $fallbackChannel
                        }

                        $details = $videoDetailsCache[$detailsKey]

                        Clear-Host
                        Show-YouCliBanner
                        Write-Host ("Enter a search query for YouTube: {0}" -f $query)
                        Write-Host
                        Write-Host ("{0} - {1}" -f $details.Title, $details.ChannelName)
                        Write-Host ("{0} | {1}" -f $details.Timestamp, $details.Length)

                        $null = Show-InlineThumbnailOrLink -ThumbnailUrl $details.ThumbnailUrl
                        Write-Host
                        Write-Host $details.Description -ForegroundColor DarkGray

                        Write-Host ("{0} views - {1} likes" -f $details.ViewCount, $details.LikeCount)
                        if ($details.TopComments -and $details.TopComments.Count -gt 0) {
                            Write-Host "Top Comments:" -ForegroundColor DarkGray
                            foreach ($commentLine in $details.TopComments) {
                                Write-Host $commentLine -ForegroundColor DarkGray
                            }
                        } else {
                            Write-Host "Top Comments: unavailable." -ForegroundColor DarkGray
                        }
                        Write-Host
                        Write-Host ("prefix: {0}" -f $prefix) -ForegroundColor DarkGray
                        Write-Host "back bookmark copyurl menu play queue" -ForegroundColor DarkGray
                        Write-Host "i.e. [prefix]back" -ForegroundColor DarkGray

                        if ($script:RecentPlayedVideos -and $script:RecentPlayedVideos.Count -gt 0) {
                            $recentPreview = $script:RecentPlayedVideos | Select-Object -First 5
                            Write-Host "Recent:" -ForegroundColor DarkGray
                            foreach ($recentItem in $recentPreview) {
                                Write-Host $recentItem -ForegroundColor DarkGray
                            }
                        }

                        $detailSelection = Read-Host "Input Request"
                        if ([string]::IsNullOrWhiteSpace($detailSelection)) {
                            Write-Host "Please enter a value." -ForegroundColor Yellow
                            continue detailLoop
                        }

                        $detailParts = $detailSelection.Trim() -split '\s+', 2
                        $detailCommand = ConvertTo-InternalCommand -CommandToken $detailParts[0]
                        $detailArg = ""
                        if ($detailParts.Count -ge 2) {
                            $detailArg = $detailParts[1].Trim()
                        }

                        if ([string]::IsNullOrWhiteSpace($detailCommand)) {
                            Write-Host ("Invalid request. Use: {0}play N, {0}queue N, {0}bookmark N, {0}copyurl N, {0}back, {0}menu, {0}exit" -f $prefix) -ForegroundColor Yellow
                            continue detailLoop
                        }

                        switch ($detailCommand) {
                            "-back" {
                                break detailLoop
                            }
                            "-menu" {
                                return
                            }
                            "-exit" {
                                Write-Host "Exiting YouCLI..." -ForegroundColor Cyan
                                exit 0
                            }
                            "-play" {
                                $targetIndex = $selectedIndex
                                if (-not [string]::IsNullOrWhiteSpace($detailArg)) {
                                    $targetIndex = & $resolveIndex $detailArg
                                    if ($null -eq $targetIndex) {
                                        continue detailLoop
                                    }
                                }

                                $targetVideo = $videoResults[$targetIndex - 1]
                                Play-VideoObject -Video $targetVideo

                                $recentLabel = "[{0}] {1}" -f $targetIndex, $targetVideo.Title
                                $script:RecentPlayedVideos = @($recentLabel) + @($script:RecentPlayedVideos | Where-Object { $_ -ne $recentLabel })
                                if ($script:RecentPlayedVideos.Count -gt 5) {
                                    $script:RecentPlayedVideos = @($script:RecentPlayedVideos | Select-Object -First 5)
                                }

                                continue detailLoop
                            }
                            "-queue" {
                                $targetIndex = $selectedIndex
                                if (-not [string]::IsNullOrWhiteSpace($detailArg)) {
                                    $targetIndex = & $resolveIndex $detailArg
                                    if ($null -eq $targetIndex) {
                                        continue detailLoop
                                    }
                                }

                                $targetVideo = $videoResults[$targetIndex - 1]
                                Add-VideoToQueue -Video $targetVideo -EnqueueInVlc
                                Write-Host "Added to queue. It will auto-play after the current video." -ForegroundColor Green
                                continue detailLoop
                            }
                            "-bookmark" {
                                $targetIndex = $selectedIndex
                                if (-not [string]::IsNullOrWhiteSpace($detailArg)) {
                                    $targetIndex = & $resolveIndex $detailArg
                                    if ($null -eq $targetIndex) {
                                        continue detailLoop
                                    }
                                }

                                $targetVideo = $videoResults[$targetIndex - 1]
                                $script:Bookmarks += [PSCustomObject]@{
                                    Title = $targetVideo.Title
                                    Url = $targetVideo.Url
                                }
                                Save-Bookmarks
                                Write-Host "Added to bookmarks." -ForegroundColor Green
                                continue detailLoop
                            }
                            "-copyurl" {
                                $targetIndex = $selectedIndex
                                if (-not [string]::IsNullOrWhiteSpace($detailArg)) {
                                    $targetIndex = & $resolveIndex $detailArg
                                    if ($null -eq $targetIndex) {
                                        continue detailLoop
                                    }
                                }

                                $targetVideo = $videoResults[$targetIndex - 1]
                                try {
                                    Set-Clipboard -Value $targetVideo.Url
                                    Write-Host "Video URL copied to clipboard." -ForegroundColor Green
                                } catch {
                                    Write-Host "Could not copy URL to clipboard." -ForegroundColor Yellow
                                }
                                continue detailLoop
                            }
                            default {
                                Write-Host ("Invalid request. Use: {0}play N, {0}queue N, {0}bookmark N, {0}copyurl N, {0}back, {0}menu, {0}exit" -f $prefix) -ForegroundColor Yellow
                                continue detailLoop
                            }
                        }
                    }

                    continue selectionLoop
                }
                "-play" {
                    $selectedIndex = & $resolveIndex $requestArg
                    if ($null -eq $selectedIndex) {
                        continue
                    }

                    $selectedVideo = $videoResults[$selectedIndex - 1]
                    Play-VideoObject -Video $selectedVideo

                    $recentLabel = "[{0}] {1}" -f $selectedIndex, $selectedVideo.Title

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
                    Add-VideoToQueue -Video $selectedVideo -EnqueueInVlc
                    Write-Host "Added to queue. It will auto-play after the current video." -ForegroundColor Green
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
                    Write-Host ("Invalid request. Use: {0}play N, {0}queue N, {0}bookmark N, {0}display N, {0}copyurl N, {0}back, {0}menu, {0}exit" -f $prefix) -ForegroundColor Yellow
                    continue selectionLoop
                }
            }
        }

        Write-Host
    }
}
