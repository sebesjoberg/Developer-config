$registryPath = "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem"
$name = "LongPathsEnabled"
$value = 1

Set-ItemProperty -Path $registryPath -Name $name -Type DWord -Value $value
Write-Host "Enabled Windows long paths (LongPathsEnabled=1)."
