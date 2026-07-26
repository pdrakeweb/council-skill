# council-skill

A Cowork / Claude Code skill that convenes a **council of sub-agents** to debate
a hard question and return a verdict with an explicit confidence level.

Three debaters run **in parallel with clean contexts** — each sees only the
question brief and its own role card, never your session's momentum toward a
preferred answer. A Judge then reads all three (and nothing else) and rules.

| Seat | Mandate |
|------|---------|
| **Advocate** | Argues for the most promising option, by mechanism |
| **Skeptic** | Attacks assumptions, names failure modes with triggers |
| **Pragmatist** | Costs the options against real constraints; says what ships |
| **Judge** | Synthesizes, rules, assigns `high`/`medium`/`low` confidence |

## Usage

```
/council <question>
/council <question> --rounds 2
/council <question> --quiet
```

- `--rounds 2` gives the debaters a rebuttal round before the Judge rules;
  concessions are recorded as first-class output.
- `--quiet` prints the verdict block only.

Every council is appended to `council_log_YYYY-MM-DD.md` in the working
directory, **before** the verdict is acted on.

## Output

```
## Council verdict — <question>

**Advocate** (medium): ...
**Skeptic** (high): ...
**Pragmatist** (high): ...

### Verdict — confidence: MEDIUM
...

**Recommended action:** ...
**Would change this verdict:** ...
```

See [`council/references/examples.md`](council/references/examples.md) for a
full worked council, brief to logged verdict.

## Called from the `afk` skill

[`afk-skill`](https://github.com/pdrakeweb/afk-skill) delegates medium-stakes
decisions here while the user is away. In that mode the council runs `--quiet`,
never asks clarifying questions (nobody is there to answer), and appends a
machine-readable last line:

```
COUNCIL_VERDICT: <option> | CONFIDENCE: <high|medium|low>
```

A `low`-confidence verdict tells `afk` to escalate and defer rather than act.
The skills are independent — `council` works standalone, and `afk` degrades
gracefully to a flagged best-effort decision if `council` is not installed.

## Install

```powershell
.\build.ps1          # → council.skill
.\build.ps1 -Zip     # → council.skill + council.zip
```

Upload `council.skill` via **Settings → Capabilities → Skills**, or drop the
`council/` directory into your Cowork skills directory.

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
