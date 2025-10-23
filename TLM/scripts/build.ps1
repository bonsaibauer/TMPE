param(
    [string]$Configuration = 'Debug',
    [switch]$NoRestore,
    [switch]$NoSubmoduleUpdate,
    [string]$ManagedDllDir,
    [switch]$UseDotNet
)

. "$PSScriptRoot/common.ps1"

Invoke-TmpeBuild -Configuration $Configuration -NoRestore:$NoRestore -NoSubmoduleUpdate:$NoSubmoduleUpdate -ManagedDllDir $ManagedDllDir -UseDotNet:$UseDotNet | Out-Null

Write-Host "[TMPE] Build completed for configuration '$Configuration'."
