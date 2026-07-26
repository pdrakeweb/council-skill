---
name: "council"
version: "0.2.0"
description: >
  Convene a council of sub-agents that debate a hard question across multiple
  rounds and return a verdict with a confidence level. Selectable panels:
  classic (Advocate / Skeptic / Pragmatist), dmad (five diverse reasoning
  methods), review (security, correctness, feasibility, clarity), or custom
  seats. Debaters open in clean parallel contexts, then cross-examine each
  other; a Judge rules with high/medium/low confidence and a recommended
  action. Includes an optional deep web-research phase that builds a cited
  evidence pack before the debate, so the panel argues over facts rather than
  recollection. Use on "council this", "convene the council", "debate this",
  "argue both sides", "red-team this", "stress-test this decision", "get
  multiple opinions", "what would a skeptic say", or any architectural,
  strategic, or high-consequence choice. Also invoked by the afk skill for
  decisions and questions arising while the user is away.
---

# Council

A structured multi-agent debate. Debaters open in **clean parallel contexts**,
**cross-examine each other**, and a Judge — who sees the transcript and nothing
else from your session — rules with an explicit confidence level.

The point is adversarial pressure over shared facts. A recommendation that
survives a Skeptic who was *paid to kill it*, arguing from sourced evidence
rather than recollection, is worth more than one that was never challenged.

## When to convene (and when not to)

Convene when **at least two** are true:

- The decision is expensive to reverse (schema, public API, dependency, hire).
- Reasonable experts would disagree.
- You notice yourself pattern-matching to the first plausible answer.
- The user asked for a debate, red-team, or second opinion.
- The `afk` skill routed a decision or question here.

**Do not convene** for questions with a checkable answer (run the test, read
the code, grep it), for pure preference with no downside, or when speed matters
more than rigour. Say so in one line and answer directly — a council on a
trivial question burns tokens and buries the real answer.

## Invocation

```
/council <question>
/council <question> --panel dmad --rounds 3
/council <question> --research
/council <question> --seats "advocate,skeptic,security,pragmatist"
/council <question> --rounds 1 --quiet
```

| Flag | Default | Effect |
|------|---------|--------|
| `--panel <name>` | `classic` | Which seats debate. See **Panels** below. |
| `--rounds N` | **2** | 1 = openings only. 2 = openings + cross-examination. 3 = adds closing statements. Max 3. |
| `--research` / `--no-research` | auto | Force or suppress the web-research phase (see **Research phase**). |
| `--seats "a,b,c"` | — | Custom seat list, overriding `--panel`. 2–6 seats. |
| `--quiet` | off | Print the verdict block only. The log still records everything. |

Anything not recognized as a flag is the question. If no question is present,
ask for one — never invent it.

## Panels

Pick by the **shape of the question**, not by how important it is. If unsure,
`classic` is right more often than not — say which you picked and why in one
line before spawning.

| Panel | Seats | Use for |
|-------|-------|---------|
| **`classic`** *(default)* | Advocate, Skeptic, Pragmatist | Should we do X? Choosing between options. The general case. |
| **`dmad`** | Contrarian, First-Principles, Analogist, Outsider, Executor | Diverse-method deliberation for open or strategic questions where the framing itself may be wrong. Five *reasoning methods*, not five opinions. |
| **`review`** | Security Auditor, Correctness Hawk, Feasibility Analyst, Clarity Editor | Reviewing a concrete artifact — a diff, a plan, a design doc, a PR. Each seat owns a failure category. |
| **custom** | `--seats "..."` | Mix any cards from `references/roles.md`. A Judge is always added. |

Panel choice is a real fork: `classic` produces a **decision**, `dmad` produces
a **reframing**, `review` produces a **findings list**. Choosing `review` for a
"should we?" question yields four critiques and no answer.

More seats is not better. Five seats on a question with two real options mostly
produces restatement. Prefer `classic` and spend the tokens on `--rounds 3`.

## Research phase

Debaters reason from what they were given. On questions that turn on **external,
checkable facts**, that is a liability: a confident council built on stale
recollection is worse than no council, because the debate launders the error
into a verdict. The research phase fixes the facts first.

### When it runs

**Auto-run** when the question depends on any of:

- The current state of a library, tool, service, or standard — is it
  maintained, what's the current major version, what replaced it
- Pricing, quotas, limits, or SLAs
- Benchmarks, performance claims, or capacity numbers
- Security advisories, CVEs, breaking changes, deprecations
- Anything a vendor or project announced, and roughly when
- A claim in the user's own framing that is checkable and load-bearing

**Skip** when the question is purely internal (this codebase, this team, this
data), purely a value judgment, or when the brief already carries the facts.
Say `research: skipped — <reason>` in one line rather than silently omitting it.

`--research` forces it on; `--no-research` forces it off. Honour the flag over
the heuristics.

### How it runs

Spawn **one Researcher agent** before the debaters, with the sharpened question
and the research card from `references/roles.md`. It runs first and serially —
the debaters need its output. Give it a real budget: this is deep research, not
one search. It should search several framings, follow into primary sources
(release notes, changelogs, advisories, official docs, the repo itself), and
prefer primary over summary.

It returns an **evidence pack**:

```
FINDINGS (each: claim — source URL — date — confidence)
- <fact> — <url> — <YYYY-MM> — direct | inferred
CONTESTED: <where sources disagree, with both sides>
COULD NOT ESTABLISH: <what was searched for and not found>
STALENESS: <how time-sensitive these facts are; when they'd need rechecking>
```

Three rules the Researcher must follow, and the Judge must enforce:

1. **Separate FACT from INFERENCE.** A sourced claim and a plausible
   extrapolation get different labels. Never blur them.
2. **Report what could not be found.** Absence of evidence is a finding, and
   often the most decision-relevant one — "no CVEs since 2024" and "I couldn't
   find CVE data" point in opposite directions.
3. **Date everything.** A fact without a date cannot be aged.

### How the evidence is used

The evidence pack is appended to the brief and given to **every** debater, so
they argue over the same facts. Two consequences, both enforced:

- **Debaters may cite only the evidence pack and the brief.** Anything else is
  recollection and is inadmissible.
- If a debater needs a fact that isn't there, it writes `NEED: <the fact>`
  rather than inventing one. The Judge collects every `NEED:` line — those
  become the "would change this verdict" list, and more than two of them is
  grounds for `low` confidence on its own.

## Protocol

### Step 0 — Frame the question

Restate it in one sentence, as a **decision between options** rather than an
open prompt. "Should we move sessions from JWT to server-side?" beats "thoughts
on auth?". If the prompt was vague, sharpen it and show the sharpened version
before spawning — a bad frame wastes every seat.

Assemble a **brief** (max ~400 words):

- the sharpened question,
- the candidate options, named A/B/C,
- hard constraints that are facts, not opinions (deadline, budget, stack,
  compliance, team size),
- file paths or excerpts the debaters need,
- the evidence pack, if the research phase ran.

The brief is the *only* context the debaters get. This is deliberate: they must
not inherit your session's momentum toward a preferred answer.

State the configuration in one line before spawning:
`panel: classic · rounds: 2 · research: ran (7 findings)`.

### Step 1 — Research (if applicable)

Run the Researcher, append the evidence pack to the brief. If it returns
nothing usable, say so and continue — but tell the Judge, because a research
phase that found nothing is a confidence input.

### Step 2 — Round 1, openings (parallel, clean contexts)

Launch every seat in **one message with N tool calls** so they run
concurrently. Each gets the brief plus its own role card and **nothing else** —
no transcript, no other seat's output, no hint about which option you like.

Each returns:

```
POSITION: <one sentence>
REASONING: <3-6 bullets, each a claim + why it holds>
STRONGEST COUNTER TO MY OWN VIEW: <one bullet — mandatory>
NEED: <facts I lacked, or "none">
CONFIDENCE: high | medium | low
```

The mandatory self-counter is an anti-sycophancy device. A seat that cannot
name a weakness in its own position has not thought hard enough; a hollow
self-counter is reported and that seat is discounted.

### Step 3 — Round 2, cross-examination (default)

Re-spawn every seat in parallel. Each now receives the brief **plus the
verbatim round-1 output of every other seat** — not its own, which it already
holds and which re-reading only entrenches. Each must:

- name at least one **specific** claim from another seat and rebut or concede it,
- update its POSITION if moved, and say explicitly what moved it,
- keep the same output format.

**Concession is a signal, not a failure.** Record concessions; they are the
highest-value output of the round. If round 2 produces no movement and no new
argument on any side, say "round 2 added nothing" rather than padding.

### Step 4 — Round 3, closings (only with `--rounds 3`)

Each seat gets one final statement: its strongest remaining argument in ≤3
bullets, plus what it now concedes. Use this only when round 2 was genuinely
contested — on a question that converged in round 2, closings are restatement.

### Step 5 — The Judge

Spawn the Judge **after** the debaters finish, with the brief (including the
evidence pack) and all rounds. The Judge does not see your session either.

The Judge must:

1. Identify where the seats **actually** disagree — often less than it appears.
2. Classify each disagreement as **factual** (checkable — name the check) or
   **value** (a tradeoff preference — surface it, don't pretend to resolve it).
3. Weigh **sourced evidence above debater assertion.** A cited finding beats a
   confident bullet. Note any position that contradicts the evidence pack.
4. Rule. Pick an option. "It depends" only with the decisive variable named and
   a way to resolve it.
5. Assign confidence from the rubric below — no other basis.
6. Give one recommended action someone could start on immediately.

**Confidence rubric** (the Judge quotes the matching row):

| Level | Criteria |
|-------|----------|
| **high** | Seats converged, or the disagreement was factual and resolved by the evidence; the brief's constraints suffice to decide; every failure mode raised has a named mitigation; **no unresolved `NEED:` lines**. |
| **medium** | Genuine unresolved disagreement, but one option is better on the stated constraints; or the decision hinges on a fact that is cheap to check; or ≤2 open `NEED:` lines. |
| **low** | The decision depends on information not available (>2 open `NEED:` lines, or the research phase could not establish a load-bearing fact); or a failure mode could not be bounded; or the seats argued past each other. **Low must name the specific missing information.** |

Never inflate confidence to sound helpful. A `low` verdict that names the
missing fact is more useful than a `high` verdict that is wrong.

### Step 6 — Report

```
## Council verdict — <sharpened question>
`panel: <name> · rounds: <n> · research: <ran (n findings) | skipped — reason>`

**<Seat>** (<conf>): <2-3 sentences>
   … one line per seat …

**Round 2 movement:** <who conceded what, or "none">
**Open questions:** <collected NEED: lines, or "none">

### Verdict — confidence: HIGH | MEDIUM | LOW
<2-4 sentences: the ruling and what decided it>

**Recommended action:** <one concrete next step>
**Would change this verdict:** <what fact or event would flip it>
**Evidence:** <key sources with dates, if research ran>
```

With `--quiet`, print only from `### Verdict` down.

### Step 7 — Log

Append to `council_log_YYYY-MM-DD.md` in the working directory (create it with
an `# Council log — YYYY-MM-DD` header if absent):

```markdown
## HH:MM — <sharpened question>
- **Config:** panel <name> · rounds <n> · research <ran|skipped>
- **Invoked by:** user | afk skill
- **Brief:** <constraints and options given to the seats>
- **Evidence:** <n findings; key sources + dates; what could not be established>
- **<Seat>:** <position> (<conf>) — <reasoning digest>   ← one per seat
- **Round 2 movement:** <concessions, or "none">
- **Open questions (NEED):** <list, or "none">
- **Verdict:** <ruling> — confidence **<LEVEL>**
- **Recommended action:** <action>
- **Would change this verdict:** <trigger>
```

Log **before** acting on the verdict. If the action goes wrong, the log is the
record of what was known at decision time.

## Being called by the `afk` skill

The `afk` skill routes decisions **and questions it would otherwise have asked
the user** here while they are away. When invoked that way:

- The brief arrives pre-built. Use it as-is; **never ask a clarifying
  question** — there is nobody there to answer, and asking is how an AFK
  session stalls.
- Default to `--rounds 2 --quiet`. Drop to `--rounds 1` if `afk` says a queue
  is waiting.
- **Run the research phase on its normal heuristics.** An AFK council is more
  dependent on it, not less: nobody is present to catch a stale premise.
- Return the verdict block plus these trailer lines, exactly:

```
COUNCIL_VERDICT: <option> | CONFIDENCE: <high|medium|low>
COUNCIL_NEEDS: <comma-separated missing facts, or none>
```

- A **low**-confidence verdict tells `afk` to escalate and defer, not to
  proceed cautiously. Say so in the returned block.
- `COUNCIL_NEEDS` becomes the question list in the user's return briefing —
  these are precisely the things worth their attention.

Log the entry with `**Invoked by:** afk skill` so the two logs cross-reference.

## Honest limitations

State this in the verdict block whenever confidence is high, and any time the
council is being treated as an independent audit:

> All seats and the Judge are the same underlying model. Their disagreement is
> stylistic and structural, not architectural — correlated blind spots survive
> the debate. A council raises the floor on rigour; it is not a substitute for
> a domain expert or a real second implementation.

Also worth naming when they apply:

- The council can only reason over the brief and the evidence pack. A missing
  constraint produces a confident, wrong verdict — the main failure mode.
- The research phase reduces this but does not eliminate it: search finds what
  is written and indexed, and recency is not reliability.
- Seats cannot run code. If a disagreement is factual and **locally**
  checkable, stop and check it rather than convening again.
- Re-running the same question is not an independent sample; cross-run
  agreement is weak evidence.
- More rounds ≠ more truth. Rounds surface disagreement; they do not resolve a
  missing fact.

## Error handling

- **A seat fails or returns nothing** — proceed with the rest, and name the
  empty seat in the verdict block and the log. Never silently substitute your
  own reasoning for a missing agent.
- **All seats fail** — do not fabricate a council. Answer directly, labelled
  `UNCOUNCILED — single-model opinion, no debate ran`.
- **The Judge fails** — print the seat summaries and stop at
  `### Verdict — confidence: LOW (judge unavailable)`. A missing Judge is not
  licence to rule from your own context, which is exactly the bias the Judge's
  clean context exists to avoid.
- **The Researcher fails or has no web access** — continue without it, mark the
  verdict `research: unavailable`, and cap confidence at **medium** if the
  question was one the heuristics said needed research. Do not let debaters
  backfill from recollection.
- **The log cannot be written** — print the entry to chat verbatim, prefixed
  `⚠ council log not written to disk:`, so the record survives the transcript.

## References

- `references/roles.md` — verbatim role cards for every seat, every panel, the
  Researcher, the Judge, and the round-2/3 addenda.
- `references/examples.md` — a worked council, briefing to verdict.
