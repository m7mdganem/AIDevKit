#!/usr/bin/env pwsh
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseBOMForUnicodeEncodedFile', '', Justification = 'UTF-8 without BOM preserves Unix shebang execution while parity prompts and banners intentionally contain Unicode text.')]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$script:ScriptName = if ([string]::IsNullOrEmpty($PSCommandPath)) { $MyInvocation.MyCommand.Name } else { $PSCommandPath }

function Write-ErrorLine {
    param([Parameter(Mandatory = $true)][string]$Message)
    [Console]::Error.WriteLine($Message)
}

function Write-OutText {
    param([Parameter(Mandatory = $true)][string]$Text)
    [Console]::Out.Write($Text)
}

function Write-OutLine {
    param([Parameter(Mandatory = $true)][string]$Message)
    [Console]::Out.WriteLine($Message)
}

function Show-Usage {
    Write-ErrorLine -Message ('Usage: {0} "<feature to discuss>"   (or run with no args to be prompted)' -f $script:ScriptName)
    exit 1
}

function Test-FileHasContent {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $false
    }

    $item = Get-Item -LiteralPath $Path
    return $item.Length -gt 0
}

function Get-RequiredEnvValue {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$DefaultValue
    )

    $value = [Environment]::GetEnvironmentVariable($Name)
    if ([string]::IsNullOrEmpty($value)) {
        return $DefaultValue
    }

    return $value
}

function Get-OptionalEnvValue {
    param([Parameter(Mandatory = $true)][string]$Name)
    return [Environment]::GetEnvironmentVariable($Name)
}

function Get-PlanScriptPath {
    $override = Get-OptionalEnvValue -Name 'PLAN_IMPL_SCRIPT'
    if (-not [string]::IsNullOrEmpty($override)) {
        return $override
    }

    $command = Get-Command -Name 'plan-and-implement.ps1' -ErrorAction SilentlyContinue
    if ($null -ne $command) {
        return $command.Source
    }

    return Join-Path -Path $PSScriptRoot -ChildPath 'plan-and-implement.ps1'
}

function Initialize-SessionWorkDirectory {
    $path = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ([guid]::NewGuid().ToString())
    $null = New-Item -Path $path -ItemType Directory -Force
    return $path
}

function Get-LastFencedBlock {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return ''
    }

    $inBlock = $false
    $current = [System.Collections.Generic.List[string]]::new()
    $last = ''

    foreach ($line in Get-Content -LiteralPath $Path) {
        if ($line.StartsWith('```')) {
            if ($inBlock) {
                $inBlock = $false
                $last = ($current -join [Environment]::NewLine) + [Environment]::NewLine
                $current.Clear()
            }
            else {
                $inBlock = $true
                $current.Clear()
            }
            continue
        }

        if ($inBlock) {
            $current.Add($line)
        }
    }

    return $last
}

function Read-ConsoleLineWithPrompt {
    param([Parameter(Mandatory = $true)][string]$Prompt)

    Write-OutText -Text $Prompt
    $line = [Console]::In.ReadLine()
    if ($null -eq $line) {
        return ''
    }

    return $line
}

if ($null -eq (Get-Command -Name 'copilot' -ErrorAction SilentlyContinue)) {
    Write-ErrorLine -Message 'ERROR: copilot CLI not found in PATH'
    exit 1
}

$RepoDir = Get-RequiredEnvValue -Name 'REPO_DIR' -DefaultValue ((Get-Location).Path)
$DiscussModel = Get-RequiredEnvValue -Name 'DISCUSS_MODEL' -DefaultValue 'claude-opus-4.8'
$DefineModel = Get-RequiredEnvValue -Name 'DEFINE_MODEL' -DefaultValue 'claude-opus-4.8'
$DiscussEffort = Get-OptionalEnvValue -Name 'DISCUSS_EFFORT'
$PlanImplScript = Get-PlanScriptPath

$Prompt = if ($args.Count -gt 0) { [string]$args[0] } else { '' }
if ([Console]::IsInputRedirected) {
    Write-ErrorLine -Message 'ERROR: discuss-and-implement.sh needs an interactive terminal for the discussion.'
    Write-ErrorLine -Message '       Run it in a terminal and pass the feature as an argument, e.g.:'
    Write-ErrorLine -Message ('       {0} "Add CSV export to the reports page"' -f $script:ScriptName)
    exit 1
}

if ([string]::IsNullOrEmpty($Prompt)) {
    $Prompt = Read-ConsoleLineWithPrompt -Prompt "`e[1;36mWhat feature do you want to discuss and implement?`e[0m`n> "
}

if ([string]::IsNullOrWhiteSpace($Prompt)) {
    Write-ErrorLine -Message 'ERROR: no feature provided.'
    Show-Usage
}

$Sid = [guid]::NewGuid().ToString()
$WorkDir = Initialize-SessionWorkDirectory
$HandoffFile = Join-Path -Path $WorkDir -ChildPath 'handoff-prompt.txt'
$DefinerOut = Join-Path -Path $WorkDir -ChildPath 'definer.out'

try {
    $Bold = "`e[1m"
    $Reset = "`e[0m"
    $Pink = "`e[1;38;5;205m"
    $Cyan = "`e[1;38;5;51m"
    $Yel = "`e[1;38;5;226m"
    $Grn = "`e[1;38;5;46m"
    $Rule = '════════════════════════════════════════════════════════════════'

    Write-OutLine -Message ''
    Write-OutLine -Message ('{0}{1}{2}' -f $Pink, $Rule, $Reset)
    Write-OutLine -Message ('{0}  🎙  FEATURE DISCUSSION SESSION{1}' -f $Cyan, $Reset)
    Write-OutLine -Message ('{0}{1}{2}' -f $Pink, $Rule, $Reset)
    Write-OutLine -Message ''
    Write-OutLine -Message ('  {0}Let''s flesh this out together:{1}' -f $Bold, $Reset)
    Write-OutLine -Message ('  {0}{1}{2}' -f $Yel, $Prompt, $Reset)
    Write-OutLine -Message ''
    Write-OutLine -Message '  Discuss freely — Copilot will ask questions and explore the repo.'
    Write-OutLine -Message ('  {0}When you''ve reached a decision, press Ctrl-D{1} to lock it in.' -f $Grn, $Reset)
    Write-OutLine -Message '  The feature definition is then written and planning + implementation start automatically.'
    Write-OutLine -Message ('{0}{1}{2}' -f $Pink, $Rule, $Reset)
    Write-OutLine -Message ''
    $null = Read-ConsoleLineWithPrompt -Prompt '  Press Enter to start the discussion… '

    $SeedPrefix = @'
Use the feature-discovery skill to run an interactive feature-discovery discussion with me — you are the conversational front end of the discuss-and-implement pipeline.

Feature to explore:
'@
    $SeedSuffix = @'
Investigate this repository as needed to ground the conversation, ask me focused questions, surface the key decisions, tradeoffs, and edge cases, and converge on a clear, complete shared understanding. Do NOT write or edit any files and do NOT invoke other skills or start implementing — the discussion itself is the deliverable. When you believe we have reached a clear decision, give me a concise recap of everything we have agreed and remind me that pressing Ctrl-D will lock it in: that ends this session, after which the feature definition will be written from our conversation and planning + implementation will start automatically.
'@
    $Seed = $SeedPrefix.TrimEnd([char[]]"`r`n") + ' ' + $Prompt + "`n`n" + $SeedSuffix.TrimEnd([char[]]"`r`n")

    Write-ErrorLine -Message ">>> [1/3] Discussion — talk it through, then press Ctrl-D when you've decided."

    $DiscussFlags = @('--allow-all-tools', '-C', $RepoDir, '--session-id', $Sid)
    if (-not [string]::IsNullOrEmpty($DiscussModel)) {
        $DiscussFlags += @('--model', $DiscussModel)
    }
    if (-not [string]::IsNullOrEmpty($DiscussEffort)) {
        $DiscussFlags += @('--effort', $DiscussEffort)
    }

    & copilot -i $Seed @DiscussFlags

    Write-ErrorLine -Message '>>> [2/3] Writing the feature definition from our discussion ...'
    $DefPromptPrefix = @'
Use the feature-definer skill to capture the feature we just discussed in this very session.
Write the full, agreed feature definition to a NEW Markdown file under docs/features/ in this repo (choose a descriptive kebab-case filename), reflecting every decision from our conversation; create the docs/features directory if it does not exist.
Then write ONLY the exact handoff prompt for the plan-and-implement pipeline (the copy-paste text that points at that definition file as the source of truth) to this absolute path, with NO surrounding code fence:
'@
    $DefPromptSuffix = @'
Do not modify any other code and do not create branches; only create the definition file and write the handoff file, then stop.
'@
    $DefPrompt = $DefPromptPrefix.TrimEnd([char[]]"`r`n") + ' ' + $HandoffFile + "`n" + $DefPromptSuffix.TrimEnd([char[]]"`r`n")

    $DefineFlags = @('-s', '--no-color', '--allow-all-tools', '--no-ask-user', '-C', $RepoDir, '--session-id', $Sid)
    if (-not [string]::IsNullOrEmpty($DefineModel)) {
        $DefineFlags += @('--model', $DefineModel)
    }

    & copilot -p $DefPrompt @DefineFlags | Tee-Object -FilePath $DefinerOut
    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }

    if (-not (Test-FileHasContent -Path $HandoffFile)) {
        Write-ErrorLine -Message '>>> Handoff file empty; extracting the last fenced block from the definer output ...'
        $lastFencedBlock = Get-LastFencedBlock -Path $DefinerOut
        Set-Content -LiteralPath $HandoffFile -Value $lastFencedBlock -NoNewline
    }

    if (-not (Test-FileHasContent -Path $HandoffFile)) {
        Write-ErrorLine -Message 'ERROR: no feature definition / handoff was produced. Did the discussion end before reaching a decision?'
        exit 2
    }

    Write-ErrorLine -Message ''
    Write-ErrorLine -Message '>>> Feature definition written. Handoff prompt for plan-and-implement:'
    foreach ($line in Get-Content -LiteralPath $HandoffFile) {
        Write-ErrorLine -Message ('    {0}' -f $line)
    }
    Write-ErrorLine -Message ''

    if (-not [string]::IsNullOrEmpty((Get-OptionalEnvValue -Name 'NO_LAUNCH'))) {
        Write-ErrorLine -Message '>>> NO_LAUNCH set — stopping after the definition. The definition file is saved in the repo;'
        Write-ErrorLine -Message "    pass the handoff prompt above to plan-and-implement.sh when you're ready."
        exit 0
    }

    if ([string]::IsNullOrEmpty((Get-OptionalEnvValue -Name 'AUTO_LAUNCH'))) {
        $answer = Read-ConsoleLineWithPrompt -Prompt '>>> Launch plan-and-implement now? [Y/n] '
        if ($answer -match '^[Nn]') {
            Write-ErrorLine -Message '>>> Stopped before implementation. The definition is saved in the repo; re-run'
            Write-ErrorLine -Message '    plan-and-implement.sh with the handoff prompt above when ready.'
            exit 0
        }
    }

    Write-ErrorLine -Message '>>> [3/3] Handing off to plan-and-implement.ps1 ...'
    if (-not (Test-Path -LiteralPath $PlanImplScript -PathType Leaf)) {
        Write-ErrorLine -Message ('ERROR: plan-and-implement script not found at: {0}' -f $PlanImplScript)
        Write-ErrorLine -Message '       Set PLAN_IMPL_SCRIPT=/path/to/plan-and-implement.ps1 and retry.'
        exit 1
    }

    $Handoff = ([System.IO.File]::ReadAllText($HandoffFile)).TrimEnd([char[]]"`r`n")
    $previousRepoDir = Get-OptionalEnvValue -Name 'REPO_DIR'
    try {
        $env:REPO_DIR = $RepoDir
        & pwsh -NoProfile -File $PlanImplScript $Handoff
        exit $LASTEXITCODE
    }
    finally {
        if ($null -eq $previousRepoDir) {
            [Environment]::SetEnvironmentVariable('REPO_DIR', $null, 'Process')
        }
        else {
            $env:REPO_DIR = $previousRepoDir
        }
    }
}
finally {
    if (Test-Path -LiteralPath $WorkDir) {
        Remove-Item -LiteralPath $WorkDir -Recurse -Force
    }
}
