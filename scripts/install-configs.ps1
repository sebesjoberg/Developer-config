$links = @{
  "$HOME\.gitconfig" = "configs/git/.gitconfig"
  "$HOME\Documents\PowerShell\Microsoft.PowerShell_profile.ps1" = "configs/powershell/profile.ps1"
  "$env:APPDATA\Code\User\settings.json" = "configs/vscode/settings.json"
  "$env:APPDATA\Code\User\keybindings.json" = "configs/vscode/keybindings.json"
}

foreach ($target in $links.Keys) {
    $source = Join-Path $PWD $links[$target]
    Write-Host "Linking $target -> $source"
    New-Item -ItemType SymbolicLink -Path $target -Target $source -Force
}