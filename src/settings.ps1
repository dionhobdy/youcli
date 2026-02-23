<#
Settings module for YouCLI.
This file is dot-sourced by the main script.
#>

<#
.SYNOPSIS
Runs the interactive settings menu.

.DESCRIPTION
Allows users to manage settings through prefixed commands, including toggling
search mode and updating max results. Displays command hints plus recent played
history and keeps interaction on a single Input Request prompt.
#>
function Start-SettingsMenu {
	while ($true) {
		$prefix = Get-CommandPrefix
		Clear-Host
		Show-YouCliBanner
		Write-Host "Settings" -ForegroundColor Red
		Write-Host "Search Mode: $($script:Settings.SearchSource)"
		Write-Host "Max Results: $($script:Settings.MaxResults)"
		Write-Host "Prefix: $($script:Settings.CommandPrefix)"
		Write-Host

		Write-Host ("prefix: {0}" -f $prefix) -ForegroundColor DarkGray
		Write-Host "back max mode prefix" -ForegroundColor DarkGray
		Write-Host "i.e. [prefix]max [number]" -ForegroundColor DarkGray
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
			Write-Host ("Invalid request. Use {0}mode, {0}max N, {0}prefix <value>, {0}back" -f $prefix) -ForegroundColor Yellow
			Start-Sleep -Milliseconds 900
			continue
		}

		switch ($requestCommand) {
			"-mode" {
				if ($script:Settings.SearchSource -eq "ytsearch") {
					$script:Settings.SearchSource = "ytsearchdate"
				} else {
					$script:Settings.SearchSource = "ytsearch"
				}
				Save-Settings
			}
			"-max" {
				[int]$parsed = 0
				if ([int]::TryParse($requestArg, [ref]$parsed) -and $parsed -ge 1 -and $parsed -le 25) {
					$script:Settings.MaxResults = $parsed
					Save-Settings
				} else {
					Write-Host ("Invalid value. Use {0}max 1..25" -f $prefix) -ForegroundColor Yellow
					Start-Sleep -Milliseconds 900
				}
			}
			"-prefix" {
				$newPrefix = $requestArg
				if ([string]::IsNullOrWhiteSpace($newPrefix) -or ($newPrefix -match '\s')) {
					Write-Host ("Invalid value. Use {0}prefix <non-space text>" -f $prefix) -ForegroundColor Yellow
					Start-Sleep -Milliseconds 900
					continue
				}

				$script:Settings.CommandPrefix = $newPrefix
				Save-Settings
			}
			"-back" { return }
			default {
				Write-Host ("Invalid request. Use {0}mode, {0}max N, {0}prefix <value>, {0}back" -f $prefix) -ForegroundColor Yellow
				Start-Sleep -Milliseconds 900
			}
		}
	}
}
