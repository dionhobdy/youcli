<#
Queue module for YouCLI.
This file is dot-sourced by the main script.
#>

<#
.SYNOPSIS
Adds a video item to the queue.

.DESCRIPTION
Appends the provided video metadata to the in-memory queue, persists queue data,
and can optionally enqueue the URL in an already-running VLC instance so it
automatically plays after the current media finishes.

.PARAMETER Video
Video object containing at minimum Title and Url properties.

.PARAMETER EnqueueInVlc
When set, attempts to enqueue the item in an existing VLC instance.
#>
function Add-VideoToQueue {
	param(
		[Parameter(Mandatory = $true)]
		[psobject]$Video,

		[switch]$EnqueueInVlc
	)

	$queueItem = [PSCustomObject]@{
		Title = $Video.Title
		Url = $Video.Url
	}

	$script:Queue += $queueItem
	Save-Queue

	if ($EnqueueInVlc.IsPresent) {
		$existingVlc = Get-Process -Name "vlc" -ErrorAction SilentlyContinue | Select-Object -First 1
		if ($existingVlc) {
			$enqueueUrl = $queueItem.Url
			$streamResolution = Resolve-StreamUrl -VideoUrl $queueItem.Url
			if ($streamResolution -and -not [string]::IsNullOrWhiteSpace($streamResolution.Url)) {
				$enqueueUrl = $streamResolution.Url
			}

			Start-Process -FilePath $script:VlcCommand -ArgumentList @("--one-instance", "--playlist-enqueue", $enqueueUrl) | Out-Null
		}
	}
}

<#
.SYNOPSIS
Synchronizes queue state with VLC playback progression.

.DESCRIPTION
When VLC is actively playing, checks the VLC window title against the first
queued item. If they match, removes that item from the app queue so the queue
reflects upcoming entries only.
#>
function Sync-QueueWithVlcPlayback {
	if (-not $script:Queue -or $script:Queue.Count -eq 0) {
		return
	}

	$vlcProcess = Get-Process -Name "vlc" -ErrorAction SilentlyContinue | Select-Object -First 1
	if (-not $vlcProcess) {
		return
	}

	$windowTitle = $vlcProcess.MainWindowTitle
	if ([string]::IsNullOrWhiteSpace($windowTitle)) {
		return
	}

	$firstQueueItem = $script:Queue[0]
	if (-not $firstQueueItem -or [string]::IsNullOrWhiteSpace($firstQueueItem.Title)) {
		return
	}

	$titlePattern = "*{0}*" -f [WildcardPattern]::Escape($firstQueueItem.Title)
	if ($windowTitle -like $titlePattern) {
		$script:Queue = @($script:Queue | Select-Object -Skip 1)
		Save-Queue
	}
}

<#
.SYNOPSIS
Runs the interactive queue menu.

.DESCRIPTION
Handles queue lifecycle actions through prefixed commands, including display,
add, play, remove, and clear operations. Displays command hints plus recent
played history and validates request arguments before changes are applied.
#>
function Start-QueueMenu {
	while ($true) {
		$prefix = Get-CommandPrefix
		Sync-QueueWithVlcPlayback
		Clear-Host
		Show-YouCliBanner
		Write-Host "Queue" -ForegroundColor Red
		if (-not $script:Queue -or $script:Queue.Count -eq 0) {
			Write-Host ("Queue is empty. Use {0}back to return to Main Menu." -f $prefix) -ForegroundColor Yellow
			Write-Host
		} else {
			Show-VideoList -VideoList $script:Queue -Heading "Queue"
		}

		Write-Host ("prefix: {0}" -f $prefix) -ForegroundColor DarkGray
		Write-Host "add back clear display play remove" -ForegroundColor DarkGray
		Write-Host "i.e. [prefix]remove [number]" -ForegroundColor DarkGray
		Show-RecentInputRequests

		$choice = Read-Host "Input Request"
		if ([string]::IsNullOrWhiteSpace($choice)) {
			Write-Host "Please enter a value." -ForegroundColor Yellow
			Start-Sleep -Milliseconds 700
			continue
		}
		Add-RecentInputRequest -Request $choice

		$requestParts = $choice.Trim() -split '\s+', 2
		$requestCommand = ConvertTo-InternalCommand -CommandToken $requestParts[0]
		$requestArg = ""
		if ($requestParts.Count -ge 2) {
			$requestArg = $requestParts[1].Trim()
		}

		if ([string]::IsNullOrWhiteSpace($requestCommand)) {
			Write-Host ("Invalid request. Use: {0}add, {0}play, {0}remove N, {0}clear, {0}display, {0}back" -f $prefix) -ForegroundColor Yellow
			Start-Sleep -Milliseconds 900
			continue
		}

		$resolveIndex = {
			param([string]$rawIndex)
			[int]$index = 0
			if (-not [int]::TryParse($rawIndex, [ref]$index) -or $index -lt 1 -or $index -gt $script:Queue.Count) {
				Write-Host "Invalid selection index." -ForegroundColor Yellow
				return $null
			}
			return $index
		}

		switch ($requestCommand) {
			"-display" { }
			"-add" {
				$title = Read-Host "Queue item title"
				$url = Read-Host "Queue item URL"
				if ([string]::IsNullOrWhiteSpace($title) -or [string]::IsNullOrWhiteSpace($url)) {
					Write-Host "Title and URL are required." -ForegroundColor Yellow
					Start-Sleep -Milliseconds 900
					continue
				}

				Add-VideoToQueue -Video ([PSCustomObject]@{ Title = $title.Trim(); Url = $url.Trim() })
			}
			"-play" {
				if (-not $script:Queue -or $script:Queue.Count -eq 0) {
					Write-Host ("Queue is empty. Use {0}back to return to Main Menu." -f $prefix) -ForegroundColor Yellow
					Start-Sleep -Milliseconds 900
					continue
				}

				$nextItem = $script:Queue[0]
				Play-VideoObject -Video $nextItem
				$script:Queue = @($script:Queue | Select-Object -Skip 1)
				Save-Queue
			}
			"-remove" {
				if (-not $script:Queue -or $script:Queue.Count -eq 0) {
					Write-Host ("Queue is empty. Use {0}back to return to Main Menu." -f $prefix) -ForegroundColor Yellow
					Start-Sleep -Milliseconds 900
					continue
				}

				$index = & $resolveIndex $requestArg
				if ($null -eq $index) {
					Start-Sleep -Milliseconds 900
					continue
				}

				$newQueue = @()
				for ($i = 0; $i -lt $script:Queue.Count; $i++) {
					if ($i -ne ($index - 1)) {
						$newQueue += $script:Queue[$i]
					}
				}
				$script:Queue = $newQueue
				Save-Queue
				Write-Host "Queue item removed permanently." -ForegroundColor Green
				Start-Sleep -Milliseconds 700
			}
			"-clear" {
				$confirm = Read-Host "Clear full queue? (y/n)"
				if ($confirm.Trim().ToLower() -eq "y") {
					$script:Queue = @()
					Save-Queue
					Write-Host "Queue cleared permanently." -ForegroundColor Green
					Start-Sleep -Milliseconds 700
				}
			}
			"-back" { return }
			default {
				Write-Host ("Invalid request. Use: {0}add, {0}play, {0}remove N, {0}clear, {0}display, {0}back" -f $prefix) -ForegroundColor Yellow
				Start-Sleep -Milliseconds 900
			}
		}
	}
}
