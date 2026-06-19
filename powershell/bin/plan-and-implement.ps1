#!/usr/bin/env pwsh
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseBOMForUnicodeEncodedFile', '', Justification = 'UTF-8 without BOM preserves Unix shebang execution while parity messages intentionally contain Unicode text.')]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptName = if ([string]::IsNullOrEmpty($MyInvocation.InvocationName)) { $PSCommandPath } else { $MyInvocation.InvocationName }
$WorkDir = $null
$KeepAwakeActive = $false
$ContinuousState = [uint32]2147483648

function Write-ErrorLine {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string] $Message
    )

    [Console]::Error.WriteLine($Message)
}

function Invoke-Usage {
    Write-ErrorLine -Message "Usage: $ScriptName ""<request prompt>""   (or pipe the prompt via stdin)"
    exit 1
}

function Get-EnvOrDefault {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Name,

        [Parameter(Mandatory = $true)]
        [string] $DefaultValue
    )

    $Value = [Environment]::GetEnvironmentVariable($Name)
    if ([string]::IsNullOrEmpty($Value)) {
        return $DefaultValue
    }

    return $Value
}

function Initialize-KeepAwake {
    param(
        [Parameter(Mandatory = $true)]
        [uint32] $Continuous
    )

    if (-not [string]::IsNullOrEmpty($env:NO_CAFFEINATE)) {
        return $false
    }

    if (-not $IsWindows) {
        Write-ErrorLine -Message '>>> keep-awake skipped (not Windows).'
        return $false
    }

    try {
        if (-not ('ExecutionStateNativeMethods' -as [type])) {
            Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class ExecutionStateNativeMethods
{
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern uint SetThreadExecutionState(uint esFlags);
}
'@
        }

        $SystemRequired = [uint32]1
        $Result = [ExecutionStateNativeMethods]::SetThreadExecutionState([uint32]($Continuous -bor $SystemRequired))
        return ($Result -ne 0)
    }
    catch {
        Write-ErrorLine -Message ">>> keep-awake skipped: $($_.Exception.Message)"
        return $false
    }
}

function Invoke-KeepAwakeReset {
    param(
        [Parameter(Mandatory = $true)]
        [uint32] $Continuous
    )

    [void][ExecutionStateNativeMethods]::SetThreadExecutionState($Continuous)
}

function Initialize-WorkDirectory {
    $DirectoryName = 'aid-devkit-' + [guid]::NewGuid().ToString('N')
    $DirectoryPath = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), $DirectoryName)
    New-Item -ItemType Directory -Path $DirectoryPath -Force | Out-Null
    return $DirectoryPath
}

function Test-FileHasContent {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path
    )

    return (Test-Path -LiteralPath $Path -PathType Leaf) -and ((Get-Item -LiteralPath $Path).Length -gt 0)
}

function Get-LastFencedBlock {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path
    )

    $InBlock = $false
    $Buffer = [System.Text.StringBuilder]::new()
    $Last = ''

    foreach ($Line in [System.IO.File]::ReadLines($Path)) {
        if ($Line.StartsWith('```')) {
            if ($InBlock) {
                $InBlock = $false
                $Last = $Buffer.ToString()
                [void]$Buffer.Clear()
            }
            else {
                $InBlock = $true
                [void]$Buffer.Clear()
            }

            continue
        }

        if ($InBlock) {
            [void]$Buffer.Append($Line)
            [void]$Buffer.Append([char]10)
        }
    }

    return $Last
}

function Get-LineFeedCount {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string] $Text
    )

    return ([regex]::Matches($Text, [string][char]10)).Count
}

$KeepAwakeActive = Initialize-KeepAwake -Continuous $ContinuousState

try {
    $Prompt = ''
    if ($args.Count -gt 0) {
        $Prompt = $args[0]
    }
    elseif ([Console]::IsInputRedirected) {
        $Prompt = [Console]::In.ReadToEnd()
    }

    if ([string]::IsNullOrEmpty($Prompt)) {
        Invoke-Usage
    }

    if ($null -eq (Get-Command -Name copilot -ErrorAction SilentlyContinue)) {
        Write-ErrorLine -Message 'ERROR: copilot CLI not found in PATH'
        exit 1
    }

    $RepoDir = Get-EnvOrDefault -Name 'REPO_DIR' -DefaultValue $PWD.ProviderPath
    $PlanFile = Get-EnvOrDefault -Name 'PLAN_FILE' -DefaultValue 'IMPLEMENTATION_PLAN.md'
    $ManualActionsFile = Get-EnvOrDefault -Name 'MANUAL_ACTIONS_FILE' -DefaultValue 'MANUAL_ACTIONS.md'
    $PlanModel = Get-EnvOrDefault -Name 'PLAN_MODEL' -DefaultValue 'claude-opus-4.8'
    $PlanEffort = Get-EnvOrDefault -Name 'PLAN_EFFORT' -DefaultValue 'max'
    $PlanContext = Get-EnvOrDefault -Name 'PLAN_CONTEXT' -DefaultValue 'long_context'
    $ImplModel = Get-EnvOrDefault -Name 'IMPL_MODEL' -DefaultValue 'gpt-5.5'
    $ImplEffort = Get-EnvOrDefault -Name 'IMPL_EFFORT' -DefaultValue 'xhigh'
    $ImplContext = Get-EnvOrDefault -Name 'IMPL_CONTEXT' -DefaultValue 'long_context'

    $ImplExtra = @()
    if (-not [string]::IsNullOrEmpty($env:IMPL_MAX_CONTINUES)) {
        $ImplExtra = @('--max-autopilot-continues', $env:IMPL_MAX_CONTINUES)
    }

    $WorkDir = Initialize-WorkDirectory
    $HandoffFile = [System.IO.Path]::Combine($WorkDir, 'handoff-prompt.txt')
    $PlannerOut = [System.IO.Path]::Combine($WorkDir, 'planner.out')

    $CommonFlags = @('--autopilot', '--yolo', '--no-ask-user', '--no-color', '-C', $RepoDir)
    $PlanFlags = @('--model', $PlanModel, '--effort', $PlanEffort, '--context', $PlanContext)
    $ImplFlags = @('--model', $ImplModel, '--effort', $ImplEffort, '--context', $ImplContext)

    Write-ErrorLine -Message '>>> [1/2] Planning with the implementation-planner skill ...'
    $Lf = [string][char]10
    $PlanPrompt = @(
        'Use the implementation-planner skill to produce a spec-grade implementation plan for the request below.'
        'Save the plan to ' + $PlanFile + ' (relative to the repo root).'
        'Then write ONLY the final handoff prompt (the exact text meant for the implementing agent, with NO surrounding code fence) to this absolute path: ' + $HandoffFile
        'If the request requires any human-only actions in an environment an agent cannot reach (prod/staging secrets or env vars, dashboards, DNS, third-party consoles, one-off prod migrations/backfills), record them in a root ' + $ManualActionsFile + ' ledger.'
        'Do NOT write or modify any other code and do NOT create branches; only produce the plan file, the ' + $ManualActionsFile + ' ledger (only if such actions exist), and the handoff file, then stop.'
        ''
        'Request:'
        $Prompt
    ) -join $Lf

    & copilot @CommonFlags @PlanFlags -s -p $PlanPrompt | Tee-Object -FilePath $PlannerOut
    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }

    if (-not (Test-FileHasContent -Path $HandoffFile)) {
        Write-ErrorLine -Message '>>> Handoff file empty; extracting last fenced block from planner output ...'
        [System.IO.File]::WriteAllText($HandoffFile, (Get-LastFencedBlock -Path $PlannerOut))
    }

    if (-not (Test-FileHasContent -Path $HandoffFile)) {
        Write-ErrorLine -Message 'ERROR: could not obtain a handoff prompt from the planning session.'
        exit 2
    }

    $Handoff = [System.IO.File]::ReadAllText($HandoffFile)
    $HandoffForPrompt = $Handoff.TrimEnd([char[]]"`r`n")
    $HandoffLineCount = Get-LineFeedCount -Text $Handoff
    Write-ErrorLine -Message ">>> Handoff prompt captured ($HandoffLineCount lines)."

    Write-ErrorLine -Message '>>> [2/2] Implementing with the plan-implementer skill ...'
    $ImplPrompt = @(
        'Use the plan-implementer skill to execute the following implementation-plan handoff to completion. Do all work on a new branch, and verify + commit after each wave, pushing after every 3 commits. Record any human-only/out-of-band actions (prod secrets or env vars, dashboards, DNS, one-off prod migrations) in a root ' + $ManualActionsFile + ' ledger and keep the code safe without them instead of blocking.'
        ''
        $HandoffForPrompt
    ) -join $Lf

    & copilot @CommonFlags @ImplFlags @ImplExtra -p $ImplPrompt
    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }

    $ManualActionsPath = Join-Path -Path $RepoDir -ChildPath $ManualActionsFile
    if (Test-FileHasContent -Path $ManualActionsPath) {
        Write-ErrorLine -Message ''
        Write-ErrorLine -Message '############################################################'
        Write-ErrorLine -Message '##  ACTION REQUIRED — manual/human steps are pending      ##'
        Write-ErrorLine -Message "##  see $ManualActionsFile (contents below)"
        Write-ErrorLine -Message '############################################################'
        [Console]::Error.Write([System.IO.File]::ReadAllText($ManualActionsPath))
        Write-ErrorLine -Message '############################################################'
    }

    Write-ErrorLine -Message ">>> Done. Plan saved at: $RepoDir/$PlanFile"
}
finally {
    if ($null -ne $WorkDir -and (Test-Path -LiteralPath $WorkDir)) {
        Remove-Item -LiteralPath $WorkDir -Recurse -Force
    }

    if ($KeepAwakeActive) {
        Invoke-KeepAwakeReset -Continuous $ContinuousState
    }
}
