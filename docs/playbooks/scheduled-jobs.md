---
title: Designing scheduled jobs
layout: default
parent: Playbooks
nav_order: 3
---

# Designing scheduled jobs

Most of the autonomous system runs as scheduled jobs (crons). Good ones are quiet, cheap, and
trustworthy; bad ones spam you, drift, or fail silently. The patterns here are what separate the
two.

---

## Silent-on-no-op (the most important rule)
A scheduled job that runs every few hours should produce **nothing** when there's nothing to report.
- If it emits "nothing to do" every tick, you'll train yourself to ignore it — and miss the tick
  that mattered.
- Design the job so empty output = no notification. A job that's silent for a week and then speaks
  is one you'll actually read.

## Deterministic where possible (no LLM in the loop)
The most robust scheduled jobs are plain scripts with **no model**:
- no prompt-injection surface (nothing reads untrusted content into a model),
- no nondeterminism (same input → same output),
- no token cost, no latency.
Push every job toward this shape. Reserve the LLM for jobs that genuinely need judgment (summarize a
feed, draft a digest, reason about content) — and for those, the security spine's injection
guardrails are mandatory.

## When a model's output feeds a script
Some jobs need the model's judgment and then act on it with plain code: write a store, rank a
list, file or label an item. The seam between the two is where these jobs break. Six rules keep
it honest:

1. **A closed schema.** The job states the exact shape it accepts: keys, types, and the allowed
   values or range for each. A reply with an unknown key, a missing key, or a value outside its
   range is rejected. Reject, never repair. When one reply covers several items, check each
   item's part on its own and reject only the parts that fail. The schema bounds the shape, not
   the content: an injected item can still steer the model to an allowed but wrong value, so the
   [injection guard](../reference/security-spine.md#1-injection-guard-read-can-never-change-do)
   still applies. Choose the allowed set with its worst value in mind.
2. **Declared shims, for transport only.** A shim may undo an artifact of how the reply arrives:
   strip a code fence, unwrap the envelope a CLI puts around the model's text. Keep the list
   finite and written down. A shim never picks one candidate out of several, guesses a field name,
   coerces a type or fills a missing value: a reply that narrates around its data is the model
   not complying, and a heuristic that picks the data out of it is one an item's text can steer.
   What a shim returns still goes through rule 1.
3. **A failure count per item.** An item is handled, rejected, or parked. A rejected reply isn't
   handled: the item stays in the queue and its count goes up. After a small fixed number of
   rejections, three say, the item is parked and surfaced instead of retried every run. The count
   resets when the item's stamp changes. Name the inputs the stamp covers, as a
   [decision row's stamp](output-loop.md#the-decision-row) does, leaving out routine churn, and
   include the prompt, the model and the schema version, so fixing a prompt brings parked items
   back. A human can unpark an item by hand.
4. **A breaker for the whole run.** When enough replies come in, five say, and most are rejected,
   stop the run and alert: that's an outage or a prompt or model regression, not many bad items.
   A run the breaker stopped charges no item's count, except an item that was in three stopped
   runs in a row. Without that exception, one bad item in a small incremental run trips the
   breaker every tick and never parks, and a flood of hostile items holds the breaker open.
5. **Counts and ids, never model text.** Anything the job emits that another model may read (a
   notification, a log a scheduler reads, a summary) carries counts, item ids, and rejection
   classes from a fixed list the job defines. Never the validator's message or the offending key
   or value: those quote what the model wrote, and the model wrote from untrusted content. Model
   text goes only where no model reads it. This applies to any job with a model in it, and most
   of all when the reading model can run commands.
6. **A rejection is reported.** List each one in the run's output, by item id and class. A park
   alerts. A breaker stop is a failure and exits non-zero, under
   [failure surfacing](#failure-surfacing).

## Incremental, not full-rescan
A steady-state job should process only what's *new or changed*, not re-scan the entire back catalog
every tick. Mark what you've handled (a state file, a label, a ledger) and skip it next time. The
one-time backfill is a manual/initial run; the recurring job is cheap.

## Idempotent
Running the job twice changes nothing the first run didn't already do. This makes retries, overlaps,
and manual re-runs safe. Reconcile to a desired state rather than blindly appending.

## The heartbeat exception
One job type *should* always speak: a **liveness watchdog** that audits the whole fleet's health and
reports daily even when all-green. Here the **absence** of the green report is the alarm — if the
heartbeat goes quiet, something broke the heartbeat itself. Use this sparingly (one fleet-health
job), not for every cron.

## Coordination & durability
- **Concurrency:** if multiple jobs (or a job and a live session) can touch the same state, guard it
  with a lock so they don't collide. A simple file lock with a "someone else owns this item, skip
  it" exit is usually enough.
- **Orphaned work:** a job can do its work, commit locally, then die before pushing. Check for
  unpushed state at the top of the next run and flush it. Don't assume a local commit reached the
  remote.
- **Script location & secrets:** jobs that need a secret call a secret-isolating helper (the token
  never enters the job's context). Keep the helper scripts where the scheduler can resolve them.

## Failure surfacing
- A job that exits non-zero or times out should *alert*, not fail silently. Silent-on-no-op is for
  *success* with nothing to do — never for errors.
- Pair long autonomous jobs with a completion or error notification so a broken job can't hide.
- **Don't make push delivery the only path to the human.** If a job's output is delivered to a chat
  platform, treat that as an enhancement — a misconfigured or unsupported target can fail silently
  and leave the human blind. Keep a pull-based fallback so the output is always discoverable. See
  [the output loop](output-loop.md).

## A good scheduled job, summarized
> Deterministic if it can be · schema-checked, never repaired, where a model feeds a script ·
> incremental · idempotent · silent when there's nothing to do · loud when it errors · guarded
> against collisions and lost work · and, if it writes to a public surface, paired with a
> [watchdog](watchdog-pattern.md).

---

_Related: [the watchdog pattern](watchdog-pattern.md) · [the autonomy ladder](autonomy-ladder.md) ·
[the output loop](output-loop.md)._
