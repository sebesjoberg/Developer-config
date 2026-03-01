Write-Host "Installing packages..."
.\scripts\install-winget.ps1

Write-Host "Installing configs..."
.\scripts\install-configs.ps1

Write-Host "Installing vscode extensions..."
.\scripts\install-vscode-extensions.ps1

Write-Host "Setup complete."