$ErrorActionPreference = "Stop"

$packages = Get-Content "./packages/winget.txt"

foreach ($pkg in $packages) {
    Write-Host "Installing $pkg..."
    $output = winget install --id $pkg -e --silent --source winget --accept-source-agreements --accept-package-agreements 2>&1 | Out-String
    $exitCode = $LASTEXITCODE

    if ($exitCode -ne 0) {
        $isNoOp = (
            $output -match "No available upgrade found" -or
            $output -match "No newer package versions are available" -or
            $output -match "Found an existing package already installed"
        )

        if ($isNoOp) {
            Write-Host "$pkg already up to date."
            continue
        }

        throw "winget install failed for $pkg with exit code $exitCode`n$output"
    }
}
