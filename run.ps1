[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingWriteHost", "", Justification = "Interactive TUI script relies on host rendering.")]
[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseApprovedVerbs", "", Justification = "Function names prioritize local readability in this script.")]
[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseSingularNouns", "", Justification = "Some helper names intentionally use plural nouns for list builders.")]
[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseShouldProcessForStateChangingFunctions", "", Justification = "This script is an explicit interactive TUI and does not expose advanced function semantics.")]
param(
    [string]$WingetFile = "./packages/winget.txt",
    [string]$VscodeFile = "./packages/vscode.txt"
)

$ErrorActionPreference = "Stop"

function Test-IsElevated {
    $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Read-YesNoDefaultYes {
    param([string]$Message)
    while ($true) {
        $answer = Read-Host "$Message (Y/y/Yes/yes, N/n/No/no, Enter=Yes)"
        if ([string]::IsNullOrWhiteSpace($answer)) { return $true }
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
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return @() }
    return @(
        Get-Content -LiteralPath $Path |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ -and -not $_.StartsWith("#") } |
        Sort-Object -Unique
    )
}

function Save-ListFile {
    param([string]$Path, [string[]]$Entries)
    $sorted = @($Entries | Sort-Object -Unique)
    Set-Content -LiteralPath $Path -Value $sorted
}

function Get-InstalledWingetPackageIds {
    $tempJson = [System.IO.Path]::Combine(
        [System.IO.Path]::GetTempPath(),
        "winget-export-$([guid]::NewGuid().ToString('N')).json"
    )
    try {
        $output = winget export --output $tempJson --accept-source-agreements 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) { throw "Failed to query winget packages.`n$output" }
        $data = Get-Content -LiteralPath $tempJson -Raw | ConvertFrom-Json
        $ids = @()
        foreach ($source in @($data.Sources)) {
            foreach ($pkg in @($source.Packages)) {
                if ($pkg.PackageIdentifier) { $ids += $pkg.PackageIdentifier }
            }
        }
        return @($ids | Sort-Object -Unique)
    }
    finally {
        if (Test-Path -LiteralPath $tempJson) { Remove-Item -LiteralPath $tempJson -Force }
    }
}

function Get-InstalledVscodeExtensionIds {
    $output = code --list-extensions 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "Failed to query VS Code extensions.`n$output" }
    return @(
        $output -split "`r?`n" |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ } |
        Sort-Object -Unique
    )
}

function New-ChangeItem {
    param(
        [string]$Target,
        [string]$Action,
        [string]$Id
    )
    return [pscustomobject]@{
        Selected = $false
        Target   = $Target
        Action   = $Action
        Id       = $Id
    }
}

function Get-ListPageSize {
    $fallbackRows = 12
    try {
        $windowHeight = [System.Console]::WindowHeight
        $reservedLines = 10
        $rows = $windowHeight - $reservedLines
        return [Math]::Max(3, $rows)
    }
    catch {
        return $fallbackRows
    }
}

function Truncate-ConsoleLine {
    param(
        [string]$Text,
        [int]$MaxWidth
    )
    if ([string]::IsNullOrEmpty($Text)) { return "" }
    if ($MaxWidth -le 3) { return $Text.Substring(0, [Math]::Min($Text.Length, $MaxWidth)) }
    if ($Text.Length -le $MaxWidth) { return $Text }
    return $Text.Substring(0, $MaxWidth - 3) + "..."
}

function Show-Items {
    param(
        [string]$Title,
        [System.Collections.Generic.List[object]]$Items,
        [int]$CursorIndex,
        [int]$PageIndex,
        [int]$PageSize,
        [bool]$ShowHelp
    )
    Clear-Host
    Write-Host $Title
    Write-Host ("-" * $Title.Length)
    Write-Host ""

    $maxWidth = 120
    try {
        $maxWidth = [Math]::Max(20, [System.Console]::WindowWidth - 1)
    }
    catch {
        $maxWidth = 120
    }

    if ($Items.Count -eq 0) {
        Write-Host "No items."
    } else {
        if ($PageSize -lt 1) { $PageSize = 1 }
        $totalPages = [Math]::Max(1, [int][Math]::Ceiling($Items.Count / [double]$PageSize))
        $safePageIndex = [Math]::Min([Math]::Max(0, $PageIndex), $totalPages - 1)
        $startIndex = $safePageIndex * $PageSize
        $endExclusive = [Math]::Min($Items.Count, $startIndex + $PageSize)

        $summaryLine = ("Page {0}/{1} | Showing {2}-{3} of {4}" -f ($safePageIndex + 1), $totalPages, ($startIndex + 1), $endExclusive, $Items.Count)
        Write-Host (Truncate-ConsoleLine -Text $summaryLine -MaxWidth $maxWidth)
        for ($i = $startIndex; $i -lt $endExclusive; $i++) {
            $it = $Items[$i]
            $mark = if ($it.Selected) { "x" } else { " " }
            $cursor = if ($i -eq $CursorIndex) { ">" } else { " " }
            $line = ("{0} {1,3}. [{2}] {3} | {4} | {5}" -f $cursor, ($i + 1), $mark, $it.Target, $it.Action, $it.Id)
            Write-Host (Truncate-ConsoleLine -Text $line -MaxWidth $maxWidth)
        }
    }
    Write-Host ""
    if ($ShowHelp) {
        $helpLines = @(
            "Keys:",
            "  Up/Down: Move cursor within page",
            "  Left/Right: Previous/next page",
            "  Space: Toggle current item",
            "  A: Select all",
            "  N: Select none",
            "  R: Refresh package lists",
            "  Enter: Apply selected",
            "  Esc: Back to main menu",
            "  ?: Hide help"
        )
        foreach ($helpLine in $helpLines) {
            Write-Host (Truncate-ConsoleLine -Text $helpLine -MaxWidth $maxWidth)
        }
    }
    else {
        $keysLine = "Esc cancel | Arrows move | Space select | ? keys"
        Write-Host (Truncate-ConsoleLine -Text $keysLine -MaxWidth $maxWidth)
    }
}

function Build-SyncItems {
    param(
        [string[]]$WingetInstalled,
        [string[]]$VscodeInstalled,
        [string[]]$WingetSpec,
        [string[]]$VscodeSpec
    )
    $items = [System.Collections.Generic.List[object]]::new()

    $wingetSpecSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $wingetSpec | ForEach-Object { [void]$wingetSpecSet.Add($_) }
    $wingetInstalledSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $WingetInstalled | ForEach-Object { [void]$wingetInstalledSet.Add($_) }

    foreach ($id in @($WingetInstalled | Where-Object { -not $wingetSpecSet.Contains($_) } | Sort-Object)) {
        $items.Add((New-ChangeItem -Target "winget" -Action "AddToSpec" -Id $id))
    }
    foreach ($id in @($WingetSpec | Where-Object { -not $wingetInstalledSet.Contains($_) } | Sort-Object)) {
        $items.Add((New-ChangeItem -Target "winget" -Action "RemoveFromSpec" -Id $id))
    }

    $vscodeSpecSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $VscodeSpec | ForEach-Object { [void]$vscodeSpecSet.Add($_) }
    $vscodeInstalledSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $VscodeInstalled | ForEach-Object { [void]$vscodeInstalledSet.Add($_) }

    foreach ($id in @($VscodeInstalled | Where-Object { -not $vscodeSpecSet.Contains($_) } | Sort-Object)) {
        $items.Add((New-ChangeItem -Target "vscode" -Action "AddToSpec" -Id $id))
    }
    foreach ($id in @($VscodeSpec | Where-Object { -not $vscodeInstalledSet.Contains($_) } | Sort-Object)) {
        $items.Add((New-ChangeItem -Target "vscode" -Action "RemoveFromSpec" -Id $id))
    }

    return $items
}

function Build-UninstallItems {
    param(
        [string[]]$WingetInstalled,
        [string[]]$VscodeInstalled,
        [string[]]$WingetSpec,
        [string[]]$VscodeSpec
    )
    $items = [System.Collections.Generic.List[object]]::new()

    $wingetSpecSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $wingetSpec | ForEach-Object { [void]$wingetSpecSet.Add($_) }
    foreach ($id in @($WingetInstalled | Where-Object { -not $wingetSpecSet.Contains($_) } | Sort-Object)) {
        $items.Add((New-ChangeItem -Target "winget" -Action "Uninstall" -Id $id))
    }

    $vscodeSpecSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $vscodeSpec | ForEach-Object { [void]$vscodeSpecSet.Add($_) }
    foreach ($id in @($VscodeInstalled | Where-Object { -not $vscodeSpecSet.Contains($_) } | Sort-Object)) {
        $items.Add((New-ChangeItem -Target "vscode" -Action "Uninstall" -Id $id))
    }

    return $items
}

function Build-UpdateItems {
    param(
        [string[]]$WingetInstalled,
        [string[]]$VscodeInstalled
    )
    $items = [System.Collections.Generic.List[object]]::new()

    foreach ($id in @($WingetInstalled | Sort-Object)) {
        $items.Add((New-ChangeItem -Target "winget" -Action "Update" -Id $id))
    }

    foreach ($id in @($VscodeInstalled | Sort-Object)) {
        $items.Add((New-ChangeItem -Target "vscode" -Action "Update" -Id $id))
    }

    return $items
}

function Invoke-SyncSelection {
    param(
        [System.Collections.Generic.List[object]]$Items,
        [string]$WingetFile,
        [string]$VscodeFile
    )
    $winget = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    Read-ListFile -Path $WingetFile | ForEach-Object { [void]$winget.Add($_) }
    $vscode = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    Read-ListFile -Path $VscodeFile | ForEach-Object { [void]$vscode.Add($_) }

    $summary = @{
        wingetAdd = 0; wingetRemove = 0
        vscodeAdd = 0; vscodeRemove = 0
    }

    foreach ($item in @($Items | Where-Object { $_.Selected })) {
        if ($item.Target -eq "winget") {
            if ($item.Action -eq "AddToSpec") {
                if ($winget.Add($item.Id)) { $summary.wingetAdd++ }
            } elseif ($item.Action -eq "RemoveFromSpec") {
                if ($winget.Remove($item.Id)) { $summary.wingetRemove++ }
            }
        } elseif ($item.Target -eq "vscode") {
            if ($item.Action -eq "AddToSpec") {
                if ($vscode.Add($item.Id)) { $summary.vscodeAdd++ }
            } elseif ($item.Action -eq "RemoveFromSpec") {
                if ($vscode.Remove($item.Id)) { $summary.vscodeRemove++ }
            }
        }
    }

    Save-ListFile -Path $WingetFile -Entries @($winget)
    Save-ListFile -Path $VscodeFile -Entries @($vscode)

    Write-Host ""
    Write-Host "Sync apply complete."
    Write-Host "Winget: added $($summary.wingetAdd), removed $($summary.wingetRemove)"
    Write-Host "VS Code: added $($summary.vscodeAdd), removed $($summary.vscodeRemove)"
}

function Invoke-UninstallSelection {
    param([System.Collections.Generic.List[object]]$Items)
    $summary = @{
        wingetUninstall = 0; wingetFail = 0
        vscodeUninstall = 0; vscodeFail = 0
    }

    foreach ($item in @($Items | Where-Object { $_.Selected })) {
        if ($item.Target -eq "winget") {
            $output = winget uninstall --id $item.Id -e --accept-source-agreements 2>&1 | Out-String
            if ($LASTEXITCODE -eq 0) {
                $summary.wingetUninstall++
            } else {
                $summary.wingetFail++
                Write-Host "Failed to uninstall winget: $($item.Id)"
                Write-Host $output
            }
        } elseif ($item.Target -eq "vscode") {
            $output = code --uninstall-extension $item.Id 2>&1 | Out-String
            if ($LASTEXITCODE -eq 0) {
                $summary.vscodeUninstall++
            } else {
                $summary.vscodeFail++
                Write-Host "Failed to uninstall extension: $($item.Id)"
                Write-Host $output
            }
        }
    }

    Write-Host ""
    Write-Host "Uninstall apply complete."
    Write-Host "Winget: uninstalled $($summary.wingetUninstall), failed $($summary.wingetFail)"
    Write-Host "VS Code: uninstalled $($summary.vscodeUninstall), failed $($summary.vscodeFail)"
}

function Invoke-UpdateSelection {
    param([System.Collections.Generic.List[object]]$Items)
    $summary = @{
        wingetUpdated = 0; wingetNoUpdate = 0; wingetFail = 0
        vscodeUpdated = 0; vscodeFail = 0
    }

    foreach ($item in @($Items | Where-Object { $_.Selected })) {
        if ($item.Target -eq "winget") {
            $output = winget upgrade --id $item.Id -e --silent --source winget --accept-source-agreements --accept-package-agreements 2>&1 | Out-String
            if ($LASTEXITCODE -eq 0) {
                $summary.wingetUpdated++
            }
            else {
                $isNoOp = (
                    $output -match "No available upgrade found" -or
                    $output -match "No newer package versions are available" -or
                    $output -match "No applicable upgrade found"
                )
                if ($isNoOp) {
                    $summary.wingetNoUpdate++
                }
                else {
                    $summary.wingetFail++
                    Write-Host "Failed to update winget package: $($item.Id)"
                    Write-Host $output
                }
            }
        }
        elseif ($item.Target -eq "vscode") {
            $output = code --install-extension $item.Id --force 2>&1 | Out-String
            if ($LASTEXITCODE -eq 0) {
                $summary.vscodeUpdated++
            }
            else {
                $summary.vscodeFail++
                Write-Host "Failed to update VS Code extension: $($item.Id)"
                Write-Host $output
            }
        }
    }

    Write-Host ""
    Write-Host "Update apply complete."
    Write-Host "Winget: updated $($summary.wingetUpdated), no-update $($summary.wingetNoUpdate), failed $($summary.wingetFail)"
    Write-Host "VS Code: updated $($summary.vscodeUpdated), failed $($summary.vscodeFail)"
}

function Show-Loading {
    param([string]$Message = "Loading...")
    Clear-Host
    Write-Host $Message
    Write-Host "Please wait..."
}

if (-not (Test-Path -LiteralPath $WingetFile)) { Set-Content -LiteralPath $WingetFile -Value @() }
if (-not (Test-Path -LiteralPath $VscodeFile)) { Set-Content -LiteralPath $VscodeFile -Value @() }

while ($true) {
    $mainOptions = @(
        "Sync spec files (add/remove entries)",
        "Uninstall extras (installed but not in spec)",
        "Install to specification",
        "Update packages and extensions",
        "Exit"
    )
    $mainCursor = 0
    while ($true) {
        Clear-Host
        Write-Host "Package TUI"
        Write-Host "-----------"
        Write-Host ""
        for ($i = 0; $i -lt $mainOptions.Count; $i++) {
            $cursor = if ($i -eq $mainCursor) { ">" } else { " " }
            Write-Host ("{0} {1}. {2}" -f $cursor, ($i + 1), $mainOptions[$i])
        }
        Write-Host ""
        Write-Host "Use Up/Down + Enter (or press 1-5, Esc=Exit)."

        $key = [System.Console]::ReadKey($true)
        if ($key.Key -eq [ConsoleKey]::UpArrow) {
            $mainCursor = [Math]::Max(0, $mainCursor - 1)
            continue
        }
        if ($key.Key -eq [ConsoleKey]::DownArrow) {
            $mainCursor = [Math]::Min($mainOptions.Count - 1, $mainCursor + 1)
            continue
        }
        if ($key.Key -eq [ConsoleKey]::Escape) { $mainCursor = 4; break }
        if ($key.Key -eq [ConsoleKey]::D1 -or $key.Key -eq [ConsoleKey]::NumPad1) { $mainCursor = 0; break }
        if ($key.Key -eq [ConsoleKey]::D2 -or $key.Key -eq [ConsoleKey]::NumPad2) { $mainCursor = 1; break }
        if ($key.Key -eq [ConsoleKey]::D3 -or $key.Key -eq [ConsoleKey]::NumPad3) { $mainCursor = 2; break }
        if ($key.Key -eq [ConsoleKey]::D4 -or $key.Key -eq [ConsoleKey]::NumPad4) { $mainCursor = 3; break }
        if ($key.Key -eq [ConsoleKey]::D5 -or $key.Key -eq [ConsoleKey]::NumPad5) { $mainCursor = 4; break }
        if ($key.Key -eq [ConsoleKey]::Enter) { break }
    }
    $main = [string]($mainCursor + 1)

    if ($main -eq "5") { break }
    if ($main -eq "3") {
        Clear-Host
        Write-Host "Install to specification selected."
        try {
            if (Test-IsElevated) {
                & ".\scripts\install.ps1"
            }
            else {
                $repoPath = (Get-Location).Path
                $cmd = "Set-Location -LiteralPath '$repoPath'; & '.\scripts\install.ps1'"
                Start-Process -FilePath "powershell.exe" -Verb RunAs -ArgumentList @("-NoExit", "-ExecutionPolicy", "Bypass", "-Command", $cmd) | Out-Null
                Write-Host "Started elevated PowerShell for installation."
            }
        }
        catch {
            Write-Host "scripts/install.ps1 failed:"
            Write-Host $_
        }
        Write-Host ""
        [void](Read-Host "Press Enter to continue")
        continue
    }
    if ($main -ne "1" -and $main -ne "2" -and $main -ne "4") { continue }

    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Host "winget is not available in PATH."
        [void](Read-Host "Press Enter to continue")
        continue
    }
    if (-not (Get-Command code -ErrorAction SilentlyContinue)) {
        Write-Host "VS Code CLI (code) is not available in PATH."
        [void](Read-Host "Press Enter to continue")
        continue
    }

    if ($main -eq "4") {
        Show-Loading -Message "Loading installed packages and extensions for updates..."
    }
    else {
        Show-Loading -Message "Loading installed packages and extensions..."
    }
    $wingetInstalled = Get-InstalledWingetPackageIds
    $vscodeInstalled = Get-InstalledVscodeExtensionIds
    $wingetSpec = Read-ListFile -Path $WingetFile
    $vscodeSpec = Read-ListFile -Path $VscodeFile

    $items = if ($main -eq "1") {
        Build-SyncItems -WingetInstalled $wingetInstalled -VscodeInstalled $vscodeInstalled -WingetSpec $wingetSpec -VscodeSpec $vscodeSpec
    } elseif ($main -eq "2") {
        Build-UninstallItems -WingetInstalled $wingetInstalled -VscodeInstalled $vscodeInstalled -WingetSpec $wingetSpec -VscodeSpec $vscodeSpec
    } else {
        Build-UpdateItems -WingetInstalled $wingetInstalled -VscodeInstalled $vscodeInstalled
    }

    while ($true) {
        $title = if ($main -eq "1") {
            "Sync Mode (default selection: none)"
        } elseif ($main -eq "2") {
            "Uninstall Mode (default selection: none)"
        } else {
            "Update Mode (default selection: none)"
        }
        $cursorIndex = 0
        $pageIndex = 0
        $showKeysHelp = $false
        while ($true) {
            $pageSize = Get-ListPageSize
            $totalPages = 1
            $pageStart = 0
            $pageEnd = -1
            if ($items.Count -eq 0) {
                $cursorIndex = 0
                $pageIndex = 0
            }
            else {
                if ($cursorIndex -ge $items.Count) { $cursorIndex = $items.Count - 1 }
                elseif ($cursorIndex -lt 0) { $cursorIndex = 0 }

                $totalPages = [Math]::Max(1, [int][Math]::Ceiling($items.Count / [double]$pageSize))
                if ($pageIndex -ge $totalPages) { $pageIndex = $totalPages - 1 }
                elseif ($pageIndex -lt 0) { $pageIndex = 0 }

                $pageStart = $pageIndex * $pageSize
                $pageEnd = [Math]::Min($items.Count - 1, $pageStart + $pageSize - 1)

                if ($cursorIndex -lt $pageStart -or $cursorIndex -gt $pageEnd) {
                    $cursorIndex = $pageStart
                }
            }

            Show-Items -Title $title -Items $items -CursorIndex $cursorIndex -PageIndex $pageIndex -PageSize $pageSize -ShowHelp $showKeysHelp
            $key = [System.Console]::ReadKey($true)

            if ($key.KeyChar -eq '?') {
                $showKeysHelp = -not $showKeysHelp
                continue
            }
            if ($key.Key -eq [ConsoleKey]::Escape) { break }
            if ($key.Key -eq [ConsoleKey]::UpArrow) {
                if ($items.Count -gt 0 -and $cursorIndex -gt $pageStart) { $cursorIndex-- }
                continue
            }
            if ($key.Key -eq [ConsoleKey]::DownArrow) {
                if ($items.Count -gt 0 -and $cursorIndex -lt $pageEnd) { $cursorIndex++ }
                continue
            }
            if ($key.Key -eq [ConsoleKey]::LeftArrow) {
                if ($items.Count -gt 0) {
                    if ($pageIndex -gt 0) {
                        $rowOffset = [Math]::Max(0, $cursorIndex - $pageStart)
                        $pageIndex--
                        $newStart = $pageIndex * $pageSize
                        $newEnd = [Math]::Min($items.Count - 1, $newStart + $pageSize - 1)
                        $cursorIndex = [Math]::Min($newEnd, $newStart + $rowOffset)
                    }
                }
                continue
            }
            if ($key.Key -eq [ConsoleKey]::RightArrow) {
                if ($items.Count -gt 0) {
                    if ($pageIndex -lt ($totalPages - 1)) {
                        $rowOffset = [Math]::Max(0, $cursorIndex - $pageStart)
                        $pageIndex++
                        $newStart = $pageIndex * $pageSize
                        $newEnd = [Math]::Min($items.Count - 1, $newStart + $pageSize - 1)
                        $cursorIndex = [Math]::Min($newEnd, $newStart + $rowOffset)
                    }
                }
                continue
            }
            if ($key.Key -eq [ConsoleKey]::Spacebar) {
                if ($items.Count -gt 0) { $items[$cursorIndex].Selected = -not $items[$cursorIndex].Selected }
                continue
            }
            if ($key.Key -eq [ConsoleKey]::A) {
                foreach ($it in $items) { $it.Selected = $true }
                continue
            }
            if ($key.Key -eq [ConsoleKey]::N) {
                foreach ($it in $items) { $it.Selected = $false }
                continue
            }
            if ($key.Key -eq [ConsoleKey]::R) {
                Show-Loading -Message "Refreshing package and extension lists..."
                $wingetInstalled = Get-InstalledWingetPackageIds
                $vscodeInstalled = Get-InstalledVscodeExtensionIds
                $wingetSpec = Read-ListFile -Path $WingetFile
                $vscodeSpec = Read-ListFile -Path $VscodeFile
                $items = if ($main -eq "1") {
                    Build-SyncItems -WingetInstalled $wingetInstalled -VscodeInstalled $vscodeInstalled -WingetSpec $wingetSpec -VscodeSpec $vscodeSpec
                } elseif ($main -eq "2") {
                    Build-UninstallItems -WingetInstalled $wingetInstalled -VscodeInstalled $vscodeInstalled -WingetSpec $wingetSpec -VscodeSpec $vscodeSpec
                } else {
                    Build-UpdateItems -WingetInstalled $wingetInstalled -VscodeInstalled $vscodeInstalled
                }
                continue
            }
            if ($key.Key -eq [ConsoleKey]::Enter) {
                if ($main -eq "1") {
                    Invoke-SyncSelection -Items $items -WingetFile $WingetFile -VscodeFile $VscodeFile
                } elseif ($main -eq "2") {
                    Invoke-UninstallSelection -Items $items
                } else {
                    Invoke-UpdateSelection -Items $items
                }
                Write-Host ""
                [void](Read-Host "Press Enter to continue")
                break
            }
        }
        break
    }
}

Write-Host "Exited."
