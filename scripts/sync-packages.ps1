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

function Save-ListFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [string[]]$Entries
    )

    $sorted = @($Entries | Sort-Object -Unique)
    Set-Content -LiteralPath $Path -Value $sorted
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

function Sync-ListFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Label,
        [Parameter(Mandatory = $true)]
        [string]$FilePath,
        [Parameter(Mandatory = $true)]
        [string[]]$InstalledEntries
    )

    Write-Host ""
    Write-Host "=== Syncing $Label ($FilePath) ==="

    $fileEntries = Read-ListFile -Path $FilePath
    $current = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($entry in $fileEntries) {
        [void]$current.Add($entry)
    }

    $installed = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($entry in $InstalledEntries) {
        [void]$installed.Add($entry)
    }

    $added = 0
    $keptMissingFromFile = 0
    $removed = 0
    $keptMissingFromComputer = 0

    $missingFromFile = @($installed.Where({ -not $current.Contains($_) }) | Sort-Object)
    foreach ($entry in $missingFromFile) {
        if (Prompt-YesNoDefaultNo -Message "Add `"$entry`" to spec file") {
            [void]$current.Add($entry)
            $added++
        }
        else {
            $keptMissingFromFile++
        }
    }

    $missingFromComputer = @($current.Where({ -not $installed.Contains($_) }) | Sort-Object)
    foreach ($entry in $missingFromComputer) {
        if (Prompt-YesNoDefaultNo -Message "Remove `"$entry`" from spec file") {
            [void]$current.Remove($entry)
            $removed++
        }
        else {
            $keptMissingFromComputer++
        }
    }

    Save-ListFile -Path $FilePath -Entries @($current)
    Write-Host "Saved $FilePath"

    return [pscustomobject]@{
        Label                    = $Label
        AddedToSpec              = $added
        RemovedFromSpec          = $removed
        KeptOutOfSpec            = $keptMissingFromFile
        KeptInSpecNotInstalled   = $keptMissingFromComputer
        InstalledCount           = $installed.Count
        FinalSpecCount           = $current.Count
    }
}

if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    throw "winget is not available in PATH."
}

if (-not (Get-Command code -ErrorAction SilentlyContinue)) {
    throw "VS Code CLI (code) is not available in PATH."
}

if (-not (Test-Path -LiteralPath $WingetFile)) {
    Write-Host "$WingetFile does not exist yet. It will be created."
}

if (-not (Test-Path -LiteralPath $VscodeFile)) {
    Write-Host "$VscodeFile does not exist yet. It will be created."
}

$installedWinget = Get-InstalledWingetPackageIds
$installedVscode = Get-InstalledVscodeExtensionIds

$wingetSummary = Sync-ListFile -Label "winget packages" -FilePath $WingetFile -InstalledEntries $installedWinget
$vscodeSummary = Sync-ListFile -Label "VS Code extensions" -FilePath $VscodeFile -InstalledEntries $installedVscode

Write-Host ""
Write-Host "Sync complete."
Write-Host ""
Write-Host "=== Sync Summary ==="
Write-Host "Winget: added $($wingetSummary.AddedToSpec), removed $($wingetSummary.RemovedFromSpec), skipped-add $($wingetSummary.KeptOutOfSpec), skipped-remove $($wingetSummary.KeptInSpecNotInstalled), installed $($wingetSummary.InstalledCount), final-spec $($wingetSummary.FinalSpecCount)"
Write-Host "VS Code: added $($vscodeSummary.AddedToSpec), removed $($vscodeSummary.RemovedFromSpec), skipped-add $($vscodeSummary.KeptOutOfSpec), skipped-remove $($vscodeSummary.KeptInSpecNotInstalled), installed $($vscodeSummary.InstalledCount), final-spec $($vscodeSummary.FinalSpecCount)"
