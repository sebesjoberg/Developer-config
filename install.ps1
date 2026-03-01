 $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
 $principal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)
 $isElevated = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isElevated) {
    Write-Error "This installer requires elevated permissions. Re-run PowerShell as Administrator."
    exit 1
}

Write-Host "Enabling Windows long paths..."
.\scripts\enable-longpaths.ps1

Write-Host "Installing packages..."
.\scripts\install-winget.ps1

Write-Host "Installing vscode extensions..."
.\scripts\install-vscode.ps1

Write-Host "Installing configs..."
.\scripts\install-configs.ps1

Write-Host "Setup complete."
