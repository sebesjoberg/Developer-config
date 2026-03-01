# Useful aliases
Set-Alias ll Get-ChildItem
Set-Alias g git

# Enable terminal icons when available
if (Get-Module -ListAvailable -Name Terminal-Icons) {
    Import-Module Terminal-Icons
}

$ompConfig = "C:\config.omp.json"

Invoke-Expression (& oh-my-posh init pwsh --config $ompConfig)
