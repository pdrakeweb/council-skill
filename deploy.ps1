<#
.SYNOPSIS
    Build the skill and deploy the package to the Dropbox skills directory.

.DESCRIPTION
    SHARED FILE — generic on purpose; it auto-discovers the single
    SKILL.md-bearing directory via build.ps1, so it needs no per-skill edits and
    can be copied verbatim between skill repos.

    1. Runs build.ps1 (which validates name, description, and both version
       stamps — a failed validation aborts the deploy, so a broken package can
       never reach the shared folder).
    2. Resolves the Dropbox skills directory (see -Destination).
    3. Backs up the currently-deployed package, keeping the most recent 5.
    4. Copies the new package in.

    The backups exist because Dropbox syncs deletions too: overwriting a good
    package with a broken one propagates to every device. A local backup is the
    fast way back.

.PARAMETER Destination
    Where to deploy. Defaults to <Dropbox>\Skills, with the Dropbox root read
    from %LOCALAPPDATA%\Dropbox\info.json so this keeps working if Dropbox is
    moved or the account changes.

.PARAMETER NoBackup
    Skip the backup rotation. Use for throwaway destinations.

.PARAMETER DryRun
    Print what would happen; write nothing.
#>
param(
    [string]$Destination,
    [switch]$NoBackup,
    [switch]$DryRun
)
$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

# --- resolve the destination --------------------------------------------------
if (-not $Destination) {
    $info = Join-Path $env:LOCALAPPDATA "Dropbox\info.json"
    if (-not (Test-Path $info)) {
        Write-Error "Dropbox not found (no $info). Pass -Destination explicitly."
        exit 1
    }
    $cfg = Get-Content $info -Raw | ConvertFrom-Json
    $root = $cfg.personal.path
    if (-not $root) { $root = $cfg.business.path }
    if (-not $root) { Write-Error "Could not read a Dropbox root from info.json."; exit 1 }
    $Destination = Join-Path $root "Skills"
}

if (-not (Test-Path $Destination)) {
    if ($DryRun) {
        Write-Host "[dry-run] would create $Destination"
    } else {
        New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    }
}

# --- build (validates; aborts the deploy on failure) --------------------------
# Reset first: a script that falls off its end leaves $LASTEXITCODE untouched,
# so without this we could read a stale non-zero from an earlier command and
# refuse to deploy a perfectly good build.
$global:LASTEXITCODE = 0
& (Join-Path $PSScriptRoot "build.ps1")
if ($LASTEXITCODE -ne 0) { Write-Error "Build failed — nothing deployed."; exit 1 }

$pkg = Get-ChildItem -Path $PSScriptRoot -Filter *.skill | Select-Object -First 1
if (-not $pkg) { Write-Error "No .skill package found after build."; exit 1 }

$target = Join-Path $Destination $pkg.Name

# --- back up the currently-deployed package, keep 5 ---------------------------
if ((Test-Path $target) -and -not $NoBackup) {
    $backupDir = Join-Path $Destination ".backups"
    $stamp = (Get-Item $target).LastWriteTime.ToString("yyyyMMdd-HHmmss")
    $backupName = "$($pkg.BaseName)-$stamp$($pkg.Extension)"
    if ($DryRun) {
        Write-Host "[dry-run] would back up existing package -> $backupDir\$backupName"
    } else {
        if (-not (Test-Path $backupDir)) { New-Item -ItemType Directory -Path $backupDir -Force | Out-Null }
        Copy-Item $target (Join-Path $backupDir $backupName) -Force
        Get-ChildItem $backupDir -Filter "$($pkg.BaseName)-*.skill" |
            Sort-Object LastWriteTime -Descending |
            Select-Object -Skip 5 |
            Remove-Item -Force -ErrorAction SilentlyContinue
    }
}

# --- deploy -------------------------------------------------------------------
if ($DryRun) {
    Write-Host "[dry-run] would copy $($pkg.Name) -> $target"
    exit 0
}

Copy-Item $pkg.FullName $target -Force
$deployed = Get-Item $target
Write-Host "Deployed: $($deployed.FullName) ($($deployed.Length) bytes)"
Write-Host "Dropbox will sync it; upload from there via Settings -> Capabilities -> Skills."
