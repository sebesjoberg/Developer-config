$packages = Get-Content "./packages/winget.txt"

foreach ($pkg in $packages) {
    winget install --id $pkg -e --silent
}