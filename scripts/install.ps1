$ErrorActionPreference = "Stop"

$currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)
$isElevated = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$installScriptsRoot = Join-Path $repoRoot "installation-scripts"

if (-not $isElevated) {
    Write-Error "This installer requires elevated permissions. Re-run PowerShell as Administrator."
    exit 1
}

Push-Location $repoRoot
try {
    Write-Host "Enabling Windows long paths..."
    & (Join-Path $installScriptsRoot "enable-longpaths.ps1")

    Write-Host "Installing packages..."
    & (Join-Path $installScriptsRoot "install-winget.ps1")


    Write-Host "Ensuring Meslo font is installed..."
    oh-my-posh font install meslo
    if ($LASTEXITCODE -ne 0) {
        throw "oh-my-posh font install meslo failed with exit code $LASTEXITCODE"
    }

    Write-Host "Installing vscode extensions..."
    & (Join-Path $installScriptsRoot "install-vscode.ps1")

    Write-Host "Installing configs..."
    & (Join-Path $installScriptsRoot "install-configs.ps1")

    Write-Host "Setup complete."
}
finally {
    Pop-Location
}
