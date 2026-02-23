<#
Playback module for YouCLI.
This file is dot-sourced by the main script.
#>

<#
.SYNOPSIS
Attempts to resolve a direct playable media URL for a YouTube video.

.DESCRIPTION
Executes yt-dlp using multiple fallback strategies (format variants, client
profiles, and browser cookie sources) to improve reliability on restricted or
difficult videos. Captures attempt diagnostics to the debug log and returns
the first successful stream URL with metadata about the strategy used.

.PARAMETER VideoUrl
The source video page URL to resolve.

.OUTPUTS
PSCustomObject with Url, Attempt, and ErrorPreview properties.
#>
function Resolve-StreamUrl {
	param(
		[Parameter(Mandatory = $true)]
		[string]$VideoUrl
	)

	$attempts = @(
		[ordered]@{
			Name = "default"
			Args = @("-f", "best[acodec!=none][vcodec!=none]/best", "-g")
		},
		[ordered]@{
			Name = "dash-fallback"
			Args = @("-f", "bv*+ba/best", "-g")
		},
		[ordered]@{
			Name = "mp4-fallback"
			Args = @("-f", "b[ext=mp4]/best", "-g")
		},
		[ordered]@{
			Name = "client-fallback"
			Args = @("--extractor-args", "youtube:player_client=android,web,ios", "-f", "best[acodec!=none][vcodec!=none]/best", "-g")
		},
		[ordered]@{
			Name = "cookies-edge"
			Args = @("--cookies-from-browser", "edge", "-f", "best[acodec!=none][vcodec!=none]/best", "-g")
		},
		[ordered]@{
			Name = "cookies-chrome"
			Args = @("--cookies-from-browser", "chrome", "-f", "best[acodec!=none][vcodec!=none]/best", "-g")
		},
		[ordered]@{
			Name = "cookies-firefox"
			Args = @("--cookies-from-browser", "firefox", "-f", "best[acodec!=none][vcodec!=none]/best", "-g")
		}
	)

	$lastErrorPreview = @()
	$lastAttemptName = ""

	foreach ($attempt in $attempts) {
		$lastAttemptName = $attempt.Name
		$commonArgs = @(
			"--no-playlist",
			"--no-warnings",
			"--socket-timeout", "20",
			"--extractor-retries", "3",
			"--fragment-retries", "3",
			"--retries", "3"
		)

		$streamOutput = & $script:YtDlpCommand @commonArgs @($attempt.Args) $VideoUrl 2>&1
		try {
			$logDir = Split-Path -Path $script:YtDlpDebugLogPath -Parent
			if (-not (Test-Path $logDir)) {
				New-Item -ItemType Directory -Path $logDir -Force | Out-Null
			}
			Add-Content -Path $script:YtDlpDebugLogPath -Value ("[{0}] Attempt={1} Url={2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $attempt.Name, $VideoUrl)
			$streamOutput | ForEach-Object { Add-Content -Path $script:YtDlpDebugLogPath -Value ("  {0}" -f $_) }
			Add-Content -Path $script:YtDlpDebugLogPath -Value ""
		} catch {
		}

		$streamUrl = $streamOutput | Where-Object {
			($_ -is [string]) -and ($_ -match "^https?://")
		} | Select-Object -First 1

		if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($streamUrl)) {
			return [PSCustomObject]@{
				Url = $streamUrl
				Attempt = $attempt.Name
				ErrorPreview = @()
			}
		}

		$errorLines = @(
			$streamOutput |
				Where-Object {
					($_ -is [string]) -and ($_ -match "(?i)error|warning|unable|forbidden|sign in|bot")
				}
		)

		if ($errorLines.Count -gt 0) {
			$lastErrorPreview = @($errorLines | Select-Object -First 5)
		} else {
			$lastErrorPreview = @(
				$streamOutput |
					Where-Object { $_ -is [string] } |
					Select-Object -First 5
			)
		}
	}

	return [PSCustomObject]@{
		Url = $null
		Attempt = $lastAttemptName
		ErrorPreview = $lastErrorPreview
	}
}

<#
.SYNOPSIS
Launches VLC playback for a resolved stream URL.

.DESCRIPTION
If VLC is already running, sends the new playback URL to the existing instance.
Otherwise starts VLC with preferred window size and network caching options,
then checks whether startup failed and retries with a simpler argument set and
the fallback URL.

.PARAMETER PlaybackUrl
Primary direct media URL resolved from yt-dlp.

.PARAMETER FallbackUrl
Fallback URL (typically the original page URL) used for retry logic.
#>
function Start-VlcPlayback {
	param(
		[Parameter(Mandatory = $true)]
		[string]$PlaybackUrl,

		[Parameter(Mandatory = $true)]
		[string]$FallbackUrl
	)

	$existingVlc = Get-Process -Name "vlc" -ErrorAction SilentlyContinue | Select-Object -First 1
	if ($existingVlc) {
		Start-Process -FilePath $script:VlcCommand -ArgumentList @("--one-instance", "--no-playlist-enqueue", $PlaybackUrl) | Out-Null
		return
	}

	$vlcArgs = @("--width=800", "--height=450", "--network-caching=1500", $PlaybackUrl)
	$vlcProcess = Start-Process -FilePath $script:VlcCommand -ArgumentList $vlcArgs -PassThru

	Start-Sleep -Seconds 2
	if ($vlcProcess.HasExited) {
		Write-Host "VLC closed unexpectedly. Retrying with a simpler launch..." -ForegroundColor Yellow
		Start-Process -FilePath $script:VlcCommand -ArgumentList @("--width=800", "--height=450", $FallbackUrl) | Out-Null
	}
}

<#
.SYNOPSIS
Coordinates playback for a selected video object.

.DESCRIPTION
Resolves a stream URL from the selected video metadata, displays diagnostics
when resolution fails, and launches VLC playback when successful. If all stream
resolution strategies fail, it offers to open the original video URL in the
default browser instead of attempting another VLC launch.

.PARAMETER Video
Video object that includes at minimum Title and Url properties.
#>
function Play-VideoObject {
	param(
		[Parameter(Mandatory = $true)]
		[psobject]$Video
	)

	$streamResolution = Resolve-StreamUrl -VideoUrl $Video.Url
	if (-not $streamResolution -or [string]::IsNullOrWhiteSpace($streamResolution.Url)) {
		Write-Host "Could not resolve a playable stream URL." -ForegroundColor Yellow
		Write-Host "Tried multiple strategies, including browser cookies." -ForegroundColor Yellow
		if ($streamResolution -and $streamResolution.Attempt) {
			Write-Host "Last strategy attempted: $($streamResolution.Attempt)" -ForegroundColor DarkYellow
		}
		if ($streamResolution -and $streamResolution.ErrorPreview -and $streamResolution.ErrorPreview.Count -gt 0) {
			Write-Host "yt-dlp said:" -ForegroundColor DarkYellow
			$streamResolution.ErrorPreview | ForEach-Object { Write-Host $_ }
		}
		Write-Host "Debug log: $script:YtDlpDebugLogPath" -ForegroundColor DarkYellow

		$openInBrowser = Read-Host "Open this video in your browser instead? (y/n)"
		if ($openInBrowser.Trim().ToLower() -eq "y") {
			Start-Process -FilePath "rundll32.exe" -ArgumentList @("url.dll,FileProtocolHandler", $Video.Url) | Out-Null
		}
		Write-Host
		return
	}

	Start-VlcPlayback -PlaybackUrl $streamResolution.Url -FallbackUrl $Video.Url
	Write-Host
}
