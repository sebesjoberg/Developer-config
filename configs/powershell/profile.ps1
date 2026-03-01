# Load Oh My Posh
oh-my-posh init pwsh --config "$env:POSH_THEMES_PATH/paradox.omp.json" | Invoke-Expression

# Useful aliases
Set-Alias ll Get-ChildItem
Set-Alias g git

# Enable terminal icons
Import-Module Terminal-Icons