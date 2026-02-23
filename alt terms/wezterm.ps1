$youCliScriptPath = Join-Path (Split-Path -Parent $PSScriptRoot) "youcli.ps1"
$youCliDirectory = Split-Path -Parent $youCliScriptPath

if (-not (Test-Path $youCliScriptPath)) {
    Write-Host "YouCLI script not found at: $youCliScriptPath" -ForegroundColor Red
    exit 1
}

$wezterm = Get-Command wezterm -ErrorAction SilentlyContinue
if (-not $wezterm) {
    Write-Host "WezTerm is not installed or not in PATH." -ForegroundColor Red
    Write-Host "Install WezTerm first, then try again." -ForegroundColor Yellow
    exit 1
}

$powerShellCommand = $null
$pwsh = Get-Command pwsh -ErrorAction SilentlyContinue
if ($pwsh) {
    $powerShellCommand = $pwsh.Source
} else {
    $windowsPowerShell = Get-Command powershell.exe -ErrorAction SilentlyContinue
    if ($windowsPowerShell) {
        $powerShellCommand = $windowsPowerShell.Source
    }
}

if (-not $powerShellCommand) {
    Write-Host "No PowerShell executable found (pwsh or powershell.exe)." -ForegroundColor Red
    exit 1
}

$escapedDirectory = $youCliDirectory.Replace("'", "''")
$escapedScript = $youCliScriptPath.Replace("'", "''")
$bootstrapCommand = "Set-Location -LiteralPath '$escapedDirectory'; & '$escapedScript'"

Start-Process -FilePath $wezterm.Source -ArgumentList @(
    "start",
    "--cwd", $youCliDirectory,
    "--",
    $powerShellCommand,
    "-NoLogo",
    "-NoExit",
    "-ExecutionPolicy", "Bypass",
    "-Command", $bootstrapCommand
) | Out-Null
