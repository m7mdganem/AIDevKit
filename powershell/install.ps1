#!/usr/bin/env pwsh
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoDir = $PSScriptRoot
$SkillsSrc = Join-Path -Path (Split-Path -Path $RepoDir -Parent) -ChildPath 'skills'
$BinSrc = Join-Path -Path $PSScriptRoot -ChildPath 'bin'
$SkillsDest = Join-Path -Path $HOME -ChildPath '.copilot/skills'
$BinDest = Join-Path -Path $HOME -ChildPath 'bin'

$script:Green = "$([char]27)[1;32m"
$script:Yellow = "$([char]27)[1;33m"
$script:Red = "$([char]27)[1;31m"
$script:Dim = "$([char]27)[2m"
$script:Reset = "$([char]27)[0m"

function Write-InfoMessage {
    param([Parameter(Mandatory)][string]$Message)
    [Console]::Out.WriteLine(("{0}{1}{2}" -f $script:Green, $Message, $script:Reset))
}

function Write-WarningMessage {
    param([Parameter(Mandatory)][string]$Message)
    [Console]::Out.WriteLine(("{0}{1}{2}" -f $script:Yellow, $Message, $script:Reset))
}

function Write-NoteMessage {
    param([Parameter(Mandatory)][string]$Message)
    [Console]::Out.WriteLine(("{0}{1}{2}" -f $script:Dim, $Message, $script:Reset))
}

function Write-ErrorMessage {
    param([Parameter(Mandatory)][string]$Message)
    [Console]::Error.WriteLine(("{0}{1}{2}" -f $script:Red, $Message, $script:Reset))
}

function Get-NormalizedFullPath {
    param([Parameter(Mandatory)][string]$Path)

    return [System.IO.Path]::GetFullPath($Path).TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    )
}

function Test-LinkedToSource {
    param(
        [Parameter(Mandatory)][string]$SourcePath,
        [Parameter(Mandatory)][string]$DestinationPath
    )

    $destinationItem = Get-Item -LiteralPath $DestinationPath -Force -ErrorAction SilentlyContinue
    if ($null -eq $destinationItem -or -not ($destinationItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint)) {
        return $false
    }

    try {
        $targetPath = $destinationItem.Target
        if ([string]::IsNullOrWhiteSpace($targetPath)) {
            return $false
        }

        if (-not [System.IO.Path]::IsPathRooted($targetPath)) {
            $targetPath = Join-Path -Path (Split-Path -Path $DestinationPath -Parent) -ChildPath $targetPath
        }

        return (Get-NormalizedFullPath -Path $targetPath) -eq (Get-NormalizedFullPath -Path $SourcePath)
    } catch {
        return $false
    }
}

function Test-FileContentMatch {
    param(
        [Parameter(Mandatory)][string]$SourcePath,
        [Parameter(Mandatory)][string]$DestinationPath
    )

    if (-not (Test-Path -LiteralPath $SourcePath -PathType Leaf) -or -not (Test-Path -LiteralPath $DestinationPath -PathType Leaf)) {
        return $false
    }

    $sourceItem = Get-Item -LiteralPath $SourcePath
    $destinationItem = Get-Item -LiteralPath $DestinationPath
    if ($sourceItem.Length -ne $destinationItem.Length) {
        return $false
    }

    return (Get-FileHash -LiteralPath $SourcePath).Hash -eq (Get-FileHash -LiteralPath $DestinationPath).Hash
}

function Test-DirectoryContentMatch {
    param(
        [Parameter(Mandatory)][string]$SourcePath,
        [Parameter(Mandatory)][string]$DestinationPath
    )

    if (-not (Test-Path -LiteralPath $SourcePath -PathType Container) -or -not (Test-Path -LiteralPath $DestinationPath -PathType Container)) {
        return $false
    }

    $sourceRoot = Get-NormalizedFullPath -Path $SourcePath
    $destinationRoot = Get-NormalizedFullPath -Path $DestinationPath
    $sourceFiles = @(Get-ChildItem -LiteralPath $SourcePath -Recurse -File -Force)
    $destinationFiles = @(Get-ChildItem -LiteralPath $DestinationPath -Recurse -File -Force)
    if ($sourceFiles.Count -ne $destinationFiles.Count) {
        return $false
    }

    $sourceDirectories = @(Get-ChildItem -LiteralPath $SourcePath -Recurse -Directory -Force)
    $destinationDirectories = @(Get-ChildItem -LiteralPath $DestinationPath -Recurse -Directory -Force)
    if ($sourceDirectories.Count -ne $destinationDirectories.Count) {
        return $false
    }

    foreach ($sourceDirectory in $sourceDirectories) {
        $relativeDirectory = [System.IO.Path]::GetRelativePath($sourceRoot, $sourceDirectory.FullName)
        if (-not (Test-Path -LiteralPath (Join-Path -Path $destinationRoot -ChildPath $relativeDirectory) -PathType Container)) {
            return $false
        }
    }

    foreach ($sourceFile in $sourceFiles) {
        $relativeFile = [System.IO.Path]::GetRelativePath($sourceRoot, $sourceFile.FullName)
        $destinationFile = Join-Path -Path $destinationRoot -ChildPath $relativeFile
        if (-not (Test-FileContentMatch -SourcePath $sourceFile.FullName -DestinationPath $destinationFile)) {
            return $false
        }
    }

    return $true
}

function Test-CopiedFromSource {
    param(
        [Parameter(Mandatory)][string]$SourcePath,
        [Parameter(Mandatory)][string]$DestinationPath
    )

    if (Test-Path -LiteralPath $SourcePath -PathType Container) {
        return Test-DirectoryContentMatch -SourcePath $SourcePath -DestinationPath $DestinationPath
    }

    return Test-FileContentMatch -SourcePath $SourcePath -DestinationPath $DestinationPath
}

function Save-ExistingDestination {
    param([Parameter(Mandatory)][string]$DestinationPath)

    if ((Test-Path -LiteralPath $DestinationPath) -or (Get-Item -LiteralPath $DestinationPath -Force -ErrorAction SilentlyContinue)) {
        Move-Item -LiteralPath $DestinationPath -Destination "$DestinationPath.bak" -Force
        Write-WarningMessage -Message ("  ~ backed up existing {0} -> {0}.bak" -f $DestinationPath)
    }
}

function Invoke-LinkItem {
    param(
        [Parameter(Mandatory)][string]$SourcePath,
        [Parameter(Mandatory)][string]$DestinationPath
    )

    if (Test-LinkedToSource -SourcePath $SourcePath -DestinationPath $DestinationPath) {
        Write-NoteMessage -Message ("  = already linked: {0}" -f $DestinationPath)
        return
    }

    Save-ExistingDestination -DestinationPath $DestinationPath

    try {
        $null = New-Item -ItemType SymbolicLink -Path $DestinationPath -Target $SourcePath
        Write-InfoMessage -Message ("  + linked {0}" -f $DestinationPath)
    } catch {
        Write-WarningMessage -Message ("  ! symlinks were not permitted; copied {0}. Repo edits will not be live until re-run." -f $DestinationPath)
        if (Test-Path -LiteralPath $SourcePath -PathType Container) {
            Copy-Item -LiteralPath $SourcePath -Destination $DestinationPath -Recurse
        } else {
            Copy-Item -LiteralPath $SourcePath -Destination $DestinationPath
        }
        Write-InfoMessage -Message ("  + linked {0}" -f $DestinationPath)
    }
}

function Invoke-UnlinkItem {
    param(
        [Parameter(Mandatory)][string]$SourcePath,
        [Parameter(Mandatory)][string]$DestinationPath
    )

    if (Test-LinkedToSource -SourcePath $SourcePath -DestinationPath $DestinationPath) {
        Remove-Item -LiteralPath $DestinationPath
        Write-InfoMessage -Message ("  - removed {0}" -f $DestinationPath)
    } elseif (Test-CopiedFromSource -SourcePath $SourcePath -DestinationPath $DestinationPath) {
        Remove-Item -LiteralPath $DestinationPath -Recurse -Force
        Write-InfoMessage -Message ("  - removed {0}" -f $DestinationPath)
    } else {
        Write-NoteMessage -Message ("  = skipped (not linked here): {0}" -f $DestinationPath)
    }
}

function Invoke-InstallAll {
    $null = New-Item -ItemType Directory -Path $SkillsDest -Force
    $null = New-Item -ItemType Directory -Path $BinDest -Force

    Write-InfoMessage -Message ("Linking skills -> {0}" -f $SkillsDest)
    if (Test-Path -LiteralPath $SkillsSrc -PathType Container) {
        Get-ChildItem -LiteralPath $SkillsSrc -Directory | ForEach-Object -Process {
            Invoke-LinkItem -SourcePath $_.FullName -DestinationPath (Join-Path -Path $SkillsDest -ChildPath $_.Name)
        }
    }

    Write-InfoMessage -Message ("Linking scripts -> {0}" -f $BinDest)
    if (Test-Path -LiteralPath $BinSrc -PathType Container) {
        Get-ChildItem -LiteralPath $BinSrc -Filter '*.ps1' -File | ForEach-Object -Process {
            Invoke-LinkItem -SourcePath $_.FullName -DestinationPath (Join-Path -Path $BinDest -ChildPath $_.Name)
        }
    }

    [Console]::Out.WriteLine()
    Write-InfoMessage -Message 'Done.'
    $pathEntries = ($env:PATH -split [System.IO.Path]::PathSeparator) | ForEach-Object -Process {
        Get-NormalizedFullPath -Path $_
    }
    if ((Get-NormalizedFullPath -Path $BinDest) -notin $pathEntries) {
        Write-WarningMessage -Message ("Note: {0} is not on your PATH. Add this to your PowerShell profile:" -f $BinDest)
        [Console]::Out.WriteLine('      $env:PATH = "$HOME/bin{0}$env:PATH"' -f [System.IO.Path]::PathSeparator)
    }
}

function Invoke-UninstallAll {
    Write-InfoMessage -Message ("Removing skill links from {0}" -f $SkillsDest)
    if (Test-Path -LiteralPath $SkillsSrc -PathType Container) {
        Get-ChildItem -LiteralPath $SkillsSrc -Directory | ForEach-Object -Process {
            Invoke-UnlinkItem -SourcePath $_.FullName -DestinationPath (Join-Path -Path $SkillsDest -ChildPath $_.Name)
        }
    }

    Write-InfoMessage -Message ("Removing script links from {0}" -f $BinDest)
    if (Test-Path -LiteralPath $BinSrc -PathType Container) {
        Get-ChildItem -LiteralPath $BinSrc -Filter '*.ps1' -File | ForEach-Object -Process {
            Invoke-UnlinkItem -SourcePath $_.FullName -DestinationPath (Join-Path -Path $BinDest -ChildPath $_.Name)
        }
    }

    [Console]::Out.WriteLine()
    Write-InfoMessage -Message 'Uninstalled. (Any *.bak backups were left untouched.)'
}

$Command = if ($args.Count -eq 0) { '' } else { $args[0] }

if ($args.Count -gt 1) {
    Write-ErrorMessage -Message ("Usage: {0} [--install | --uninstall]" -f $PSCommandPath)
    exit 1
}

switch ($Command) {
    { $_ -in @($null, '', '--install', '-i') } {
        Invoke-InstallAll
        break
    }
    { $_ -in @('--uninstall', '-u') } {
        Invoke-UninstallAll
        break
    }
    default {
        Write-ErrorMessage -Message ("Usage: {0} [--install | --uninstall]" -f $PSCommandPath)
        exit 1
    }
}
