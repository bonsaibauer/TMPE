param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$resolvedScriptRoot = Resolve-Path $PSScriptRoot
$candidate = $resolvedScriptRoot
$gitRoot = $null

while ($candidate -and (-not $gitRoot)) {
    if (Test-Path (Join-Path $candidate '.git')) {
        $gitRoot = $candidate
        break
    }

    $parent = Split-Path -Parent $candidate
    if ([string]::IsNullOrWhiteSpace($parent) -or $parent -eq $candidate) {
        break
    }

    $candidate = $parent
}

if (-not $gitRoot) {
    $fallbackParent = Resolve-Path (Join-Path $resolvedScriptRoot '..')
    if ($fallbackParent) {
        $fallback = Join-Path $fallbackParent '..'
        if (Test-Path $fallback) {
            $gitRoot = Resolve-Path $fallback
        }
        else {
            $gitRoot = $fallbackParent
        }
    }
}

$gitRoot = [string]$gitRoot
if ([string]::IsNullOrWhiteSpace($gitRoot)) {
    throw 'Unable to determine the TM:PE repository root.'
}

$Script:RepoRoot = [string]$gitRoot
$Script:ToolsDir = Join-Path $Script:RepoRoot '.tools'
$Script:PackagesDir = Join-Path (Join-Path $Script:RepoRoot 'TLM') 'packages'
$Script:DependenciesDir = Join-Path (Join-Path $Script:RepoRoot 'TLM') 'dependencies'
$Script:NuGetCacheDir = Join-Path $Script:ToolsDir 'nuget-cache'
$Script:DefaultManagedDllDir = Join-Path (Join-Path $Script:RepoRoot 'TLM') 'dependencies'
$Script:ManagedDllDirectory = $null
$Script:ManagedDllFileNames = @(
    'Assembly-CSharp.dll',
    'ColossalManaged.dll',
    'ICities.dll',
    'UnityEngine.dll',
    'UnityEngine.Networking.dll',
    'UnityEngine.UI.dll'
)

function Get-RepoRoot {
    return $Script:RepoRoot
}

function Get-ToolsDir {
    if (-not (Test-Path $Script:ToolsDir)) {
        New-Item -Path $Script:ToolsDir -ItemType Directory | Out-Null
    }

    return $Script:ToolsDir
}

function Get-PackagesDir {
    if (-not (Test-Path $Script:PackagesDir)) {
        New-Item -Path $Script:PackagesDir -ItemType Directory | Out-Null
    }

    return $Script:PackagesDir
}

function Get-DependenciesDir {
    if (-not (Test-Path $Script:DependenciesDir)) {
        New-Item -Path $Script:DependenciesDir -ItemType Directory | Out-Null
    }

    return $Script:DependenciesDir
}

function Ensure-NuGetEnvironment {
    $packagesDir = Get-PackagesDir
    if ([string]::IsNullOrWhiteSpace($env:NUGET_PACKAGES) -or $env:NUGET_PACKAGES -ne $packagesDir) {
        $env:NUGET_PACKAGES = $packagesDir
    }

    if (-not (Test-Path $Script:NuGetCacheDir)) {
        New-Item -Path $Script:NuGetCacheDir -ItemType Directory | Out-Null
    }

    if ([string]::IsNullOrWhiteSpace($env:NUGET_HTTP_CACHE_PATH) -or $env:NUGET_HTTP_CACHE_PATH -ne $Script:NuGetCacheDir) {
        $env:NUGET_HTTP_CACHE_PATH = $Script:NuGetCacheDir
    }
}

function Get-NuGetExePath {
    return Join-Path (Get-ToolsDir) 'nuget.exe'
}

function Set-ManagedDllDirectory {
    param(
        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        $Script:ManagedDllDirectory = $null
        return
    }

    $resolved = Resolve-Path -LiteralPath $Path -ErrorAction Stop
    $Script:ManagedDllDirectory = [string]$resolved
}

function Get-ManagedDllDirectory {
    if ($Script:ManagedDllDirectory) {
        return $Script:ManagedDllDirectory
    }

    if (-not [string]::IsNullOrWhiteSpace($env:TMPE_MANAGED_DLL_DIR)) {
        try {
            $resolved = Resolve-Path -LiteralPath $env:TMPE_MANAGED_DLL_DIR -ErrorAction Stop
            $Script:ManagedDllDirectory = [string]$resolved
            return $Script:ManagedDllDirectory
        }
        catch {
        }
    }

    if (Test-Path $Script:DefaultManagedDllDir) {
        $Script:ManagedDllDirectory = [string](Resolve-Path $Script:DefaultManagedDllDir)
        return $Script:ManagedDllDirectory
    }

    return $null
}

function Test-ManagedDllAvailability {
    $directory = Get-ManagedDllDirectory
    if (-not $directory) {
        return [pscustomobject]@{
            Directory = $null
            Missing   = $Script:ManagedDllFileNames
        }
    }

    $missing = @()
    foreach ($name in $Script:ManagedDllFileNames) {
        $candidate = Join-Path $directory $name
        if (-not (Test-Path $candidate)) {
            $missing += $name
        }
    }

    return [pscustomobject]@{
        Directory = $directory
        Missing   = $missing
    }
}

function Ensure-ManagedDllAvailability {
    $status = Test-ManagedDllAvailability
    if (-not $status.Directory) {
        throw "Managed Cities: Skylines assemblies were not found. Run 'pwsh .\\TLM\\scripts\\update.ps1 -ManagedDllDir \"<path to Cities_Data\\Managed>\"' or copy the DLLs to 'TLM\\dependencies'."
    }

    if ($status.Missing.Count -gt 0) {
        $missingList = $status.Missing -join ', '
        throw "Managed assembly directory '$($status.Directory)' is missing the following files: $missingList. See docs/BUILDING_INSTRUCTIONS.md for setup steps."
    }

    return $status.Directory
}

function Sync-ManagedAssemblies {
    param(
        [string]$SourceDir
    )

    if ([string]::IsNullOrWhiteSpace($SourceDir)) {
        return
    }

    $resolvedSource = Resolve-Path -LiteralPath $SourceDir -ErrorAction Stop
    $resolvedSource = [string]$resolvedSource

    foreach ($name in $Script:ManagedDllFileNames) {
        $candidate = Join-Path $resolvedSource $name
        if (-not (Test-Path $candidate)) {
            throw "Managed assembly '$name' was not found in '$resolvedSource'."
        }
    }

    $destination = Get-DependenciesDir
    foreach ($name in $Script:ManagedDllFileNames) {
        Copy-Item -LiteralPath (Join-Path $resolvedSource $name) -Destination (Join-Path $destination $name) -Force
    }

    Write-Host "[TMPE] Copied managed assemblies from '$resolvedSource' to '$destination'."
    Set-ManagedDllDirectory -Path $destination
}

function New-MSBuildPropertyArgument {
    param(
        [string]$Name,
        [string]$Value
    )

    if ([string]::IsNullOrWhiteSpace($Name) -or [string]::IsNullOrWhiteSpace($Value)) {
        return $null
    }

    $escaped = $Value.Replace('"', '""')
    return "/p:$Name=\"$escaped\""
}

function Ensure-NuGetExe {
    $nugetExe = Get-NuGetExePath
    if (Test-Path $nugetExe) {
        return $nugetExe
    }

    Write-Host '[TMPE] Downloading nuget.exe …'
    $nugetUri = 'https://dist.nuget.org/win-x86-commandline/latest/nuget.exe'
    Invoke-WebRequest -Uri $nugetUri -OutFile $nugetExe -UseBasicParsing
    return $nugetExe
}

function Get-GitPath {
    $git = Get-Command git -ErrorAction SilentlyContinue
    if ($null -ne $git) {
        return $git.Source
    }

    throw 'git command was not found in PATH.'
}

function Invoke-GitSubmoduleUpdate {
    param (
        [switch]$Init
    )

    $git = Get-GitPath
    $args = @('submodule', 'update', '--recursive')
    if ($Init) {
        $args += '--init'
    }

    $result = & $git -C (Get-RepoRoot) @args
    if ($LASTEXITCODE -ne 0) {
        throw 'git submodule update failed.'
    }

    return $result
}

function Invoke-NuGetRestore {
    param(
        [string]$SolutionPath,
        [switch]$NoSubmoduleUpdate,
        [string]$ManagedDllDir
    )

    if (-not (Test-Path $SolutionPath)) {
        throw "Solution '$SolutionPath' does not exist."
    }

    if (-not $NoSubmoduleUpdate) {
        Invoke-GitSubmoduleUpdate -Init
    }

    if (-not [string]::IsNullOrWhiteSpace($ManagedDllDir)) {
        Sync-ManagedAssemblies -SourceDir $ManagedDllDir
    }

    Ensure-NuGetEnvironment
    $nugetExe = Ensure-NuGetExe
    $packagesDir = Get-PackagesDir
    $solutionDir = Split-Path -Parent $SolutionPath

    $arguments = @(
        'restore',
        $SolutionPath,
        '-NonInteractive',
        '-PackagesDirectory',
        $packagesDir,
        '-SolutionDirectory',
        $solutionDir
    )
    $result = & $nugetExe @arguments
    if ($LASTEXITCODE -ne 0) {
        throw 'NuGet restore failed.'
    }

    return $result
}

function Get-MSBuildPath {
    $command = Get-Command msbuild -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
    if (Test-Path $vswhere) {
        $instances = & $vswhere -latest -requires Microsoft.Component.MSBuild -find 'MSBuild/**/Bin/MSBuild.exe'
        if ($LASTEXITCODE -eq 0 -and $instances) {
            $first = $instances | Select-Object -First 1
            if ($first) {
                return $first
            }
        }
    }

    $fallbacks = @(
        'C:/Program Files/Microsoft Visual Studio/2022/Community/MSBuild/Current/Bin/MSBuild.exe',
        'C:/Program Files (x86)/Microsoft Visual Studio/2022/BuildTools/MSBuild/Current/Bin/MSBuild.exe'
    )

    foreach ($candidate in $fallbacks) {
        if (Test-Path $candidate) {
            return $candidate
        }
    }

    throw 'MSBuild executable could not be located. Make sure Visual Studio or the Build Tools are installed.'
}

function Invoke-MSBuild {
    param(
        [string]$SolutionPath,
        [string]$Configuration = 'Debug',
        [string]$Target = 'Build',
        [string]$Verbosity = 'minimal'
    )

    if (-not (Test-Path $SolutionPath)) {
        throw "Solution '$SolutionPath' does not exist."
    }

    Ensure-NuGetEnvironment
    $managedDllDir = Ensure-ManagedDllAvailability
    $msbuild = Get-MSBuildPath
    Write-Host "[TMPE] Running MSBuild from '$msbuild'"
    $packagesDir = Get-PackagesDir
    $args = @(
        $SolutionPath,
        "/t:$Target"
    )

    $propertyArgs = @()
    $propertyArgs += New-MSBuildPropertyArgument -Name 'Configuration' -Value $Configuration
    $propertyArgs += New-MSBuildPropertyArgument -Name 'RestorePackagesPath' -Value $packagesDir
    $propertyArgs += New-MSBuildPropertyArgument -Name 'NuGetPackageRoot' -Value $packagesDir
    if ($managedDllDir) {
        $propertyArgs += New-MSBuildPropertyArgument -Name 'MangedDLLPath' -Value $managedDllDir
    }

    foreach ($propertyArg in $propertyArgs) {
        if ($propertyArg) {
            $args += $propertyArg
        }
    }

    $args += '/m'
    $args += "/v:$Verbosity"
    $result = & $msbuild @args
    if ($LASTEXITCODE -ne 0) {
        throw 'MSBuild failed. Inspect the output above for details.'
    }

    return $result
}

function Get-SolutionPath {
    param(
        [string]$RelativePath = 'TMPE.sln'
    )

    return Join-Path (Join-Path (Get-RepoRoot) 'TLM') $RelativePath
}

function Get-BuildOutputPath {
    param(
        [string]$Configuration
    )

    if ([string]::IsNullOrWhiteSpace($Configuration)) {
        throw 'Configuration must be provided.'
    }

    return Join-Path (Join-Path (Get-RepoRoot) 'TLM/TLM/bin') $Configuration
}

function Copy-BuildOutput {
    param(
        [string]$Configuration,
        [string]$Destination
    )

    if ([string]::IsNullOrWhiteSpace($Destination)) {
        throw 'Destination must not be empty.'
    }

    $outputPath = Get-BuildOutputPath -Configuration $Configuration
    if (-not (Test-Path $outputPath)) {
        throw "Build output directory '$outputPath' does not exist."
    }

    if (-not (Test-Path $Destination)) {
        Write-Host "[TMPE] Creating destination '$Destination'"
        New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    }

    Write-Host "[TMPE] Copying build artifacts to '$Destination'"
    $robocopy = Get-Command robocopy -ErrorAction SilentlyContinue
    if ($null -ne $robocopy) {
        robocopy $outputPath $Destination /MIR /NFL /NDL /NJH /NJS /NC /NS | Out-Null
    }
    else {
        Copy-Item -Path (Join-Path $outputPath '*') -Destination $Destination -Recurse -Force
    }
}

function Invoke-TmpeRestore {
    param(
        [switch]$NoSubmoduleUpdate,
        [string]$SolutionPath,
        [string]$ManagedDllDir
    )

    if ([string]::IsNullOrWhiteSpace($SolutionPath)) {
        $SolutionPath = Get-SolutionPath -RelativePath 'TMPE.sln'
    }

    Invoke-NuGetRestore -SolutionPath $SolutionPath -NoSubmoduleUpdate:$NoSubmoduleUpdate -ManagedDllDir $ManagedDllDir | Out-Null
}

function Invoke-TmpeBuild {
    param(
        [string]$Configuration = 'Debug',
        [switch]$NoRestore,
        [switch]$NoSubmoduleUpdate,
        [string]$SolutionPath,
        [string]$ManagedDllDir
    )

    if (-not $NoRestore) {
        Invoke-TmpeRestore -NoSubmoduleUpdate:$NoSubmoduleUpdate -SolutionPath $SolutionPath -ManagedDllDir $ManagedDllDir
    }
    elseif (-not [string]::IsNullOrWhiteSpace($ManagedDllDir)) {
        Sync-ManagedAssemblies -SourceDir $ManagedDllDir
    }

    if ([string]::IsNullOrWhiteSpace($SolutionPath)) {
        $SolutionPath = Get-SolutionPath -RelativePath 'TMPE.sln'
    }

    Invoke-MSBuild -SolutionPath $SolutionPath -Configuration $Configuration | Out-Null

    $outputPath = Get-BuildOutputPath -Configuration $Configuration
    if (-not (Test-Path $outputPath)) {
        throw "Build output directory '$outputPath' does not exist after building."
    }

    return $outputPath
}

function Invoke-TmpeInstall {
    param(
        [string]$Configuration = 'Release',
        [string]$Destination,
        [switch]$NoBuild,
        [switch]$NoRestore,
        [switch]$NoSubmoduleUpdate,
        [string]$SolutionPath,
        [string]$ManagedDllDir
    )

    if ($NoBuild) {
        $outputPath = Get-BuildOutputPath -Configuration $Configuration
        if (-not (Test-Path $outputPath)) {
            throw "Build output directory '$outputPath' does not exist. Run Invoke-TmpeBuild first or omit -NoBuild."
        }
    }
    else {
        $outputPath = Invoke-TmpeBuild -Configuration $Configuration -NoRestore:$NoRestore -NoSubmoduleUpdate:$NoSubmoduleUpdate -SolutionPath $SolutionPath -ManagedDllDir $ManagedDllDir
    }

    if ([string]::IsNullOrWhiteSpace($Destination)) {
        Write-Host '[TMPE] No destination provided. Skipping artifact copy.' -ForegroundColor Yellow
        return $outputPath
    }

    Copy-BuildOutput -Configuration $Configuration -Destination $Destination
    Write-Host "[TMPE] Artifacts copied to '$Destination'."

    return $outputPath
}
