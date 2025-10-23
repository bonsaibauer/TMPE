param(
    [string]$Configuration = 'Release',
    [string]$Destination,
    [switch]$NoBuild,
    [switch]$NoRestore,
    [switch]$NoSubmoduleUpdate,
    [string]$ManagedDllDir,
    [switch]$UseDotNet
)

. "$PSScriptRoot/common.ps1"

Invoke-TmpeInstall -Configuration $Configuration -Destination $Destination -NoBuild:$NoBuild -NoRestore:$NoRestore -NoSubmoduleUpdate:$NoSubmoduleUpdate -ManagedDllDir $ManagedDllDir -UseDotNet:$UseDotNet
