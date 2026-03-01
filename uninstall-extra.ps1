param(
    [string]$WingetFile = "./packages/winget.txt",
    [string]$VscodeFile = "./packages/vscode.txt"
)

$ErrorActionPreference = "Stop"

function Prompt-YesNoDefaultNo {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    while ($true) {
        $answer = Read-Host "$Message (Y/y/Yes/yes, N/n/No/no, Enter=No)"
        if ([string]::IsNullOrWhiteSpace($answer)) {
            return $false
        }

        switch ($answer.Trim().ToLowerInvariant()) {
            "y" { return $true }
            "yes" { return $true }
            "n" { return $false }
            "no" { return $false }
            default { Write-Host "Please answer y or n." }
        }
    }
}

function Read-ListFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return @()
    }

    return @(
        Get-Content -LiteralPath $Path |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ -and -not $_.StartsWith("#") }
    )
}

function Get-InstalledWingetPackageIds {
    $tempJson = [System.IO.Path]::Combine(
        [System.IO.Path]::GetTempPath(),
        "winget-export-$([guid]::NewGuid().ToString('N')).json"
    )

    try {
        $wingetOutput = winget export --output $tempJson --accept-source-agreements 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to query winget packages.`n$wingetOutput"
        }

        if (-not (Test-Path -LiteralPath $tempJson)) {
            throw "winget export did not produce output at $tempJson"
        }

        $exportData = Get-Content -LiteralPath $tempJson -Raw | ConvertFrom-Json
        $ids = @()
        foreach ($source in @($exportData.Sources)) {
            foreach ($pkg in @($source.Packages)) {
                if ($pkg.PackageIdentifier) {
                    $ids += $pkg.PackageIdentifier
                }
            }
        }

        return @($ids | Sort-Object -Unique)
    }
    finally {
        if (Test-Path -LiteralPath $tempJson) {
            Remove-Item -LiteralPath $tempJson -Force
        }
    }
}

function Get-InstalledVscodeExtensionIds {
    $vscodeOutput = code --list-extensions 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to query VS Code extensions.`n$vscodeOutput"
    }

    return @(
        $vscodeOutput -split "`r?`n" |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ } |
        Sort-Object -Unique
    )
}

function Uninstall-WingetPackage {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Id
    )

    Write-Host "Uninstalling winget package: $Id"
    $output = winget uninstall --id $Id -e --accept-source-agreements 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Failed to uninstall $Id"
        Write-Host $output
        return $false
    }

    Write-Host "Uninstalled: $Id"
    return $true
}

function Uninstall-VscodeExtension {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Id
    )

    Write-Host "Uninstalling VS Code extension: $Id"
    $output = code --uninstall-extension $Id 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Failed to uninstall $Id"
        Write-Host $output
        return $false
    }

    Write-Host "Uninstalled: $Id"
    return $true
}

if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    throw "winget is not available in PATH."
}

if (-not (Get-Command code -ErrorAction SilentlyContinue)) {
    throw "VS Code CLI (code) is not available in PATH."
}

$wingetSpec = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
foreach ($id in (Read-ListFile -Path $WingetFile)) {
    [void]$wingetSpec.Add($id)
}

$vscodeSpec = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
foreach ($id in (Read-ListFile -Path $VscodeFile)) {
    [void]$vscodeSpec.Add($id)
}

$installedWinget = Get-InstalledWingetPackageIds
$installedVscode = Get-InstalledVscodeExtensionIds

$extraWinget = @($installedWinget | Where-Object { -not $wingetSpec.Contains($_) } | Sort-Object)
$extraVscode = @($installedVscode | Where-Object { -not $vscodeSpec.Contains($_) } | Sort-Object)

Write-Host ""
Write-Host "=== Extra winget packages (installed but not in $WingetFile) ==="
$wingetUninstalled = 0
$wingetSkipped = 0
$wingetFailed = 0
if ($extraWinget.Count -eq 0) {
    Write-Host "None"
} else {
    foreach ($id in $extraWinget) {
        if (Prompt-YesNoDefaultNo -Message "Uninstall `"$id`"") {
            if (Uninstall-WingetPackage -Id $id) {
                $wingetUninstalled++
            }
            else {
                $wingetFailed++
            }
        }
        else {
            $wingetSkipped++
        }
    }
}

Write-Host ""
Write-Host "=== Extra VS Code extensions (installed but not in $VscodeFile) ==="
$vscodeUninstalled = 0
$vscodeSkipped = 0
$vscodeFailed = 0
if ($extraVscode.Count -eq 0) {
    Write-Host "None"
} else {
    foreach ($id in $extraVscode) {
        if (Prompt-YesNoDefaultNo -Message "Uninstall `"$id`"") {
            if (Uninstall-VscodeExtension -Id $id) {
                $vscodeUninstalled++
            }
            else {
                $vscodeFailed++
            }
        }
        else {
            $vscodeSkipped++
        }
    }
}

Write-Host ""
Write-Host "Done."
Write-Host ""
Write-Host "=== Uninstall Summary ==="
Write-Host "Winget: detected-extra $($extraWinget.Count), uninstalled $wingetUninstalled, skipped $wingetSkipped, failed $wingetFailed"
Write-Host "VS Code: detected-extra $($extraVscode.Count), uninstalled $vscodeUninstalled, skipped $vscodeSkipped, failed $vscodeFailed"
