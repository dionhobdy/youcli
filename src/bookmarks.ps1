<#
Bookmarks module for YouCLI.
This file is dot-sourced by the main script.
#>

<#
.SYNOPSIS
Runs the interactive bookmarks menu.

.DESCRIPTION
Provides bookmark management operations including listing, adding, playback,
removal, and full clear actions. User input is validated for required fields
and valid item indexes before persistence updates are applied.
#>
function Start-BookmarksMenu {
	while ($true) {
		Write-Host "=== Bookmarks ===" -ForegroundColor Cyan
		Write-Host "[1] View bookmarks"
		Write-Host "[2] Add bookmark"
		Write-Host "[3] Play bookmark"
		Write-Host "[4] Remove bookmark"
		Write-Host "[5] Clear bookmarks"
		Write-Host "[6] Back to Main Menu"
		Write-Host

		$choice = Read-Host "Choose an option"
		switch ($choice.Trim()) {
			"1" {
				Show-VideoList -VideoList $script:Bookmarks -Heading "Bookmarks"
			}
			"2" {
				$title = Read-Host "Bookmark title"
				$url = Read-Host "Bookmark URL"
				if ([string]::IsNullOrWhiteSpace($title) -or [string]::IsNullOrWhiteSpace($url)) {
					Write-Host "Title and URL are required." -ForegroundColor Yellow
				} else {
					$script:Bookmarks += [PSCustomObject]@{
						Title = $title.Trim()
						Url = $url.Trim()
					}
					Save-Bookmarks
				}
				Write-Host
			}
			"3" {
				if (-not $script:Bookmarks -or $script:Bookmarks.Count -eq 0) {
					Write-Host "No bookmarks available." -ForegroundColor Yellow
					Write-Host
					continue
				}

				Show-VideoList -VideoList $script:Bookmarks -Heading "Bookmarks"
				$selection = Read-Host "Enter bookmark number"
				[int]$index = 0
				if (-not [int]::TryParse($selection, [ref]$index) -or $index -lt 1 -or $index -gt $script:Bookmarks.Count) {
					Write-Host "Invalid selection." -ForegroundColor Yellow
					Write-Host
					continue
				}

				$selected = $script:Bookmarks[$index - 1]
				Play-VideoObject -Video $selected
			}
			"4" {
				if (-not $script:Bookmarks -or $script:Bookmarks.Count -eq 0) {
					Write-Host "No bookmarks to remove." -ForegroundColor Yellow
					Write-Host
					continue
				}

				Show-VideoList -VideoList $script:Bookmarks -Heading "Bookmarks"
				$selection = Read-Host "Enter bookmark number to remove"
				[int]$index = 0
				if ([int]::TryParse($selection, [ref]$index) -and $index -ge 1 -and $index -le $script:Bookmarks.Count) {
					$newBookmarks = @()
					for ($i = 0; $i -lt $script:Bookmarks.Count; $i++) {
						if ($i -ne ($index - 1)) {
							$newBookmarks += $script:Bookmarks[$i]
						}
					}
					$script:Bookmarks = $newBookmarks
					Save-Bookmarks
					Write-Host "Bookmark removed." -ForegroundColor Green
				} else {
					Write-Host "Invalid selection." -ForegroundColor Yellow
				}
				Write-Host
			}
			"5" {
				$confirm = Read-Host "Clear all bookmarks? (y/n)"
				if ($confirm.Trim().ToLower() -eq "y") {
					$script:Bookmarks = @()
					Save-Bookmarks
					Write-Host "Bookmarks cleared." -ForegroundColor Green
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
