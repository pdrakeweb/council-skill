# CLAUDE.md — council-skill

## Divergence from claude-skill-skeleton (deliberate)

Per the machine-wide convention, new skills start from
`claude-skill-skeleton`. This one **intentionally does not**, and the reason is
recorded here so nobody "fixes" it later:

`council` is a pure-Markdown orchestration skill. It has no upstream API, no
data to cache, and no Python CLI — so `skill_cache.py`, `skill_schema.py`,
`cli.py`, TTLs, `protect_where`, `config-export`, and the auth-bootstrap paths
are all dead weight. Vendoring them would mean shipping a SQLite layer that
never opens a database.

What this repo **does** keep from the skeleton, because it applies:

| Skeleton convention | How it appears here |
|---|---|
| Two version stamps that must match | `council/SKILL.md` frontmatter `version:` **and** `council/VERSION` (`SKILL_VERSION = "X.Y.Z"`) |
| Build refuses to package on mismatch | `build.ps1` validates both stamps |
| Build validates skill naming rules | folder name == frontmatter `name:`, lowercase/hyphen only, no reserved words, description <= 1024 chars |
| Bump on every commit + `git tag vX.Y.Z` | see below |
| `data/` ships empty | `build.ps1` stages an empty `data/` |
| Compact Markdown output, no raw dumps | the verdict block in SKILL.md |
| Honest-limitations section | the correlated-model caveat |

The one shared file that changed shape: the second version stamp moved from
`scripts/skill_schema.py` to a plain `VERSION` file, since there is no Python.
If the skeleton ever grows first-class support for script-free skills, that is
the change to port back.

## Versioning — bump on EVERY commit that touches `council/`

Both stamps must match or `build.ps1` refuses to package:

1. `council/SKILL.md` frontmatter → `version: "X.Y.Z"`
2. `council/VERSION` → `SKILL_VERSION = "X.Y.Z"`

- **patch** — wording fixes, role-card tweaks, doc changes
- **minor** — new flags, new seats, new output fields
- **major** — breaking changes to the invocation contract, the output block, or
  the `COUNCIL_VERDICT:` line that `afk` parses

Then `git tag vX.Y.Z`.

## Build

```powershell
.\build.ps1          # → council.skill
.\build.ps1 -Zip     # → council.skill + council.zip
```

## The contract with afk-skill — do not break silently

`afk-skill` parses the last line of a council run:

```
COUNCIL_VERDICT: <option> | CONFIDENCE: <high|medium|low>
```

Changing that line's format is a **major** version bump, and `afk-skill`'s
SKILL.md must be updated in the same session. `afk` treats `low` confidence as
"escalate and defer" — if the confidence vocabulary ever changes, `afk`'s
handling of it changes too.

## Invariants

- Debaters get the **brief only** — never the session transcript, never each
  other's output in round 1, never a hint about the preferred answer. Leaking
  session context is the failure that makes the whole skill theatre.
- The Judge runs **after** the debaters, in a clean context, and is the only
  seat allowed to rule. If the Judge fails, the skill reports LOW confidence —
  it does not rule from the orchestrating session's own (biased) context.
- Confidence is assigned **from the rubric only**. Never inflate to sound
  decisive; `low` must always name the missing information.
- Log **before** acting on a verdict.
- A missing debater is disclosed in the verdict block and the log — never
  silently backfilled by the orchestrator.
