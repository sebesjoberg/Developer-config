$links = @{
  "$HOME\.gitconfig" = "configs/git/.gitconfig"
  "$HOME\Documents\PowerShell\Microsoft.PowerShell_profile.ps1" = "configs/powershell/profile.ps1"
  "$HOME\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1" = "configs/powershell/profile.ps1"
  "$env:APPDATA\Code\User\settings.json" = "configs/vscode/settings.json"
  "$env:APPDATA\Code\User\keybindings.json" = "configs/vscode/keybindings.json"
  "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json" = "configs/windows-terminal/settings.json"
}

$allUsersProfiles = @(
    "$env:WINDIR\System32\WindowsPowerShell\v1.0\profile.ps1",
    "$env:WINDIR\System32\WindowsPowerShell\v1.0\Microsoft.PowerShell_profile.ps1",
    "$env:ProgramFiles\PowerShell\7\profile.ps1",
    "$env:ProgramFiles\PowerShell\7\Microsoft.PowerShell_profile.ps1"
)

foreach ($allUsersProfile in $allUsersProfiles) {
    $parent = Split-Path -Parent $allUsersProfile
    if (Test-Path $parent) {
        $links[$allUsersProfile] = "configs/powershell/profile.ps1"
    }
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
