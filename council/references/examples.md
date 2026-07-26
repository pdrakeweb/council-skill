# Worked example

A full council, from a vague prompt to a logged verdict. Use this to calibrate
brief length, summary length, and how blunt the verdict should be.

> Run as `panel: classic · rounds: 1 · research: skipped` — the question turned
> entirely on internal facts (this team, this cluster, these incidents), so the
> research heuristics correctly declined to run. The `--rounds 2` default was
> suppressed here to keep the example readable; §"What round 2 would have
> added" at the end shows what was lost by doing so, and why 2 is the default.

---

## The prompt

> "should we switch our background jobs off celery"

## Step 0 — Sharpen and brief

Vague prompt in, decision out. Shown to the user before spawning:

> **Sharpened:** Should we migrate the existing Celery background-job workers
> to (A) stay on Celery, (B) move to Postgres-backed queue via `pgmq`, or
> (C) move to a managed queue (SQS + a thin worker)?

The brief handed to the debaters — and nothing else:

```
QUESTION: Should we migrate background jobs off Celery?

OPTIONS
A. Stay on Celery + Redis.
B. Move to pgmq (queue inside the existing Postgres).
C. Move to SQS with a thin worker process.

CONSTRAINTS (facts, not preferences)
- 4 backend engineers; none has run SQS in production.
- ~40 job types, ~2M jobs/day, p99 latency requirement is 30s (loose).
- Redis is a separate managed instance costing ~$400/mo; Postgres already
  runs at ~20% CPU headroom.
- Two production incidents in 6 months traced to lost Celery tasks on
  worker restart.
- No hard deadline. Team wants "less operational surface".
- Compliance: jobs may carry PII; data must stay in our VPC.
```

Note what is *not* in the brief: any hint that the session already leaned
toward pgmq. That omission is the whole point.

## Step 1 — Debaters (parallel, clean contexts)

**Advocate** returned:

```
POSITION: Option B — move to pgmq; the lost-task incidents are a durability
problem and Postgres already gives us the transaction they need.
REASONING:
- The two incidents share a mechanism: Celery acks tasks before the work
  commits, so a restart drops in-flight work. pgmq lets the enqueue and the
  business write share one transaction — the failure mode stops existing.
- Removes Redis entirely: one less managed service, one less thing to page on.
- PII stays in Postgres, inside the VPC — compliance is unchanged, not merely
  satisfiable.
- 20% CPU headroom covers 2M jobs/day; pgmq's cost is a row insert and a
  SKIP LOCKED read, not a new engine.
STRONGEST COUNTER TO MY OWN VIEW: 40 job types means 40 migrations, and a
half-migrated system runs two queues at once — the riskiest state of all.
CONFIDENCE: medium
```

**Skeptic** returned:

```
POSITION: The durability argument is sound but the migration is being costed
as if it were free; the load-bearing assumption is that Postgres headroom
today survives queue traffic plus growth.
REASONING:
- Load-bearing assumption: "20% CPU headroom" is measured without the queue.
  Trigger: pgmq polling at high frequency across 40 job types adds constant
  read load; if headroom drops below ~10%, the queue and the primary database
  fail together — a shared-fate risk Celery+Redis does not have.
- The incidents are attributed to Celery, but ack-before-commit is a
  CONFIGURATION choice. `acks_late=True` plus idempotent tasks fixes it
  without a migration. This is unproven, not wrong — nobody said they tried.
- Trigger for a worse outcome: a long-running job holds a Postgres connection
  from a bounded pool; at 40 job types the pool becomes the new bottleneck.
- Retention: 2M jobs/day of queue rows means vacuum pressure. Nobody costed it.
STRONGEST COUNTER TO MY OWN VIEW: if the team genuinely cannot operate Redis
well — and two incidents suggest that — then "fix the config" keeps them on a
system they have already proven they mismanage.
EVIDENCE THAT WOULD CHANGE MY MIND: a staging run of pgmq at 2M jobs/day
showing Postgres CPU staying above 15% headroom.
CONFIDENCE: high
```

**Pragmatist** returned:

```
POSITION: Option B, but not as a migration — as a strangler. Move the 3 job
types involved in the incidents first; leave the other 37 on Celery
indefinitely.
REASONING:
- 40 job types is weeks-to-months of calendar time and a long dual-queue
  window. That window is where outages live. Nobody has budgeted for it.
- Option C is out on staffing alone: zero SQS experience across 4 engineers,
  and PII-in-VPC means VPC endpoints and a compliance review — that is a
  quarter, not a sprint.
- The incident-causing jobs are a small, identifiable set. Fixing those buys
  most of the value in days, not weeks.
- Killing Redis saves $400/mo. That is not a reason to do anything; it is a
  rounding error against four engineers' time.
STRONGEST COUNTER TO MY OWN VIEW: running two queue systems permanently is a
real ongoing tax, and "temporary" dual-stacks have a way of becoming the
architecture.
CONFIDENCE: high
```

## Step 3 — Judge

```
REAL DISAGREEMENT: Not whether pgmq is durable — all three accept that — but
whether the durability win requires migrating 40 job types or 3.

FACTUAL vs VALUE: Two factual, one value. FACTUAL: does `acks_late=True` fix
the lost-task incidents (check: read the incident postmortems and the current
Celery config)? FACTUAL: does Postgres hold headroom under queue load (check:
staging run at production volume). VALUE: tolerance for permanently running
two queue systems versus tolerance for a long migration window.

VERDICT: Move the 3 incident-implicated job types to pgmq; do not migrate the
other 37 on this evidence. The Pragmatist's strangler and the Advocate's
mechanism agree — the transactional enqueue is what fixes the incidents, and
it fixes them for 3 jobs as well as for 40. The Skeptic's headroom objection
is real but a 3-job pilot bounds it: it measures the CPU cost at small scale
before anything is committed. The Skeptic's `acks_late` point should be
checked FIRST — if it is untried, the cheap fix has not been ruled out and
even the 3-job migration may be unnecessary.

CONFIDENCE: MEDIUM — "genuine unresolved disagreement, but one option is
still better on the stated constraints; or the decision hinges on a fact that
is cheap to check." Both open facts are cheap: one config read, one staging
run.

RECOMMENDED ACTION: Read the two incident postmortems and the current Celery
`acks_late` setting today. If acks are early and untried, fix the config and
re-evaluate in 30 days before writing any pgmq code.

WOULD CHANGE THIS VERDICT: `acks_late=True` already set and incidents still
occurring (→ migrate the 3 jobs immediately, confidence rises). Or a staging
run showing Postgres headroom below 10% under queue load (→ pgmq is off the
table entirely, revisit C despite the staffing cost).

HOLLOW SELF-COUNTERS: none — all three named real weaknesses.
```

## Step 5 — Log entry

```markdown
## 14:32 — Migrate background jobs off Celery to pgmq, SQS, or stay?
- **Rounds:** 1
- **Invoked by:** user
- **Brief:** 3 options (Celery / pgmq / SQS); 4 engineers, no SQS experience;
  2M jobs/day, p99 30s; 2 lost-task incidents in 6mo; PII must stay in VPC;
  Postgres at 20% CPU headroom; no deadline.
- **Advocate:** B (pgmq) (medium) — transactional enqueue removes the
  lost-task mechanism; drops Redis; PII stays in VPC.
- **Skeptic:** headroom assumption unvalidated (high) — queue load measured
  without queue; shared-fate risk; `acks_late=True` never tried; vacuum
  pressure uncosted.
- **Pragmatist:** B as a strangler, 3 jobs not 40 (high) — 40-type migration
  is a months-long dual-queue window; C blocked on staffing + compliance.
- **Round 2 movement:** n/a
- **Verdict:** Migrate the 3 incident-implicated jobs only; check `acks_late`
  first — confidence **MEDIUM**
- **Recommended action:** Read the 2 postmortems + current `acks_late` config
  today; if untried, fix config and re-evaluate in 30 days.
- **Would change this verdict:** `acks_late` already on and incidents persist
  → migrate now. Staging headroom <10% → pgmq off the table.
```

---

## What round 2 would have added

Round 1 left one exchange unresolved, and it is the kind cross-examination is
for. The Skeptic asserted that `acks_late=True` would fix the incidents without
any migration. Nobody answered it — the Advocate never saw the claim, and the
Pragmatist built a plan on top of a premise the Skeptic had just questioned.

In round 2 the Advocate receives that claim verbatim and has to either rebut it
("`acks_late` re-delivers on restart but does not make the enqueue atomic with
the business write, so the double-write window stays open") or concede it. Both
outcomes are worth more than the Judge inferring the answer:

- A **rebuttal** would have promoted the verdict from MEDIUM toward HIGH, since
  the cheap-alternative question — the thing that made it MEDIUM — would be
  settled inside the debate rather than deferred to a config read.
- A **concession** would have flipped the recommended action entirely: not "fix
  3 jobs", but "fix one config line and re-evaluate".

That is why `--rounds 2` is the default. Round 1 collects positions; round 2 is
where a claim actually gets tested. Drop to `--rounds 1` only when a queue is
waiting on the answer.

Note also what round 2 would **not** have done: neither seat could have
established whether `acks_late` is currently set. That is a NEED, and it stays a
NEED however many rounds run. Rounds surface disagreement; they do not
manufacture missing facts.

## What this example is calibrated to show

- The **brief carries the constraints**, and the verdict is only as good as
  they are. Had "Postgres at 20% headroom" been omitted, the Skeptic's best
  objection would not exist.
- The Judge **narrowed** the disagreement (40 jobs vs 3) rather than splitting
  the difference between three positions.
- Confidence is `MEDIUM` because two cheap checks are outstanding — not
  because the Judge wanted to hedge.
- The recommended action is a **thing to read**, not a thing to build. That is
  frequently the right answer and the council should not be embarrassed by it.
