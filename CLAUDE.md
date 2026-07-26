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

`afk-skill` parses these trailer lines from a council run:

```
COUNCIL_VERDICT: <option> | CONFIDENCE: <high|medium|low>
COUNCIL_NEEDS: <comma-separated missing facts, or none>
```

Changing either line's format is a **major** version bump, and `afk-skill`'s
SKILL.md must be updated in the same session. Adding a new trailer is additive
(minor). `afk` treats `low` confidence as "escalate and defer" — if the
confidence vocabulary ever changes, `afk`'s handling of it changes too.

`COUNCIL_NEEDS` becomes the "questions the council couldn't answer" section of
the user's return briefing, so it must be populated honestly: it is the list of
things only the user can close.

When called by `afk`, the council **must not ask a clarifying question** — there
is nobody there to answer, and asking is exactly how an AFK session stalls. This
is a correctness property of the integration, not a stylistic preference.

## Invariants

- Debaters get the **brief only** — never the session transcript, never each
  other's output in round 1, never a hint about the preferred answer. Leaking
  session context is the failure that makes the whole skill theatre.
- **Round 2 is the default and should stay that way.** Round 1 only collects
  positions; round 2 is where a claim gets tested and where concessions happen.
  Dropping to 1 round is a latency concession, not a quality-neutral default.
- **Evidence discipline is enforced in the role cards, not just described.**
  When an evidence pack exists, debaters may cite only it and the brief; a
  missing fact becomes a `NEED:` line, never an invention. This is the whole
  reason the research phase is worth its cost — remove it and the pack becomes
  decoration that a debater can talk over.
- **The Researcher takes no position.** If it starts recommending, it has become
  a fourth debater with a search engine, and the Judge will weight it as
  evidence. Keep the card's separation of FACT and INFERENCE intact.
- **"Could not establish" is a required output**, not an optional one. "No
  advisories since 2024" and "I could not find advisory data" point in opposite
  directions, and only one of them is a reason for confidence.
- **Panels are not interchangeable.** `classic` produces a decision, `dmad` a
  reframing, `review` a findings list. Do not quietly widen a panel's seat list
  to make it cover more — that is how every panel becomes the same mush.
- **More seats and more rounds do not resolve a missing fact.** If the Judge is
  short of information, the answer is research or a `NEED:` line, never another
  round.
- The Judge runs **after** the debaters, in a clean context, and is the only
  seat allowed to rule. If the Judge fails, the skill reports LOW confidence —
  it does not rule from the orchestrating session's own (biased) context.
- Confidence is assigned **from the rubric only**. Never inflate to sound
  decisive; `low` must always name the missing information.
- Log **before** acting on a verdict.
- A missing debater is disclosed in the verdict block and the log — never
  silently backfilled by the orchestrator.
