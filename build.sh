#!/usr/bin/env bash
#
# Package the skill into <skill-name>.skill (Cowork / claude.ai upload format).
#
# POSIX counterpart to build.ps1 — same validations, same output, so a build on
# macOS/Linux/Git-Bash is byte-equivalent to a build on Windows PowerShell.
#
# SHARED SKELETON-STYLE FILE — generic on purpose; it auto-discovers the single
# SKILL.md-bearing directory, so it needs no per-skill edits and can be copied
# verbatim between skill repos.
#
#   1. Discovers the skill dir (exactly one top-level dir containing SKILL.md).
#   2. Validates SKILL.md frontmatter `name:` equals the folder name and obeys
#      Anthropic's naming rules.
#   3. Validates `description:` is present and <= 1024 chars.
#   4. Validates frontmatter `version:` matches SKILL_VERSION in <skill>/VERSION.
#   5. Stages a copy with an EMPTY data/, zips it as <skill>.skill.
#
# Usage:
#   ./build.sh          # -> <skill>.skill
#   ./build.sh --zip    # -> <skill>.skill and <skill>.zip (identical bytes)

set -euo pipefail
cd "$(dirname "$0")"

EMIT_ZIP=0
for arg in "$@"; do
    case "$arg" in
        --zip) EMIT_ZIP=1 ;;
        *) echo "Unknown argument: $arg" >&2; exit 1 ;;
    esac
done

die() { echo "ERROR: $*" >&2; exit 1; }

# Find a Python that actually RUNS. On Windows, `python3` on PATH is usually the
# Microsoft Store alias stub: it resolves under `command -v` but exits non-zero
# with a "not found, install from the Store" message. So probe each candidate
# instead of trusting the name to resolve.
find_python() {
    local c
    for c in python3 python py; do
        if command -v "$c" >/dev/null 2>&1 && "$c" -c 'import zipfile' >/dev/null 2>&1; then
            printf '%s' "$c"
            return 0
        fi
    done
    return 1
}

# --- discover the skill directory --------------------------------------------
skill_dir=""
count=0
for d in */; do
    d="${d%/}"
    if [ -f "$d/SKILL.md" ]; then
        skill_dir="$d"
        count=$((count + 1))
    fi
done
[ "$count" -eq 1 ] || die "Expected exactly one SKILL.md-bearing directory; found $count."

out_name="$skill_dir.skill"

# --- validate folder name matches SKILL.md frontmatter -----------------------
skill_name=$(sed -n 's/^name:[[:space:]]*"\{0,1\}\([^"[:space:]]*\)"\{0,1\}[[:space:]]*$/\1/p' \
    "$skill_dir/SKILL.md" | head -1)
[ -n "$skill_name" ] || die "Could not read 'name:' from $skill_dir/SKILL.md"
[ "$skill_name" = "$skill_dir" ] || \
    die "SKILL.md name '$skill_name' does not match folder '$skill_dir'"
[ "${#skill_name}" -le 64 ] || die "Skill name exceeds 64 chars."
printf '%s' "$skill_name" | grep -qE '^[a-z0-9-]+$' || \
    die "Skill name '$skill_name' must be lowercase letters, digits, hyphens only."
printf '%s' "$skill_name" | grep -qiE '(claude|anthropic)' && \
    die "Skill name '$skill_name' uses a reserved word (claude/anthropic)."

# --- description present and <= 1024 chars ------------------------------------
# Folded scalar: gather the description line plus indented continuation lines.
desc=$(awk '
    /^description:[[:space:]]*/ { sub(/^description:[[:space:]]*/, ""); buf = $0; found = 1; next }
    found { if ($0 ~ /^[[:space:]]+[^[:space:]]/) { sub(/^[[:space:]]+/, ""); buf = buf " " $0 } else { exit } }
    END { print buf }
' "$skill_dir/SKILL.md")
desc_clean=$(printf '%s' "$desc" | tr -d '>' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
[ -n "$desc_clean" ] || die "SKILL.md frontmatter description is empty."
[ "${#desc}" -le 1024 ] || die "SKILL.md description exceeds 1024 chars (${#desc})."

# --- validate frontmatter version matches the VERSION stamp -------------------
md_ver=$(sed -n 's/^version:[[:space:]]*"\{0,1\}\([0-9]\+\.[0-9]\+\.[0-9]\+\)"\{0,1\}.*$/\1/p' \
    "$skill_dir/SKILL.md" | head -1)
file_ver=$(sed -n 's/.*SKILL_VERSION[[:space:]]*=[[:space:]]*"\([0-9]\+\.[0-9]\+\.[0-9]\+\)".*/\1/p' \
    "$skill_dir/VERSION" 2>/dev/null | head -1)
[ -n "$md_ver" ] && [ -n "$file_ver" ] || \
    die "Missing version: in SKILL.md frontmatter or SKILL_VERSION in $skill_dir/VERSION"
[ "$md_ver" = "$file_ver" ] || \
    die "Version mismatch: SKILL.md says $md_ver, VERSION says $file_ver. Bump both (see CLAUDE.md)."

rm -f "$out_name"

# --- stage to temp so data/ ships empty ---------------------------------------
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cp -R "$skill_dir" "$tmp/$skill_dir"

find "$tmp/$skill_dir" -type d -name '__pycache__' -exec rm -rf {} + 2>/dev/null || true

data_dir="$tmp/$skill_dir/data"
rm -rf "$data_dir"
mkdir -p "$data_dir"
echo "This directory is created at runtime (logs). Ships empty." > "$data_dir/.gitkeep"

# Zip via whatever this machine actually has. `zip` is absent from a default
# Git-Bash install on Windows, and Python's zipfile module is the most reliable
# fallback there (the skeleton already assumes Python is present). All three
# produce an archive with the skill folder as the top-level entry.
dest="$PWD/$out_name"
if command -v zip >/dev/null 2>&1; then
    ( cd "$tmp" && zip -q -r "$dest" "$skill_dir" )
elif py=$(find_python); then
    ( cd "$tmp" && "$py" -c '
import os, sys, zipfile
dest, root = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(dest, "w", zipfile.ZIP_DEFLATED) as z:
    for base, _, files in os.walk(root):
        for f in files:
            p = os.path.join(base, f)
            z.write(p, os.path.relpath(p, "."))
' "$dest" "$skill_dir" )
elif command -v powershell.exe >/dev/null 2>&1; then
    windest=$(cygpath -w "$dest" 2>/dev/null || echo "$dest")
    ( cd "$tmp" && powershell.exe -NoProfile -Command \
        "Compress-Archive -Path '$skill_dir' -DestinationPath '$windest' -Force" )
else
    die "No zip tool found (tried zip, python3/python, powershell)."
fi

[ "$EMIT_ZIP" -eq 1 ] && cp "$out_name" "$skill_dir.zip"

size=$(wc -c < "$out_name" | tr -d ' ')
echo "Built: $out_name v$md_ver ($size bytes)"
[ "$EMIT_ZIP" -eq 1 ] && echo "Built: $skill_dir.zip (copy)"
exit 0
