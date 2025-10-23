param(
    [switch]$NoSubmoduleUpdate
)

. "$PSScriptRoot/common.ps1"

Invoke-TmpeRestore -NoSubmoduleUpdate:$NoSubmoduleUpdate

Write-Host '[TMPE] Dependencies restored successfully.'
