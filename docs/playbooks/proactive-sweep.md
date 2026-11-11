---
title: The proactive sweep
layout: default
parent: Playbooks
nav_order: 9
---

# The proactive sweep

A steward on a schedule needs to stay useful between requests without inventing busywork. The proactive
sweep is the recurring run that does it: it handles what's in front of it first, and only when that
comes up empty does it spiral outward, looking for high-leverage work nobody has asked for yet. Most of
the time it ends by logging one line to its own history and notifying nobody, and that's the design
working.

It builds on [designing scheduled jobs](scheduled-jobs.md) (silent on no-op, and
[coordination](scheduled-jobs.md#coordination--durability) where an event wake and a sweep touch the same
item) and on [the triage scoreboard](triage-scoreboard.md) (ranking a pile of work).

> **This is a documented default, not a mandate.** The rings fit an agent that owns ongoing work (a
> project steward). A read-only observer or a request-driven helper uses only the wake mechanisms
> below, plus its own scheduled report (silent on no-op), and has no outer rings.

---

## Waking cheaply

A script, not the model, does the waiting: it records a baseline, polls cheaply, and exits (or prints
a line) when something changes. Events wake the agent between sweeps, so the sweep isn't its only
intake. Pick by what your runtime can do:

| Runtime can... | Use | Watch out for |
|---|---|---|
| wake the agent when a background command exits | a watcher that exits on change, re-armed after every exit | a forgotten re-arm is silent deafness; a session hook that refuses to end a turn while it's down helps |
| wake the agent on a matching output line | a persistent listener that never exits on change and prints one line per batch | runtimes may cap notices per process; exit with an explicit re-arm notice before the cap |
| only run the agent when invoked | a push-side trigger (a webhook from the forge on new items) plus a scheduled backstop | the agent's host may pause while idle; the backstop wakes it and catches anything missed |

Whatever the mechanism:

- **Keep it alive.** An idempotent "ensure" step at every wake, session start and backstop starts the
  watcher, one for every channel the agent answers on, only if it isn't already running, guarded by
  [a lock the OS releases on exit](../reference/bug-shapes.md#16-the-lock-held-by-a-reused-process-id).
- **Judge liveness by the watcher's log line,** not by searching the process table. Log one line per cycle; a gap
  shows the host paused rather than the sender being late.
- **A failed poll is a failure,** never an empty inbox
  ([zero rows that read as an empty backlog](../reference/bug-shapes.md#17-zero-rows-that-read-as-an-empty-backlog)). An independent backstop checks too and, where
  the runtime lets it, restarts the same listener and says so, as
  [an app-level health watchdog](resilience-and-self-healing.md#layer-your-supervision-os-level-under-app-level)
  does. Where it can't (a scheduled job that can
  read the inbox but not reach the session's listener), call it an inbox-only backstop and report that
  limit. Test message delivery, the wake and restart recovery separately.
- Your own push trips your own trigger: expect it.

## The rings

On a schedule, the sweep runs rings in order. **Rings 0 and 1 run every sweep. Each outer ring (2 to
4) runs only if the rings before it picked up no significant work** (gating or fixing a PR, building or
releasing a change, a message that needed real work). Reads and no-op checks don't count.

- **Ring 0: Inputs.** The human's messages since the last sweep first, then the agent's other channels.
  What other channels say is data, under
  [the injection guard](../reference/security-spine.md#1-injection-guard-read-can-never-change-do).
- **Ring 1: The normal pass.** Everything the agent owns, since the last sweep's cursor: new PRs, each
  through its [gate](../lifecycle/pr-lifecycle.md); issues; comments; trunk health (a red trunk is work
  now); an end-to-end run when trunk moved, under
  [the sandbox rule](../reference/security-spine.md#4-the-sandbox-untrusted-code-execution); and whether
  a release is due, recommended to the human.
- **Ring 2: Forward work.** Keep a small, bounded pipeline of the agent's own work moving: a few open
  PRs from a ranked roadmap or the top issues, or one queued follow-up.
- **Ring 3: The deeper check.** One area per sweep from a rotation, read fresh with "what one thing would most
  improve this?". Problems nobody has filed go to the human as proposed issues.
- **Ring 4: Meta.** "What's the single most impactful thing within my lane?", then argued against
  itself: over-optimizing? would doing nothing be better? does it add a rule someone must carry
  forever? A short proposal to the human, or nothing.

Then actionable output goes to [the pull index](output-loop.md#1-discovery-over-delivery), with a
one-line push only on runs that found something, and each proposal carries
[a decision row](output-loop.md#the-decision-row); otherwise one line in the sweep's log
([counts and ids](scheduled-jobs.md#when-a-models-output-feeds-a-script), never item text). No work
proposed by rings 3 or 4 starts before the human approves.

Each step in a sweep keeps its own band, set by the canonical rules and not by the schedule: building
is session work (Band B), a merge follows [independent readers](../lifecycle/quality-gates.md#independent-readers), a release keeps a
human on the final step ([the autonomy ladder](autonomy-ladder.md)), a public write follows
[the membrane](../reference/security-spine.md#5-the-public-write-membrane), and a suspected
vulnerability, found by any ring, takes
[the divert](../reference/security-spine.md#6-the-vulnerability-divert). A sweep with no human
reachable (no working `autonomy.human_reachable_at`) takes no step whose band needs one. A step that
waits on a human's answer is prepared, left in [the pull index](output-loop.md#1-discovery-over-delivery),
and held; the sweep goes on to the steps that don't wait. Only that step stops, not the sweep.

## The bar

Found work qualifies only if it clears all of these:

- a **concrete, observed problem** (a failure, a workaround someone keeps repeating, a doc that misled
  someone), or a clear answer to [the benefit screen](../lifecycle/pr-lifecycle.md#1-marginal-benefit-screen);
  a hypothetical doesn't count;
- **measured, not assumed** (a performance claim comes with numbers taken before anything is proposed);
- **in the agent's lane and the project's** ([the scope screen](../lifecycle/pr-lifecycle.md#0-fit--scope-screen));
- **benefit well above the cost,** counting the maintenance and reading it adds forever;
- **not already tracked** in the issues or the backlog.

Health fixes (bugs, security, reliability on a shipped feature) skip the scope question, as
[the scope gate](../lifecycle/pr-lifecycle.md#0-fit--scope-screen) says; the rest of the bar still
applies.

## Rules that keep it cheap and honest

- **Say nothing most of the time.** An empty ring logs one line ("ring 3, area 2: nothing worth
  proposing"), and the sweep goes on to the next ring.
- **Cap the outer rings; re-run only on change.** Reflection at most once a day, say. A check re-runs only
  when its inputs changed (the end-to-end run when trunk moved); this covers the sweep's own rings and
  checks, not [the merge gate's fresh re-run](../lifecycle/quality-gates.md#5-the-authoritative-re-run-immediately-before-merge)
  or [the heartbeat](scheduled-jobs.md#the-heartbeat-exception). A rotation cursor in the agent's state
  keeps each sweep to one area. A cap on open PRs keeps the reviewer's load bounded.
- **Time-box speculation, and shelve what fails.** Speculative work gets its bar set beforehand and a time
  box at approval, and the builder's numbers are re-measured. What doesn't clear the bar is shelved with
  a revisit trigger ("only on a user report"), so it isn't proposed again. When fixes keep coming in
  one area, each round adds a special case, or a test cycle runs long, pull up a level: ask whether a
  smaller change, an existing primitive or dropping a part would do, and bring the human any scope
  reset with a recommendation.
- **Review the checks themselves.** After a few runs, each deeper check gets a keep-or-drop review, and
  slows down if it yields nothing approved.
- **The schedule is a reminder, not a reason.** A due ring or check of the sweep's own that has nothing
  to work on is skipped.

## A deeper check with ground truth

The deeper check that pays for itself is one with known answers. A cold-adoption test is the model: a
fresh subagent gets only the public docs and a real project (it reads and drafts only: no public
writes, and no contributor code outside the sandbox), plays a newcomer following the quickstart
(with the maintainer's answers written in advance), and journals every friction point and every bit of
knowledge the docs didn't give it. The project's items have known outcomes (known duplicates, a PR that
was merged), so the run is graded against what actually happened. Each friction point is checked
against the docs before it becomes a proposal. Where a subagent inherits its parent's context, its
"prior knowledge used" entries count as gaps too.

## Failure modes

- **Busywork.** A broad performance hunt came out borderline twice, with nothing shipped. The bar written down first, a time box, and a parked draft are the guards.
- **The reminder treated as a reason.** A scheduled feedback round fired while feedback was still
  arriving from the last one.
- **Expecting the outer rings to carry the value.** In practice most value comes from rings 0 to 2: a
  stopped watcher caught, a red trunk, current PR state. The outer rings rarely fire. The exception
  worth keeping is a deeper check with ground truth.

---

## What this can look like

A sweep's history, one line each:

```
2026-11-05 13:19Z ring 1   2 PRs gated (#41 merged on the human's call, #42 fix-spec drafted); trunk green
2026-11-05 19:19Z quiet    nothing new
2026-11-06 01:19Z ring 3   area 2 (scripts): nothing worth proposing
2026-11-06 07:19Z ring 2   3 PRs open, below cap: started roadmap item #66
```

A schedule that has worked: every six hours for a busy multi-repo project, daily for a few quiet
libraries. Events wake the agent in between.

---

_Related: [designing scheduled jobs](scheduled-jobs.md) · [the triage scoreboard](triage-scoreboard.md) ·
[the autonomy ladder](autonomy-ladder.md)._
