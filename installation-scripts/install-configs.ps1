param(
    [string[]]$SelectedConfigs
)

$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path

function Read-YesNoDefaultNo {
    param([string]$Message)
    while ($true) {
        $answer = Read-Host "$Message (Y/y/Yes/yes, N/n/No/no, Enter=No)"
        if ([string]::IsNullOrWhiteSpace($answer)) { return $false }
        switch ($answer.Trim().ToLowerInvariant()) {
            "y" { return $true }
            "yes" { return $true }
            "n" { return $false }
            "no" { return $false }
            default { Write-Host "Please answer y or n." }
        }
    }
}

function ConvertTo-HashtableCompat {
    param($InputObject)
    if ($null -eq $InputObject) { return $null }

    if ($InputObject -is [System.Collections.IDictionary]) {
        $result = [ordered]@{}
        foreach ($k in $InputObject.Keys) {
            $result[$k] = ConvertTo-HashtableCompat -InputObject $InputObject[$k]
        }
        return $result
    }

    if ($InputObject -is [System.Collections.IEnumerable] -and -not ($InputObject -is [string])) {
        $arr = @()
        foreach ($item in $InputObject) {
            $arr += ,(ConvertTo-HashtableCompat -InputObject $item)
        }
        return $arr
    }

    if ($InputObject -is [psobject] -and $InputObject.PSObject.Properties.Count -gt 0) {
        $result = [ordered]@{}
        foreach ($p in $InputObject.PSObject.Properties) {
            $result[$p.Name] = ConvertTo-HashtableCompat -InputObject $p.Value
        }
        return $result
    }

    return $InputObject
}

function Get-JsonMap {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return [ordered]@{} }
    $raw = Get-Content -LiteralPath $Path -Raw
    if ([string]::IsNullOrWhiteSpace($raw)) { return [ordered]@{} }
    $obj = $raw | ConvertFrom-Json
    $map = ConvertTo-HashtableCompat -InputObject $obj
    if ($map -is [hashtable]) { return $map }
    return [ordered]@{}
}

function Save-JsonMap {
    param(
        [string]$Path,
        [hashtable]$Map
    )
    $json = $Map | ConvertTo-Json -Depth 100
    Set-Content -LiteralPath $Path -Value $json
}

function Get-JsonComparable {
    param($Value)
    if ($null -eq $Value) { return "null" }
    return ($Value | ConvertTo-Json -Depth 100 -Compress)
}

function Merge-JsonSettingsToRepo {
    param(
        [string]$RepoPath,
        [string]$UserPath,
        [string]$Label
    )
    if (-not (Test-Path -LiteralPath $UserPath)) { return }

    $repo = Get-JsonMap -Path $RepoPath
    $user = Get-JsonMap -Path $UserPath
    if ($user.Count -eq 0) { return }

    Write-Host ""
    Write-Host "Reviewing $Label differences..."

    foreach ($key in @($repo.Keys)) {
        if ($user.ContainsKey($key)) {
            $repoValue = Get-JsonComparable -Value $repo[$key]
            $userValue = Get-JsonComparable -Value $user[$key]
            if ($repoValue -ne $userValue) {
                $useUser = Read-YesNoDefaultNo -Message "$Label key `"$key`" differs. Use current user value?"
                if ($useUser) { $repo[$key] = $user[$key] }
            }
        }
    }

    foreach ($key in @($user.Keys | Where-Object { -not $repo.ContainsKey($_) } | Sort-Object)) {
        $addKey = Read-YesNoDefaultNo -Message "$Label key `"$key`" exists only in current config. Add it to repo config?"
        if ($addKey) { $repo[$key] = $user[$key] }
    }

    Save-JsonMap -Path $RepoPath -Map $repo
}

function Get-GitConfigMap {
    param([string]$Path)
    $map = [ordered]@{}
    if (-not (Test-Path -LiteralPath $Path)) { return $map }

    $currentSection = $null
    foreach ($line in Get-Content -LiteralPath $Path) {
        if ($line -match "^\s*#") { continue }
        if ($line -match "^\s*;") { continue }
        if ($line -match "^\s*$") { continue }
        if ($line -match "^\s*\[(.+)\]\s*$") {
            $currentSection = $matches[1].Trim()
            if (-not $map.Contains($currentSection)) {
                $map[$currentSection] = [ordered]@{}
            }
            continue
        }
        if ($null -ne $currentSection -and $line -match "^\s*([A-Za-z0-9\.\-_]+)\s*=\s*(.*)\s*$") {
            $key = $matches[1].Trim()
            $val = $matches[2]
            $map[$currentSection][$key] = $val
        }
    }

    return $map
}

function Save-GitConfigMap {
    param(
        [string]$Path,
        [hashtable]$Map
    )
    $lines = [System.Collections.Generic.List[string]]::new()
    foreach ($section in $Map.Keys) {
        $lines.Add("[$section]")
        foreach ($key in $Map[$section].Keys) {
            $lines.Add("    $key = $($Map[$section][$key])")
        }
        $lines.Add("")
    }
    Set-Content -LiteralPath $Path -Value $lines
}

function Merge-GitConfigToRepo {
    param(
        [string]$RepoPath,
        [string]$UserPath
    )
    if (-not (Test-Path -LiteralPath $UserPath)) { return }

    $repo = Get-GitConfigMap -Path $RepoPath
    $user = Get-GitConfigMap -Path $UserPath
    if ($user.Count -eq 0) { return }

    Write-Host ""
    Write-Host "Reviewing git config differences..."

    function Test-IsMachineSpecificGitKey {
        param(
            [string]$Section,
            [string]$Key
        )

        if ($Section -ieq "user") {
            if ($Key -ieq "name" -or $Key -ieq "email" -or $Key -ieq "signingkey") {
                return $true
            }
        }

        return $false
    }

    foreach ($section in @($repo.Keys)) {
        foreach ($key in @($repo[$section].Keys)) {
            if (Test-IsMachineSpecificGitKey -Section $section -Key $key) {
                continue
            }
            if ($user.Contains($section) -and $user[$section].Contains($key)) {
                $repoValue = [string]$repo[$section][$key]
                $userValue = [string]$user[$section][$key]
                if ($repoValue -ne $userValue) {
                    $useUser = Read-YesNoDefaultNo -Message "git [$section] $key differs. Use current user value?"
                    if ($useUser) { $repo[$section][$key] = $user[$section][$key] }
                }
            }
        }
    }

    foreach ($section in @($user.Keys)) {
        if (-not $repo.Contains($section)) {
            $repo[$section] = [ordered]@{}
        }
        foreach ($key in @($user[$section].Keys)) {
            if (Test-IsMachineSpecificGitKey -Section $section -Key $key) {
                continue
            }
            if (-not $repo[$section].Contains($key)) {
                $addKey = Read-YesNoDefaultNo -Message "git [$section] $key exists only in current config. Add it to repo config?"
                if ($addKey) { $repo[$section][$key] = $user[$section][$key] }
            }
        }
    }

    Save-GitConfigMap -Path $RepoPath -Map $repo
}

function Set-ManagedLink {
    param(
        [string]$Target,
        [string]$Source,
        [bool]$PromptIfNonEmpty = $false
    )
    $parent = Split-Path -Parent $Target
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    if (Test-Path -LiteralPath $Target) {
        if ($PromptIfNonEmpty) {
            $raw = Get-Content -LiteralPath $Target -Raw -ErrorAction SilentlyContinue
            if (-not [string]::IsNullOrWhiteSpace($raw)) {
                $ok = Read-YesNoDefaultNo -Message "Existing profile at `"$Target`" is non-empty. Overwrite with managed symlink?"
                if (-not $ok) {
                    Write-Host "Skipping profile link for $Target"
                    return
                }
            }
        }
        Remove-Item -LiteralPath $Target -Force
    }

    Write-Host "Linking $Target -> $Source"
    try {
        New-Item -ItemType SymbolicLink -Path $Target -Target $Source -Force | Out-Null
        return
    }
    catch {
        Write-Host "Symlink failed for $Target. Trying hard link fallback..."
    }

    try {
        New-Item -ItemType HardLink -Path $Target -Target $Source -Force | Out-Null
        Write-Host "Created hard link for $Target"
        return
    }
    catch {
        Write-Host "Hard link failed for $Target. Falling back to copy."
    }

    Copy-Item -LiteralPath $Source -Destination $Target -Force
    Write-Host "Copied managed file to $Target"
}

$links = [ordered]@{
    "$HOME\.gitconfig" = "configs/git/.gitconfig"
    "$HOME\.gitconfig.local" = "configs/git/.gitconfig.local"
    "$env:SystemDrive\config.omp.json" = "configs/powershell/config.omp.json"
    "$HOME\Documents\PowerShell\Microsoft.PowerShell_profile.ps1" = "configs/powershell/profile.ps1"
    "$HOME\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1" = "configs/powershell/profile.ps1"
    "$env:APPDATA\Code\User\settings.json" = "configs/vscode/settings.json"
    "$env:APPDATA\Code\User\keybindings.json" = "configs/vscode/keybindings.json"
    "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json" = "configs/windows-terminal/settings.json"
}

$selectedSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
if ($SelectedConfigs -and $SelectedConfigs.Count -gt 0) {
    foreach ($cfg in $SelectedConfigs) {
        if (-not [string]::IsNullOrWhiteSpace($cfg)) {
            $normalized = ($cfg -replace "/", "\").TrimStart(".\")
            [void]$selectedSet.Add($normalized)
        }
    }
}

function Test-IsSelected {
    param([string]$RelativeSource)
    if ($selectedSet.Count -eq 0) { return $true }
    $normalized = ($RelativeSource -replace "/", "\").TrimStart(".\")
    return $selectedSet.Contains($normalized)
}

$gitTarget = "$HOME\.gitconfig"
$gitSourceRelative = "configs/git/.gitconfig"
$gitSource = Join-Path $repoRoot $gitSourceRelative
if (Test-IsSelected -RelativeSource $gitSourceRelative) {
    Merge-GitConfigToRepo -RepoPath $gitSource -UserPath $gitTarget
}

$gitLocalSourceRelative = "configs/git/.gitconfig.local"
$gitLocalSource = Join-Path $repoRoot $gitLocalSourceRelative
if (Test-IsSelected -RelativeSource $gitLocalSourceRelative) {
    if (-not (Test-Path -LiteralPath $gitLocalSource)) {
        $gitLocalExample = Join-Path $repoRoot "configs/git/.gitconfig.local.example"
        if (Test-Path -LiteralPath $gitLocalExample) {
            Copy-Item -LiteralPath $gitLocalExample -Destination $gitLocalSource -Force
            Write-Host "Created $gitLocalSource from example template."
        }
        else {
            Set-Content -LiteralPath $gitLocalSource -Value @(
                "[user]"
                "    name = Your Name"
                "    email = your.email@example.com"
            )
            Write-Host "Created $gitLocalSource with placeholder values."
        }
        Write-Host "Update configs/git/.gitconfig.local with your machine-specific identity."
    }
}

$vscodeSettingsTarget = "$env:APPDATA\Code\User\settings.json"
$vscodeSettingsSourceRelative = "configs/vscode/settings.json"
$vscodeSettingsSource = Join-Path $repoRoot $vscodeSettingsSourceRelative
if (Test-IsSelected -RelativeSource $vscodeSettingsSourceRelative) {
    Merge-JsonSettingsToRepo -RepoPath $vscodeSettingsSource -UserPath $vscodeSettingsTarget -Label "VS Code settings"
}

$terminalTarget = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
$terminalSourceRelative = "configs/windows-terminal/settings.json"
$terminalSource = Join-Path $repoRoot $terminalSourceRelative
if (Test-IsSelected -RelativeSource $terminalSourceRelative) {
    Merge-JsonSettingsToRepo -RepoPath $terminalSource -UserPath $terminalTarget -Label "Windows Terminal settings"
}

foreach ($target in $links.Keys) {
    $relativeSource = $links[$target]
    if (-not (Test-IsSelected -RelativeSource $relativeSource)) {
        continue
    }

    $source = Join-Path $repoRoot $relativeSource
    $isProfileTarget = (
        $target -ieq "$HOME\Documents\PowerShell\Microsoft.PowerShell_profile.ps1" -or
        $target -ieq "$HOME\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1"
    )
    Set-ManagedLink -Target $target -Source $source -PromptIfNonEmpty:$isProfileTarget
}
