---
name: "council"
version: "0.1.0"
description: >
  Convene a council of sub-agents that debate a hard question and return a
  verdict. An Advocate argues for the most promising option, a Skeptic attacks
  the assumptions and hunts failure modes, and a Pragmatist tests feasibility
  against real constraints; a Judge then synthesizes all three into a verdict
  with a high/medium/low confidence rating and a recommended action. Use when
  the user says "council this", "convene the council", "debate this", "argue
  both sides", "stress-test this decision", "get multiple opinions", "red-team
  this plan", "what would a skeptic say", or is stuck on an architectural,
  strategic, or high-consequence choice where a single answer is not enough.
  Also invoked programmatically by the afk skill to adjudicate medium-stakes
  decisions while the user is away — even if they don't say "council" by name.
---

# Council

A structured multi-agent debate. Three debaters answer the same question from
locked, non-overlapping stances in **clean parallel contexts**, then a Judge —
who sees all three and nothing else from your session — delivers a verdict with
an explicit confidence level.

The point is adversarial pressure. A recommendation that survives a Skeptic
who was *paid to kill it* is worth more than one that was never challenged.

## When to convene (and when not to)

Convene when **at least two** are true:

- The decision is expensive to reverse (schema, public API, dependency, hire).
- Reasonable experts would disagree.
- You notice yourself pattern-matching to the first plausible answer.
- The user explicitly asked for a debate, red-team, or second opinion.
- The `afk` skill classified something as medium-stakes.

**Do not convene** for questions with a checkable answer (run the test, read
the docs, grep the code), for pure preference with no downside, or when the
user needs speed more than rigour. Say so in one line and answer directly —
a council on a trivial question burns tokens and buries the real answer.

## Invocation

```
/council <question>
/council <question> --rounds 2
/council <question> --quiet
```

| Flag | Effect |
|------|--------|
| `--rounds 2` | Debaters get a **second round** to rebut the other two before the Judge rules. Default is 1 round. |
| `--quiet` | Skip the per-agent summaries in chat; print the verdict block only. The log still records everything. |

Anything not recognized as a flag is the question. If no question is present,
ask for one — never invent it.

## Protocol

### Step 0 — Frame the question

Restate the question in one sentence, as a **decision between options** rather
than an open prompt. "Should we move sessions from JWT to server-side?" beats
"thoughts on auth?". If the user gave a vague prompt, sharpen it and show the
sharpened version before spawning — a bad frame wastes all three agents.

Assemble a **brief** (max ~400 words) containing:

- the sharpened question,
- the candidate options (name them A/B/C),
- hard constraints that are facts, not opinions (deadline, budget, stack,
  compliance, team size),
- any file paths or excerpts the debaters need.

The brief is the *only* context the debaters get. This is deliberate: they must
not inherit your session's momentum toward a preferred answer.

### Step 1 — Spawn the three debaters in parallel

Launch all three in **one message with three tool calls** so they run
concurrently. Each gets the brief plus its own role card (see
`references/roles.md`) and **nothing else** — no transcript, no prior council
output, no hints about which option you like.

| Agent | Mandate |
|-------|---------|
| **Advocate** | Pick the single most promising option and make the strongest honest case for it. Name the option explicitly. Give the mechanism by which it wins, not just adjectives. |
| **Skeptic** | Attack. Surface the load-bearing assumptions, name concrete failure modes with a plausible trigger for each, and state what evidence would change your mind. Do not propose alternatives — that is not your job. |
| **Pragmatist** | Ignore elegance. Cost the options in effort, calendar time, migration risk, on-call burden, and required skills the team may not have. Say which option ships. |

Each debater returns:

```
POSITION: <one sentence>
REASONING: <3-6 bullets, each a claim + why it holds>
STRONGEST COUNTER TO MY OWN VIEW: <one bullet — mandatory>
CONFIDENCE: high | medium | low
```

The mandatory self-counter is an anti-sycophancy device. An agent that cannot
name a weakness in its own position has not thought hard enough; if one returns
a hollow self-counter, note it and discount that agent in the verdict.

### Step 2 — Optional second round (`--rounds 2`)

Re-spawn the same three roles in parallel. Each now receives the brief **plus
the verbatim round-1 output of the other two** (not its own — it already has
that in its position, and re-reading it entrenches). Instruct each to:

- name at least one specific claim from another debater and rebut or concede it,
- update its POSITION if the other two moved it, and say so explicitly,
- keep the same output format.

A debater that concedes is a **signal, not a failure** — record concessions;
they are the highest-value output of round 2.

If round 2 produces no movement and no new argument on any side, say
"round 2 added nothing" in the log rather than padding the summary.

### Step 3 — The Judge

Spawn the Judge **after** the debaters finish, with the brief and all debater
output (both rounds if run). The Judge does **not** see your session either.

The Judge must:

1. Identify where the three actually disagree — often less than it appears.
2. Decide which disagreements are **factual** (checkable, so name the check)
   versus **value judgments** (not resolvable by debate — surface the tradeoff).
3. Rule on the question. Pick an option. "It depends" is only acceptable with
   the decisive variable named and a way to resolve it.
4. Assign confidence using the rubric below — no other basis.
5. Give one recommended action that someone could start on Monday.

**Confidence rubric** (the Judge quotes the matching row):

| Level | Criteria |
|-------|----------|
| **high** | Debaters converged, or the disagreement was factual and resolvable; the constraints in the brief are sufficient to decide; the Skeptic's failure modes are all mitigable with named mitigations. |
| **medium** | Genuine unresolved disagreement, but one option is still better on the stated constraints; or the decision hinges on a fact that is cheap to check. |
| **low** | The decision depends on information not in the brief; or the Skeptic surfaced a failure mode nobody could bound; or the debaters were arguing past each other. **Low confidence must be paired with the specific missing information.** |

Never inflate confidence to sound helpful. A `low` verdict that names the
missing fact is more useful than a `high` verdict that is wrong.

### Step 4 — Report

Print this block (compact; no preamble):

```
## Council verdict — <sharpened question>

**Advocate** (<conf>): <2-3 sentences>
**Skeptic** (<conf>): <2-3 sentences>
**Pragmatist** (<conf>): <2-3 sentences>
<if --rounds 2:>
**Round 2 movement:** <who conceded what, or "none">

### Verdict — confidence: HIGH | MEDIUM | LOW
<2-4 sentences: the ruling and the reasoning that decided it>

**Recommended action:** <one concrete next step>
**Would change this verdict:** <what fact or event would flip it>
```

With `--quiet`, print only from `### Verdict` down.

### Step 5 — Log

Append to `council_log_YYYY-MM-DD.md` in the working directory (create it, with
an `# Council log — YYYY-MM-DD` header, if absent). One entry per council:

```markdown
## HH:MM — <sharpened question>
- **Rounds:** 1 | 2
- **Invoked by:** user | afk skill
- **Brief:** <the constraints and options given to the debaters>
- **Advocate:** <position> (<conf>) — <reasoning digest>
- **Skeptic:** <position> (<conf>) — <reasoning digest>
- **Pragmatist:** <position> (<conf>) — <reasoning digest>
- **Round 2 movement:** <concessions, or "none">
- **Verdict:** <ruling> — confidence **<LEVEL>**
- **Recommended action:** <action>
- **Would change this verdict:** <trigger>
```

Log **before** acting on the verdict, not after. If the action goes wrong, the
log is the record of what was known at decision time.

## Being called by the `afk` skill

The `afk` skill delegates medium-stakes decisions here while the user is away.
When invoked that way:

- The brief arrives pre-built from `afk` — use it as-is; do not ask the user
  for clarification, because there is nobody there to answer.
- Run **1 round** unless `afk` requests 2. Speed matters more when a queue of
  decisions is waiting.
- Always run `--quiet`; `afk` writes its own summary into the AFK log.
- Return the verdict block **plus** the confidence level as a machine-readable
  last line: `COUNCIL_VERDICT: <option> | CONFIDENCE: <high|medium|low>`.
- A **low**-confidence verdict is a signal to `afk` that the decision should be
  escalated and deferred, not executed. Say so in the returned block.

Log the entry with `**Invoked by:** afk skill` so the two logs can be
cross-referenced on return.

## Honest limitations

State this in the verdict block whenever confidence is high, and any time the
user seems to be treating the council as an independent audit:

> All three debaters and the Judge are the same underlying model. Their
> disagreement is stylistic and structural, not architectural — correlated
> blind spots survive the debate. A council raises the floor on rigour; it is
> not a substitute for a domain expert or a real second implementation.

Other limits worth naming when they apply:

- The council can only reason over what is in the brief. A missing constraint
  produces a confident, wrong verdict — this is the main failure mode.
- Debaters cannot run code or read files unless the brief includes the
  excerpts. If a disagreement is factual, **stop and check the fact** rather
  than convening again.
- Re-running the same question does not produce independent samples; agreement
  across runs is weak evidence.

## Error handling

- **A debater fails or returns nothing** — proceed with the remaining two, and
  say which seat was empty in both the verdict block and the log. Never
  silently substitute your own reasoning for a missing agent.
- **All three fail** — do not fabricate a council. Report the failure, answer
  the question directly, and label the answer `UNCOUNCILED — single-model
  opinion, no debate ran`.
- **The Judge fails** — print the three debater summaries and stop at
  `### Verdict — confidence: LOW (judge unavailable)`. A missing Judge is not
  a licence to rule yourself; you have your session's bias, which is exactly
  what the Judge's clean context exists to avoid.
- **The log cannot be written** (read-only directory) — print the log entry to
  chat verbatim, prefixed `⚠ council log not written to disk:`, so the record
  survives in the transcript.

## References

- `references/roles.md` — the verbatim role cards to pass to each debater.
- `references/examples.md` — a worked council, briefing to verdict.
