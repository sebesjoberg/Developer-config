$links = @{
  "$HOME\.gitconfig" = "configs/git/.gitconfig"
  "$env:SystemDrive\config.omp.json" = "configs/powershell/config.omp.json"
  "$HOME\Documents\PowerShell\Microsoft.PowerShell_profile.ps1" = "configs/powershell/profile.ps1"
  "$HOME\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1" = "configs/powershell/profile.ps1"
  "$env:APPDATA\Code\User\settings.json" = "configs/vscode/settings.json"
  "$env:APPDATA\Code\User\keybindings.json" = "configs/vscode/keybindings.json"
  "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json" = "configs/windows-terminal/settings.json"
}

foreach ($target in $links.Keys) {
    $source = Join-Path $PWD $links[$target]
    $parent = Split-Path -Parent $target
    if (-not (Test-Path $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    Write-Host "Linking $target -> $source"
    New-Item -ItemType SymbolicLink -Path $target -Target $source -Force
}
