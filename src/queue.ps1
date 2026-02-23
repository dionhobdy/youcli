<#
Queue module for YouCLI.
This file is dot-sourced by the main script.
#>

<#
.SYNOPSIS
Runs the interactive queue menu.

.DESCRIPTION
Handles queue lifecycle actions including viewing items, adding new entries,
playing the next queued item, removing a specific item, and clearing the queue.
All mutating actions persist queue changes to disk and validate user selection
input before changes are applied.
#>
function Start-QueueMenu {
	while ($true) {
		Write-Host "=== Queue ===" -ForegroundColor Cyan
		Write-Host "[1] View queue"
		Write-Host "[2] Add to queue"
		Write-Host "[3] Play next"
		Write-Host "[4] Remove from queue"
		Write-Host "[5] Clear queue"
		Write-Host "[6] Back to Main Menu"
		Write-Host

		$choice = Read-Host "Choose an option"
		switch ($choice.Trim()) {
			"1" {
				Show-VideoList -VideoList $script:Queue -Heading "Queue"
			}
			"2" {
				$title = Read-Host "Queue item title"
				$url = Read-Host "Queue item URL"
				if ([string]::IsNullOrWhiteSpace($title) -or [string]::IsNullOrWhiteSpace($url)) {
					Write-Host "Title and URL are required." -ForegroundColor Yellow
				} else {
					$script:Queue += [PSCustomObject]@{
						Title = $title.Trim()
						Url = $url.Trim()
					}
					Save-Queue
				}
				Write-Host
			}
			"3" {
				if (-not $script:Queue -or $script:Queue.Count -eq 0) {
					Write-Host "Queue is empty." -ForegroundColor Yellow
					Write-Host
					continue
				}

				$nextItem = $script:Queue[0]
				Play-VideoObject -Video $nextItem
				$script:Queue = @($script:Queue | Select-Object -Skip 1)
				Save-Queue
				Write-Host
			}
			"4" {
				if (-not $script:Queue -or $script:Queue.Count -eq 0) {
					Write-Host "No queue items to remove." -ForegroundColor Yellow
					Write-Host
					continue
				}

				Show-VideoList -VideoList $script:Queue -Heading "Queue"
				$selection = Read-Host "Enter queue item number to remove"
				[int]$index = 0
				if ([int]::TryParse($selection, [ref]$index) -and $index -ge 1 -and $index -le $script:Queue.Count) {
					$newQueue = @()
					for ($i = 0; $i -lt $script:Queue.Count; $i++) {
						if ($i -ne ($index - 1)) {
							$newQueue += $script:Queue[$i]
						}
					}
					$script:Queue = $newQueue
					Save-Queue
				} else {
					Write-Host "Invalid selection." -ForegroundColor Yellow
				}
				Write-Host
			}
			"5" {
				$confirm = Read-Host "Clear full queue? (y/n)"
				if ($confirm.Trim().ToLower() -eq "y") {
					$script:Queue = @()
					Save-Queue
				}
				Write-Host
			}
			"6" { return }
			default {
				Write-Host "Invalid option." -ForegroundColor Yellow
				Write-Host
			}
		}
	}
}
