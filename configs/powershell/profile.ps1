# Load Oh My Posh in both Windows PowerShell and PowerShell 7
$ompShell = if ($PSVersionTable.PSEdition -eq "Desktop") { "powershell" } else { "pwsh" }
oh-my-posh init $ompShell --config "$env:POSH_THEMES_PATH/paradox.omp.json" | Invoke-Expression

# Useful aliases
Set-Alias ll Get-ChildItem
Set-Alias g git

# Enable terminal icons when available
if (Get-Module -ListAvailable -Name Terminal-Icons) {
    Import-Module Terminal-Icons
}
