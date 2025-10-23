param(
    [switch]$NoSubmoduleUpdate,
    [string]$ManagedDllDir
)

. "$PSScriptRoot/common.ps1"

Invoke-TmpeRestore -NoSubmoduleUpdate:$NoSubmoduleUpdate -ManagedDllDir $ManagedDllDir

Write-Host '[TMPE] Dependencies restored successfully.'
