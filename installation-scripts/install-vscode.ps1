$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$packagesFile = Join-Path $repoRoot "packages/vscode.txt"

Get-Content $packagesFile | ForEach-Object {
    code --install-extension $_ --force
}
