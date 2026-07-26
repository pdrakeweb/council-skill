<#
.SYNOPSIS
    Package the skill into <skill-name>.skill (Cowork / claude.ai upload format).

.DESCRIPTION
    Derived from claude-skill-skeleton's build.ps1, with one deliberate
    divergence: this is a pure-Markdown skill with no Python CLI, so the second
    version stamp lives in <skill>/VERSION instead of scripts/skill_schema.py.
    Everything else — auto-discovery of the SKILL.md-bearing directory, name /
    description / version validation, empty data/ — follows the skeleton so
    future skeleton improvements merge cleanly.

    1. Discovers the skill dir (exactly one top-level dir containing SKILL.md).
    2. Validates SKILL.md frontmatter `name:` equals the folder name and obeys
       Anthropic's naming rules.
    3. Validates `description:` is present and <= 1024 chars.
    4. Validates frontmatter `version:` matches SKILL_VERSION in <skill>/VERSION.
    5. Stages a copy with an EMPTY data/, zips it as <skill>.skill.

.PARAMETER Zip
    Also emit <skill>.zip alongside <skill>.skill (identical bytes). Some
    upload paths expect the .zip extension.
#>
param([switch]$Zip)
$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

# --- discover the skill directory --------------------------------------------
$skillDirs = @(Get-ChildItem -Directory | Where-Object {
    Test-Path (Join-Path $_.FullName "SKILL.md") })
if ($skillDirs.Count -ne 1) {
    Write-Error "Expected exactly one SKILL.md-bearing directory; found $($skillDirs.Count)."
    exit 1
}
$skillDir = $skillDirs[0].Name
$outName = "$skillDir.skill"

# --- validate folder name matches SKILL.md frontmatter -----------------------
$nameMatch = Select-String -Path "$skillDir\SKILL.md" -Pattern '^name:\s+"?([^"\s]+)"?'
if (-not $nameMatch) { Write-Error "Could not read 'name:' from $skillDir\SKILL.md"; exit 1 }
$skillName = $nameMatch.Matches[0].Groups[1].Value.Trim()
if ($skillName -ne $skillDir) {
    Write-Error "SKILL.md name '$skillName' does not match folder '$skillDir'"
    exit 1
}
if ($skillName.Length -gt 64) { Write-Error "Skill name exceeds 64 chars."; exit 1 }
if ($skillName -cnotmatch '^[a-z0-9-]+$') {
    Write-Error "Skill name '$skillName' must be lowercase letters, digits, hyphens only."
    exit 1
}
if ($skillName -match '(?i)\b(claude|anthropic)\b') {
    Write-Error "Skill name '$skillName' uses a reserved word (claude/anthropic)."
    exit 1
}

# --- description present and <= 1024 chars ------------------------------------
$fmLines = Get-Content "$skillDir\SKILL.md"
$descRest = ""
$inDesc = $false
foreach ($l in $fmLines) {
    if ($l -match '^description:\s*(.*)$') { $inDesc = $true; $descRest += $Matches[1]; continue }
    if ($inDesc) {
        if ($l -match '^\s+\S') { $descRest += " " + $l.Trim() } else { break }
    }
}
if ([string]::IsNullOrWhiteSpace($descRest.Replace('>', '').Trim())) {
    Write-Error "SKILL.md frontmatter description is empty."
    exit 1
}
if ($descRest.Length -gt 1024) {
    Write-Error "SKILL.md description exceeds 1024 chars ($($descRest.Length))."
    exit 1
}

# --- validate frontmatter version matches the VERSION stamp -------------------
$mdVerMatch = Select-String -Path "$skillDir\SKILL.md" -Pattern '^version:\s+"?([0-9]+\.[0-9]+\.[0-9]+)"?'
$fileVerMatch = Select-String -Path "$skillDir\VERSION" -Pattern 'SKILL_VERSION\s*=\s*"([0-9]+\.[0-9]+\.[0-9]+)"'
if (-not $mdVerMatch -or -not $fileVerMatch) {
    Write-Error "Missing version: in SKILL.md frontmatter or SKILL_VERSION in $skillDir\VERSION"
    exit 1
}
$mdVer = $mdVerMatch.Matches[0].Groups[1].Value
$fileVer = $fileVerMatch.Matches[0].Groups[1].Value
if ($mdVer -ne $fileVer) {
    Write-Error "Version mismatch: SKILL.md says $mdVer, VERSION says $fileVer. Bump both (see CLAUDE.md)."
    exit 1
}

if (Test-Path $outName) { Remove-Item $outName -Force }

# --- stage to temp so data/ ships empty ---------------------------------------
$tmp = Join-Path $env:TEMP "skill_build_$(Get-Random)"
New-Item $tmp -ItemType Directory | Out-Null
$stage = Join-Path $tmp $skillDir
Copy-Item $skillDir $stage -Recurse

$dataDir = Join-Path $stage "data"
if (Test-Path $dataDir) {
    Remove-Item "$dataDir\*" -Recurse -Force -ErrorAction SilentlyContinue
} else {
    New-Item $dataDir -ItemType Directory | Out-Null
}
"This directory is created at runtime (logs). Ships empty." |
    Set-Content -Path (Join-Path $dataDir ".gitkeep")

Add-Type -AssemblyName System.IO.Compression.FileSystem
$dest = (Join-Path (Resolve-Path .).Path $outName)
[System.IO.Compression.ZipFile]::CreateFromDirectory($tmp, $dest)
Remove-Item $tmp -Recurse -Force

if ($Zip) { Copy-Item $outName "$skillDir.zip" -Force }

$size = (Get-Item $outName).Length
Write-Host "Built: $outName v$mdVer ($size bytes)"
if ($Zip) { Write-Host "Built: $skillDir.zip (copy)" }
