<#
Bookmarks module for YouCLI.
This file is dot-sourced by the main script.
#>

<#
.SYNOPSIS
Runs the interactive bookmarks menu.

.DESCRIPTION
Provides bookmark management operations through prefixed commands, including
display, add, play, remove, and clear actions. Shows command hints plus recent
played history and validates request arguments before mutating data.
#>
function Start-BookmarksMenu {
	while ($true) {
		$prefix = Get-CommandPrefix
		Clear-Host
		Show-YouCliBanner
		Write-Host "Bookmarks" -ForegroundColor Red
		if (-not $script:Bookmarks -or $script:Bookmarks.Count -eq 0) {
			Write-Host ("No bookmarks saved. Use {0}back to return to Main Menu." -f $prefix) -ForegroundColor Yellow
			Write-Host
		} else {
			Show-VideoList -VideoList $script:Bookmarks -Heading "Bookmarks"
		}

		Write-Host ("prefix: {0}" -f $prefix) -ForegroundColor DarkGray
		Write-Host "add back clear display play remove" -ForegroundColor DarkGray
		Write-Host "i.e. [prefix]play [number]" -ForegroundColor DarkGray
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
			Write-Host ("Invalid request. Use: {0}add, {0}play N, {0}remove N, {0}clear, {0}display, {0}back" -f $prefix) -ForegroundColor Yellow
			Start-Sleep -Milliseconds 900
			continue
		}

		$resolveIndex = {
			param([string]$rawIndex)
			[int]$index = 0
			if (-not [int]::TryParse($rawIndex, [ref]$index) -or $index -lt 1 -or $index -gt $script:Bookmarks.Count) {
				Write-Host "Invalid selection index." -ForegroundColor Yellow
				return $null
			}
			return $index
		}

		switch ($requestCommand) {
			"-display" { }
			"-add" {
				$title = Read-Host "Bookmark title"
				$url = Read-Host "Bookmark URL"
				if ([string]::IsNullOrWhiteSpace($title) -or [string]::IsNullOrWhiteSpace($url)) {
					Write-Host "Title and URL are required." -ForegroundColor Yellow
					Start-Sleep -Milliseconds 900
					continue
				}

				$script:Bookmarks += [PSCustomObject]@{
					Title = $title.Trim()
					Url = $url.Trim()
				}
				Save-Bookmarks
			}
			"-play" {
				if (-not $script:Bookmarks -or $script:Bookmarks.Count -eq 0) {
					Write-Host ("No bookmarks saved. Use {0}back to return to Main Menu." -f $prefix) -ForegroundColor Yellow
					Start-Sleep -Milliseconds 900
					continue
				}

				$index = & $resolveIndex $requestArg
				if ($null -eq $index) {
					Start-Sleep -Milliseconds 900
					continue
				}

				$selected = $script:Bookmarks[$index - 1]
				Play-VideoObject -Video $selected
			}
			"-remove" {
				if (-not $script:Bookmarks -or $script:Bookmarks.Count -eq 0) {
					Write-Host ("No bookmarks saved. Use {0}back to return to Main Menu." -f $prefix) -ForegroundColor Yellow
					Start-Sleep -Milliseconds 900
					continue
				}

				$index = & $resolveIndex $requestArg
				if ($null -eq $index) {
					Start-Sleep -Milliseconds 900
					continue
				}

				$newBookmarks = @()
				for ($i = 0; $i -lt $script:Bookmarks.Count; $i++) {
					if ($i -ne ($index - 1)) {
						$newBookmarks += $script:Bookmarks[$i]
					}
				}
				$script:Bookmarks = $newBookmarks
				Save-Bookmarks
				Write-Host "Bookmark removed permanently." -ForegroundColor Green
				Start-Sleep -Milliseconds 700
			}
			"-clear" {
				$confirm = Read-Host "Clear all bookmarks? (y/n)"
				if ($confirm.Trim().ToLower() -eq "y") {
					$script:Bookmarks = @()
					Save-Bookmarks
					Write-Host "All bookmarks removed permanently." -ForegroundColor Green
					Start-Sleep -Milliseconds 700
				}
			}
			"-back" { return }
			default {
				Write-Host ("Invalid request. Use: {0}add, {0}play N, {0}remove N, {0}clear, {0}display, {0}back" -f $prefix) -ForegroundColor Yellow
				Start-Sleep -Milliseconds 900
			}
		}
	}
}
