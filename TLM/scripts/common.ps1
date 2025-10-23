param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Script:RepoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$Script:ToolsDir = Join-Path $Script:RepoRoot '.tools'

function Get-RepoRoot {
    return $Script:RepoRoot
}

function Get-ToolsDir {
    if (-not (Test-Path $Script:ToolsDir)) {
        New-Item -Path $Script:ToolsDir -ItemType Directory | Out-Null
    }

    return $Script:ToolsDir
}

function Get-NuGetExePath {
    return Join-Path (Get-ToolsDir) 'nuget.exe'
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
        [switch]$NoSubmoduleUpdate
    )

    if (-not (Test-Path $SolutionPath)) {
        throw "Solution '$SolutionPath' does not exist."
    }

    if (-not $NoSubmoduleUpdate) {
        Invoke-GitSubmoduleUpdate -Init
    }

    $nugetExe = Ensure-NuGetExe
    $arguments = @('restore', $SolutionPath, '-NonInteractive')
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

    $msbuild = Get-MSBuildPath
    Write-Host "[TMPE] Running MSBuild from '$msbuild'"
    $args = @($SolutionPath, "/t:$Target", "/p:Configuration=$Configuration", '/m', "/v:$Verbosity")
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
        [string]$SolutionPath
    )

    if ([string]::IsNullOrWhiteSpace($SolutionPath)) {
        $SolutionPath = Get-SolutionPath -RelativePath 'TMPE.sln'
    }

    Invoke-NuGetRestore -SolutionPath $SolutionPath -NoSubmoduleUpdate:$NoSubmoduleUpdate | Out-Null
}

function Invoke-TmpeBuild {
    param(
        [string]$Configuration = 'Debug',
        [switch]$NoRestore,
        [switch]$NoSubmoduleUpdate,
        [string]$SolutionPath
    )

    if (-not $NoRestore) {
        Invoke-TmpeRestore -NoSubmoduleUpdate:$NoSubmoduleUpdate -SolutionPath $SolutionPath
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
        [string]$SolutionPath
    )

    if ($NoBuild) {
        $outputPath = Get-BuildOutputPath -Configuration $Configuration
        if (-not (Test-Path $outputPath)) {
            throw "Build output directory '$outputPath' does not exist. Run Invoke-TmpeBuild first or omit -NoBuild."
        }
    }
    else {
        $outputPath = Invoke-TmpeBuild -Configuration $Configuration -NoRestore:$NoRestore -NoSubmoduleUpdate:$NoSubmoduleUpdate -SolutionPath $SolutionPath
    }

    if ([string]::IsNullOrWhiteSpace($Destination)) {
        Write-Host '[TMPE] No destination provided. Skipping artifact copy.' -ForegroundColor Yellow
        return $outputPath
    }

    Copy-BuildOutput -Configuration $Configuration -Destination $Destination
    Write-Host "[TMPE] Artifacts copied to '$Destination'."

    return $outputPath
}
