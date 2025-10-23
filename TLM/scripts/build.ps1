param(
    [string]$Configuration = 'Debug',
    [switch]$NoRestore,
    [switch]$NoSubmoduleUpdate,
    [string]$ManagedDllDir
)

. "$PSScriptRoot/common.ps1"

Invoke-TmpeBuild -Configuration $Configuration -NoRestore:$NoRestore -NoSubmoduleUpdate:$NoSubmoduleUpdate -ManagedDllDir $ManagedDllDir | Out-Null

Write-Host "[TMPE] Build completed for configuration '$Configuration'."
