<#
.SYNOPSIS
    Build and deploy this skill into Claude Desktop's local skills-plugin dir.

.DESCRIPTION
    SHARED SKELETON FILE — generic; no per-skill edits needed.

    1. Runs build.ps1 (auto-discovers the skill, validates name + version).
    2. Extracts the zip and reads the skill name from SKILL.md frontmatter.
    3. Locates the Claude Desktop skills-plugin target — auto-detects the
       nested <outer-guid>\<inner-guid>\skills\<skill-name>\ layout; falls
       back to %APPDATA%\Claude\local-agent-mode-sessions\skills-plugin\<name>\.
    4. Backs up the existing deployment (keeps last 5).
    5. Mirrors with robocopy /MIR, EXCLUDING data\ so the deployed cache,
       sessions, and credentials survive every redeploy.
    6. Optionally restarts Claude Desktop.

.PARAMETER DryRun
    Show what would happen without writing anything.
.PARAMETER RestartClaude
    Kill Claude Desktop and relaunch it after a successful deploy.
.PARAMETER SkipBackup
    Skip the pre-deploy backup.
#>
[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$RestartClaude,
    [switch]$SkipBackup
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:StartTime = Get-Date
$script:ProjectRoot = $PSScriptRoot
$script:TempDirs = New-Object System.Collections.Generic.List[string]

function Write-Step { param([string]$m) Write-Host "==> $m" -ForegroundColor Cyan }
function Write-Info { param([string]$m) Write-Host "    $m" -ForegroundColor Gray }
function Write-Ok   { param([string]$m) Write-Host "    $m" -ForegroundColor Green }
function Write-Warn { param([string]$m) Write-Host "    $m" -ForegroundColor Yellow }

function Cleanup-TempDirs {
    foreach ($d in $script:TempDirs) {
        if ($d -and (Test-Path -LiteralPath $d)) {
            try { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction Stop }
            catch { Write-Warn "Could not remove temp dir: $d" }
        }
    }
}

function Get-SkillDirName {
    $dirs = @(Get-ChildItem -LiteralPath $script:ProjectRoot -Directory |
        Where-Object { Test-Path (Join-Path $_.FullName 'SKILL.md') })
    if ($dirs.Count -ne 1) { throw "Expected exactly one SKILL.md-bearing directory; found $($dirs.Count)." }
    return $dirs[0].Name
}

function Invoke-ProjectBuild {
    $buildPs1 = Join-Path $script:ProjectRoot 'build.ps1'
    if (-not (Test-Path -LiteralPath $buildPs1)) { throw "build.ps1 not found." }
    Write-Step "Running build.ps1"
    if ($DryRun) { Write-Info "[dry-run] would invoke: pwsh $buildPs1"; return }
    $global:LASTEXITCODE = 0
    & $buildPs1
    $rc = $global:LASTEXITCODE
    if ($rc -and $rc -ne 0) { throw "build.ps1 failed with exit code $rc" }
}

function Resolve-BuildOutput {
    param([string]$SkillDirName)
    # DIVERGENCE FROM SKELETON: this repo's build.ps1 emits <name>.skill by
    # default (the Cowork package extension) and <name>.zip only with -Zip.
    # Accept either — both are ordinary zip archives. Candidate for porting
    # back to the skeleton.
    $zip = Join-Path $script:ProjectRoot "$SkillDirName.skill"
    if (-not (Test-Path -LiteralPath $zip)) {
        $zip = Join-Path $script:ProjectRoot "$SkillDirName.zip"
    }
    if (-not (Test-Path -LiteralPath $zip)) {
        if ($DryRun) { return (Join-Path $script:ProjectRoot $SkillDirName) }
        throw "Neither $SkillDirName.skill nor $SkillDirName.zip found after build."
    }
    $temp = Join-Path ([System.IO.Path]::GetTempPath()) ("skill-deploy-" + [Guid]::NewGuid().ToString('N'))
    $script:TempDirs.Add($temp)
    if ($DryRun) {
        Write-Info "[dry-run] would extract $zip to $temp"
        return (Join-Path $script:ProjectRoot $SkillDirName)
    }
    New-Item -ItemType Directory -Path $temp -Force | Out-Null
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::ExtractToDirectory($zip, $temp)
    if (Test-Path -LiteralPath (Join-Path $temp 'SKILL.md')) { return $temp }
    $skillDirs = @(Get-ChildItem -LiteralPath $temp -Directory |
        Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'SKILL.md') })
    if ($skillDirs.Count -eq 1) { return $skillDirs[0].FullName }
    throw "Could not locate SKILL.md inside the extracted zip."
}

function Get-SkillName {
    param([string]$SourceDir)
    $skillMd = Join-Path $SourceDir 'SKILL.md'
    if (-not (Test-Path -LiteralPath $skillMd)) { throw "SKILL.md not found at: $skillMd" }
    $content = Get-Content -LiteralPath $skillMd -Raw
    if ($content -notmatch '(?s)\A---\r?\n(.*?)\r?\n---') { throw "SKILL.md has no YAML frontmatter." }
    $frontmatter = $Matches[1]
    $name = $null
    foreach ($line in $frontmatter -split "`n") {
        if ($line -match '^\s*name\s*:\s*(.+?)\s*$') {
            $raw = $Matches[1].Trim()
            if (($raw.StartsWith('"') -and $raw.EndsWith('"')) -or
                ($raw.StartsWith("'") -and $raw.EndsWith("'"))) {
                $raw = $raw.Substring(1, $raw.Length - 2)
            }
            $name = $raw; break
        }
    }
    if ([string]::IsNullOrWhiteSpace($name)) { throw "SKILL.md frontmatter has no 'name:'." }
    if ($name -notmatch '^[A-Za-z0-9._\-]+$') { throw "Skill name '$name' unsafe for a directory name." }
    return $name
}

function Get-SkillDescription {
    param([string]$SourceDir)
    $content = Get-Content -LiteralPath (Join-Path $SourceDir 'SKILL.md') -Raw
    if ($content -notmatch '(?s)\A---\r?\n(.*?)\r?\n---') { return $null }
    $fm = $Matches[1]
    # Folded multi-line form: description: >  (indented continuation lines)
    if ($fm -match '(?sm)^description:\s*>?\s*\r?\n((?:[ \t]+\S.*\r?\n?)+)') {
        $lines = $Matches[1] -split "\r?\n" | ForEach-Object { $_.Trim() } | Where-Object { $_ }
        return ($lines -join ' ').Trim()
    }
    if ($fm -match '(?m)^description:\s*"?(.+?)"?\s*$') { return $Matches[1].Trim() }
    return $null
}

function Sync-SkillManifest {
    <#
      Claude Desktop only loads skills listed in manifest.json (sibling of the
      skills\ directory) — files alone are invisible. This registers the skill
      when missing and keeps the manifest description in sync with SKILL.md.
      A .bak of the manifest is written before any change.
    #>
    param([string]$TargetDir, [string]$SkillName, [string]$Description)
    $skillsDir = Split-Path -Parent $TargetDir
    $manifestPath = Join-Path (Split-Path -Parent $skillsDir) 'manifest.json'
    if (-not (Test-Path -LiteralPath $manifestPath)) {
        Write-Warn "No manifest.json next to the skills dir — Claude Desktop will NOT see this skill."
        Write-Warn "Install it once via Claude Desktop Settings > Capabilities > Skills (upload the zip)."
        return 'no-manifest'
    }
    if ($DryRun) {
        Write-Info "[dry-run] would sync manifest.json entry for '$SkillName'"
        return 'dry-run'
    }
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    $entry = @($manifest.skills) | Where-Object { $_.name -eq $SkillName } | Select-Object -First 1
    $now = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.ffffffZ')
    $changed = $false
    $action = 'unchanged'
    if ($entry) {
        # Server-registered? A skillId NOT prefixed skill_local_ means this
        # skill was uploaded via claude.ai Settings and is account-synced
        # (web + mobile + desktop all load the SERVER copy). Local file edits
        # do NOT change what loads — the user must RE-UPLOAD the zip.
        $script:ServerRegistered = ($entry.skillId -notlike 'skill_local_*')
        if ($Description -and $entry.description -ne $Description) {
            Copy-Item -LiteralPath $manifestPath "$manifestPath.bak" -Force
            $entry.description = $Description
            $entry.updatedAt = $now
            $changed = $true
            $action = 'description-updated'
        }
    } else {
        Copy-Item -LiteralPath $manifestPath "$manifestPath.bak" -Force
        $new = [pscustomobject]@{
            skillId     = "skill_local_$SkillName"
            name        = $SkillName
            description = $Description
            creatorType = 'user'
            updatedAt   = $now
            enabled     = $true
        }
        $manifest.skills = @($manifest.skills) + @($new)
        $changed = $true
        $action = 'registered'
        Write-Ok "Registered '$SkillName' in manifest.json (was missing — this is why a bare file copy is invisible)."
    }
    if ($changed) {
        $manifest.lastUpdated = [int64]([datetimeoffset](Get-Date)).ToUnixTimeMilliseconds()
        $manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
    }
    return $action
}

function Resolve-DeployTarget {
    param([string]$SkillName)
    $appdata = $env:APPDATA
    if ([string]::IsNullOrWhiteSpace($appdata)) { throw "APPDATA is not set." }
    $base = Join-Path $appdata 'Claude\local-agent-mode-sessions\skills-plugin'

    $existingHit = $null
    $anyManifestHit = $null
    if (Test-Path -LiteralPath $base -PathType Container) {
        $outers = @(Get-ChildItem -LiteralPath $base -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -ne '.backups' })
        foreach ($outer in $outers) {
            foreach ($inner in @(Get-ChildItem -LiteralPath $outer.FullName -Directory -ErrorAction SilentlyContinue)) {
                $skillsDir = Join-Path $inner.FullName 'skills'
                if (-not (Test-Path -LiteralPath $skillsDir -PathType Container)) { continue }
                if (-not $anyManifestHit) { $anyManifestHit = $skillsDir }
                $candidate = Join-Path $skillsDir $SkillName
                if (Test-Path -LiteralPath $candidate -PathType Container) { $existingHit = $candidate; break }
            }
            if ($existingHit) { break }
        }
    }
    if ($existingHit) {
        Write-Info "Detected existing deployment: $existingHit"
        return [pscustomobject]@{ Path = $existingHit; Layout = 'nested-existing' }
    }
    if ($anyManifestHit) {
        $target = Join-Path $anyManifestHit $SkillName
        Write-Info "Detected nested skills-plugin layout; new skill dir: $target"
        return [pscustomobject]@{ Path = $target; Layout = 'nested-new' }
    }
    $fallback = Join-Path $base $SkillName
    Write-Warn "No nested GUID layout found. Falling back to: $fallback"
    return [pscustomobject]@{ Path = $fallback; Layout = 'literal-fallback' }
}

function Backup-ExistingDeployment {
    param([string]$Target, [string]$SkillName)
    if ($SkipBackup) { Write-Info "Backup skipped (-SkipBackup)."; return $null }
    if (-not (Test-Path -LiteralPath $Target -PathType Container)) {
        Write-Info "Nothing to back up (target does not exist yet)."; return $null
    }
    $backupRoot = Join-Path $env:APPDATA 'Claude\local-agent-mode-sessions\skills-plugin\.backups'
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $backupDir = Join-Path $backupRoot ("{0}_{1}" -f $SkillName, $stamp)
    if ($DryRun) {
        Write-Info "[dry-run] would back up $Target -> $backupDir"
    } else {
        New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
        & robocopy @($Target, $backupDir, '/E', '/COPY:DAT', '/R:1', '/W:1', '/NFL', '/NDL', '/NP', '/NJH', '/NJS') | Out-Null
        $rc = $LASTEXITCODE
        $global:LASTEXITCODE = 0
        if ($rc -ge 8) { throw "Backup robocopy failed with exit code $rc" }
        Write-Ok "Backup created: $backupDir"
    }
    if (-not $DryRun -and (Test-Path -LiteralPath $backupRoot -PathType Container)) {
        $old = @(Get-ChildItem -LiteralPath $backupRoot -Directory -Filter ("$SkillName" + "_*") -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -Skip 5)
        foreach ($o in $old) {
            try { Remove-Item -LiteralPath $o.FullName -Recurse -Force -ErrorAction Stop; Write-Info "Pruned old backup: $($o.Name)" }
            catch { Write-Warn "Could not prune backup $($o.FullName)" }
        }
    }
    return $backupDir
}

function Invoke-Mirror {
    param([string]$Source, [string]$Target)
    if (-not $DryRun -and -not (Test-Path -LiteralPath $Target -PathType Container)) {
        New-Item -ItemType Directory -Path $Target -Force | Out-Null
    }
    # /XD data: never clobber the deployed skill's runtime data (cache,
    # session pickles, credentials) with the build's empty data/ dir.
    $rcArgs = @($Source, $Target, '/MIR', '/XD', 'data', '/COPY:DAT', '/R:2', '/W:2', '/NFL', '/NDL', '/NP')
    if ($DryRun) { $rcArgs += '/L' }
    Write-Step ("robocopy " + ($rcArgs -join ' '))
    $output = & robocopy @rcArgs
    $rc = $LASTEXITCODE
    $global:LASTEXITCODE = 0
    if ($rc -ge 8) {
        Write-Host ($output -join "`n") -ForegroundColor Red
        throw "robocopy failed with exit code $rc"
    }
    $targetData = Join-Path $Target 'data'
    if (-not $DryRun -and -not (Test-Path -LiteralPath $targetData)) {
        New-Item -ItemType Directory -Path $targetData -Force | Out-Null
    }
    $copied = 0; $removed = 0
    foreach ($line in $output) {
        if ($line -match '^\s*Files\s*:\s*(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s*$') {
            $copied = [int]$Matches[2]; $removed = [int]$Matches[6]
        }
    }
    return [pscustomobject]@{ ExitCode = $rc; Copied = $copied; Removed = $removed }
}

function Restart-ClaudeDesktop {
    Write-Step "Restarting Claude Desktop"
    $procs = @(Get-Process -Name 'Claude' -ErrorAction SilentlyContinue)
    if ($DryRun) { Write-Info "[dry-run] would restart Claude Desktop"; return }
    if ($procs.Count -gt 0) {
        $procs | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 750
        Write-Ok "Stopped Claude Desktop ($($procs.Count) process(es))"
    }
    $exe = Join-Path $env:LOCALAPPDATA 'AnthropicClaude\Claude.exe'
    if (-not (Test-Path -LiteralPath $exe)) { $exe = Join-Path $env:LOCALAPPDATA 'Programs\Claude\Claude.exe' }
    if (Test-Path -LiteralPath $exe) { Start-Process -FilePath $exe | Out-Null; Write-Ok "Launched: $exe" }
    else { Write-Warn "Could not find Claude.exe under %LOCALAPPDATA%." }
}

try {
    Write-Host ""
    Write-Host "=== Skill Deploy ===" -ForegroundColor Magenta
    if ($DryRun) { Write-Host "    (DRY RUN — no changes will be written)" -ForegroundColor Yellow }
    Write-Host ""

    $skillDirName = Get-SkillDirName
    Invoke-ProjectBuild
    $sourceDir = Resolve-BuildOutput -SkillDirName $skillDirName
    $skillName = Get-SkillName -SourceDir $sourceDir
    Write-Info "Skill name: $skillName"

    $script:ServerRegistered = $false
    $targetInfo = Resolve-DeployTarget -SkillName $skillName
    $targetDir = $targetInfo.Path
    $backupPath = Backup-ExistingDeployment -Target $targetDir -SkillName $skillName
    $mirror = Invoke-Mirror -Source $sourceDir -Target $targetDir
    $description = Get-SkillDescription -SourceDir $sourceDir
    $manifestAction = Sync-SkillManifest -TargetDir $targetDir -SkillName $skillName -Description $description
    $zipPath = Join-Path $script:ProjectRoot "$skillDirName.skill"
    if (-not (Test-Path -LiteralPath $zipPath)) { $zipPath = Join-Path $script:ProjectRoot "$skillDirName.zip" }
    if ($RestartClaude) { Restart-ClaudeDesktop }

    $elapsed = (Get-Date) - $script:StartTime
    Write-Host ""
    Write-Host "=== Deploy Summary ===" -ForegroundColor Magenta
    Write-Host ("  Skill name     : {0}" -f $skillName)
    Write-Host ("  Target         : {0}" -f $targetDir)
    Write-Host ("  Target layout  : {0}" -f $targetInfo.Layout)
    Write-Host ("  Files copied   : {0}" -f $mirror.Copied)
    Write-Host ("  Files removed  : {0}" -f $mirror.Removed)
    Write-Host ("  Manifest       : {0}" -f $manifestAction)
    Write-Host ("  Backup         : {0}" -f $(if ($backupPath) { $backupPath } else { '(none)' }))
    Write-Host ("  Server-synced  : {0}" -f $(if ($script:ServerRegistered) { 'YES — re-upload required (see below)' } else { 'no (local-only)' }))
    Write-Host ("  Elapsed        : {0:N1}s" -f $elapsed.TotalSeconds)
    Write-Host ""
    if ($DryRun) {
        Write-Host "Dry run complete." -ForegroundColor Yellow
    } elseif ($script:ServerRegistered) {
        Write-Host "⚠  THIS SKILL IS ACCOUNT/SERVER-SYNCED — local files are NOT what loads." -ForegroundColor Yellow
        Write-Host "   It was uploaded via claude.ai Settings, so web + mobile + desktop all" -ForegroundColor Yellow
        Write-Host "   load the SERVER copy. There is NO API to update it; you must re-upload:" -ForegroundColor Yellow
        Write-Host "     1. claude.ai (or Desktop) → Settings → Capabilities → Skills" -ForegroundColor Yellow
        Write-Host "     2. Remove the old '$skillName', then Upload a skill:" -ForegroundColor Yellow
        Write-Host "        $zipPath" -ForegroundColor Cyan
        Write-Host "   This updates ALL your devices (including phone). Restart afterward." -ForegroundColor Yellow
    } else {
        Write-Host "Deploy complete. Restart Claude Desktop to pick up changes." -ForegroundColor Green
        Write-Host "(For web/mobile access, upload $skillDirName.zip via Settings → Capabilities → Skills.)" -ForegroundColor Gray
    }
}
catch {
    Write-Host ""
    Write-Host "DEPLOY FAILED: $($_.Exception.Message)" -ForegroundColor Red
    Cleanup-TempDirs
    exit 1
}
finally {
    Cleanup-TempDirs
}
