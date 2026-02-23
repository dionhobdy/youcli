<#
Settings module for YouCLI.
This file is dot-sourced by the main script.
#>

<#
.SYNOPSIS
Runs the interactive settings menu.

.DESCRIPTION
Allows users to toggle search mode and configure maximum results, validates
input ranges, persists updates to disk, and returns control to the main menu
when requested.
#>
function Start-SettingsMenu {
	while ($true) {
		Write-Host "=== Settings ===" -ForegroundColor Cyan
		Write-Host "[1] Search Mode: $($script:Settings.SearchSource)"
		Write-Host "[2] Max Results: $($script:Settings.MaxResults)"
		Write-Host "[3] Back to Main Menu"
		Write-Host

		$choice = Read-Host "Choose a setting option"
		switch ($choice.Trim()) {
			"1" {
				if ($script:Settings.SearchSource -eq "ytsearch") {
					$script:Settings.SearchSource = "ytsearchdate"
				} else {
					$script:Settings.SearchSource = "ytsearch"
				}
				Save-Settings
				Write-Host
			}
			"2" {
				$value = Read-Host "Enter max results (1-25)"
				[int]$parsed = 0
				if ([int]::TryParse($value, [ref]$parsed) -and $parsed -ge 1 -and $parsed -le 25) {
					$script:Settings.MaxResults = $parsed
					Save-Settings
				} else {
					Write-Host "Invalid value." -ForegroundColor Yellow
				}
				Write-Host
			}
			"3" { return }
			default {
				Write-Host "Invalid option." -ForegroundColor Yellow
				Write-Host
			}
		}
	}
}
