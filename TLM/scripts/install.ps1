param(
    [string]$Configuration = 'Release',
    [string]$Destination,
    [switch]$NoBuild,
    [switch]$NoRestore,
    [switch]$NoSubmoduleUpdate
)

. "$PSScriptRoot/common.ps1"

Invoke-TmpeInstall -Configuration $Configuration -Destination $Destination -NoBuild:$NoBuild -NoRestore:$NoRestore -NoSubmoduleUpdate:$NoSubmoduleUpdate
