# council-skill

A Cowork / Claude Code skill that convenes a **council of sub-agents** to debate
a hard question and return a verdict with an explicit confidence level.

Debaters open **in parallel with clean contexts** — each sees only the question
brief and its own role card, never your session's momentum toward a preferred
answer — then **cross-examine each other**. A Judge reads the whole transcript
(and nothing else) and rules.

## Panels

Pick by the *shape* of the question. The choice is a real fork: `classic`
produces a **decision**, `dmad` produces a **reframing**, `review` produces a
**findings list**.

| Panel | Seats | Use for |
|---|---|---|
| **`classic`** *(default)* | Advocate, Skeptic, Pragmatist | "Should we do X?" — choosing between options |
| **`dmad`** | Contrarian, First-Principles, Analogist, Outsider, Executor | Open or strategic questions where the *framing* may be wrong. Five reasoning **methods**, not five opinions |
| **`review`** | Security Auditor, Correctness Hawk, Feasibility Analyst, Clarity Editor | Reviewing a concrete artifact — a diff, a plan, a PR |
| custom | `--seats "a,b,c"` | Any mix of cards. A Judge is always added |

More seats is not better. Five seats on a two-option question mostly produces
restatement — prefer `classic` and spend the tokens on `--rounds 3`.

## Usage

```
/council <question>                              # classic, 2 rounds, auto-research
/council <question> --panel dmad --rounds 3
/council <question> --research
/council <question> --seats "advocate,skeptic,security,pragmatist"
/council <question> --rounds 1 --quiet
```

| Flag | Default | Effect |
|---|---|---|
| `--panel <name>` | `classic` | Which seats debate |
| `--rounds N` | **2** | 1 = openings · 2 = + cross-examination · 3 = + closings |
| `--research` / `--no-research` | auto | Force or suppress the web-research phase |
| `--seats "a,b,c"` | — | Custom seat list (2–6) |
| `--quiet` | off | Verdict block only |

**Two rounds by default**, because round 1 only collects positions — round 2 is
where a claim actually gets tested. A seat must quote a specific claim from
another seat and either rebut or **concede** it; concessions are recorded as
first-class output. Drop to `--rounds 1` only when something is waiting.

## Research phase

Debaters reason from what they're given, which on fact-dependent questions is a
liability: a confident council built on stale recollection is *worse* than no
council, because the debate launders the error into a verdict.

So a **Researcher** runs first — deep web search, several framings, following
into primary sources (release notes, advisories, official docs, the repo
itself) — and returns a cited evidence pack that every seat then argues over.
It must separate **fact from inference**, **date everything**, and **report what
it could not find** (absence of evidence is a finding: "no CVEs since 2024" and
"I couldn't find CVE data" point opposite ways).

Auto-runs when the question turns on library/tool status, pricing, benchmarks,
advisories, deprecations, or any checkable load-bearing claim. Skipped for
purely internal or purely value questions — and it says which, rather than
silently omitting it.

Then two rules are enforced: **debaters may cite only the evidence pack and the
brief**, and a debater needing an absent fact writes `NEED: <fact>` rather than
inventing one. The Judge collects every `NEED:` line — they drive the confidence
level and become the "would change this verdict" list.

## Output

```
## Council verdict — <question>
`panel: classic · rounds: 2 · research: ran (7 findings)`

**Advocate** (medium): ...
**Skeptic** (high): ...
**Pragmatist** (high): ...
**Round 2 movement:** Skeptic conceded the pool concern is bounded at current volume
**Open questions:** actual p99 job duration under load

### Verdict — confidence: MEDIUM
...

**Recommended action:** ...
**Would change this verdict:** ...
**Evidence:** ...
```

Every council is appended to `council_log_YYYY-MM-DD.md`, **before** the verdict
is acted on. See
[`council/references/examples.md`](council/references/examples.md) for a full
worked council, brief to logged verdict.

## Called from the `afk` skill

[`afk-skill`](https://github.com/pdrakeweb/afk-skill) delegates medium-stakes
decisions here while the user is away. In that mode the council runs `--quiet`,
never asks clarifying questions (nobody is there to answer), and appends a
machine-readable last line:

```
COUNCIL_VERDICT: <option> | CONFIDENCE: <high|medium|low>
```

plus `COUNCIL_NEEDS: <missing facts, or none>`, which becomes the "questions the
council couldn't answer" section of your return briefing.

A `low`-confidence verdict tells `afk` to escalate and defer rather than act.
In that mode the council never asks a clarifying question — there is nobody
there to answer, and asking is exactly how an AFK session stalls. The research
phase still runs on its normal heuristics: an AFK council is *more* dependent on
it, since nobody is present to catch a stale premise.

The skills are independent — `council` works standalone, and `afk` degrades
gracefully to a flagged best-effort decision if `council` is not installed.

## Build and deploy

```powershell
.\build.ps1              # → council.skill
.\build.ps1 -Zip         # → council.skill + council.zip
.\deploy.ps1             # INSTALL into Claude Desktop on this machine
.\publish.ps1            # build, then copy to <Dropbox>\Skills
.\deploy.ps1  -DryRun    # either script; show what would happen, write nothing
.\publish.ps1 -DryRun
```

The two verbs are different targets and it matters which you want:

| Script | Target | Use when |
|---|---|---|
| `deploy.ps1` | Claude Desktop's local skills-plugin dir on **this machine** | You want to *use* the skill here |
| `publish.ps1` | `<Dropbox>\Skills` | You want the package available on your other machines, or to upload it |

```bash
./build.sh               # same, on macOS / Linux / Git Bash
./build.sh --zip
```

`build.sh` and `build.ps1` produce **byte-identical archive contents** — same
entry set, same file bytes — so it doesn't matter which one runs. Both validate
before packaging and refuse to build on: a folder name that doesn't match the
frontmatter `name:`, a name breaking Anthropic's rules, an empty or >1024-char
description, or the two version stamps disagreeing.

Both scripts run the build first, so a failed validation aborts them and a
package that doesn't validate never reaches Claude Desktop or the shared folder.

`deploy.ps1` is the **skeleton's** installer, adopted here: it auto-detects the
nested `skills-plugin\<guid>\<guid>\skills\` layout, mirrors with robocopy
`/MIR` **excluding `data\`** so any runtime state survives a redeploy, keeps 5
backups, and — critically — registers the skill in `manifest.json`. Claude
Desktop only loads skills listed there, so a bare file copy is invisible.
**Restart Claude Desktop afterward.**

`publish.ps1` resolves Dropbox from `%LOCALAPPDATA%\Dropbox\info.json` (so it
survives Dropbox moving) and keeps the last 5 packages in `Skills\.backups\` —
Dropbox syncs deletions too, so overwriting a good package with a bad one
propagates everywhere, and a local backup is the fast way back. Override with
`-Destination`.

For web and mobile, upload `council.skill` via **Settings → Capabilities →
Skills** — that creates an account-synced copy which then takes precedence over
local files everywhere, including desktop.

## Honest limitation

All four agents are the same underlying model. Their disagreement is stylistic
and structural, not architectural — **correlated blind spots survive the
debate**. A council raises the floor on rigour; it is not an independent audit
and not a substitute for a domain expert. The skill states this in its own
verdicts whenever confidence is high.

## Relationship to the skeleton

Built from scratch rather than from
[claude-skill-skeleton](https://github.com/pdrakeweb/claude-skill-skeleton),
because this skill has no API, no cache, and no Python CLI — the skeleton's
SQLite/`skill_cache.py` machinery has nothing to do here. It **does** keep the
skeleton's conventions that apply: two matching semver stamps validated at
build time (`SKILL.md` frontmatter + `council/VERSION`), the same build-time
name/description validation, bump-on-every-commit versioning, and `git tag
vX.Y.Z`. See [CLAUDE.md](CLAUDE.md).

## Prior art

Surveyed before writing; none matched the required role set, confidence
rubric, logging, or AFK-callable contract, but ideas were borrowed with thanks:

- [mugenGH/ai-council](https://github.com/mugenGH/ai-council) — the
  correlated-model caveat in the verdict is its idea, and a good one.
- [ngmeyer/council-review](https://github.com/ngmeyer/council-review) —
  anti-sycophancy guardrails; the mandatory self-counter is a cousin of these.
- [wan-huiyan/agent-review-panel](https://github.com/wan-huiyan/agent-review-panel),
  [tsenart/council-skill](https://github.com/tsenart/council-skill).

## License

MIT — see [LICENSE](LICENSE).
