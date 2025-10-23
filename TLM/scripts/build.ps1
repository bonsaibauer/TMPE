param(
    [string]$Configuration = 'Debug',
    [switch]$NoRestore,
    [switch]$NoSubmoduleUpdate
)

. "$PSScriptRoot/common.ps1"

Invoke-TmpeBuild -Configuration $Configuration -NoRestore:$NoRestore -NoSubmoduleUpdate:$NoSubmoduleUpdate | Out-Null

Write-Host "[TMPE] Build completed for configuration '$Configuration'."
