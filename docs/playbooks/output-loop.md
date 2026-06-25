---
title: The output loop
layout: default
parent: Playbooks
nav_order: 6
---

# The output loop

A steward that produces excellent triage but the human never sees has done nothing. The **output
loop** is the other half of every Band A/B job: the path from *"the steward produced a draft"* to
*"the human found it, acted on it, and the local state reflects that the action was taken."* The
skills cover how to *produce* good output; this playbook covers how that output reaches a person and
stays honest afterward.

> Producing output is not the same as the human receiving it. A draft nobody discovers, and an
> actioned item that still looks pending, are both failures of the loop — even when the reasoning
> that produced them was perfect.

This is a **documented default, not a mandate.** The framework prescribes the *loop*; it does not
prescribe a filesystem layout. Adopt the three rules below and shape the storage to your project.

---

## Two failure modes it prevents

**The blind steward.** The job runs, produces a useful draft, and tries to deliver it to a chat
platform — but delivery silently fails (a misconfigured target, an unsupported platform, a transient
outage). The run reports success; the human sees nothing and doesn't know to look. The work happened
and reached no one.

**The stale state.** The human reads a draft, posts the reply, files the issue — and the draft sits
in the queue unchanged. Hours later the local state still shows it as pending. Now the state can't be
trusted, and the human is forced back to cross-referencing the live system by hand to learn what's
actually been done — which defeats the point of keeping local state at all.

Both are *operational*, not methodological. The triage was right; the loop around it leaked.

## The shape

```
   [scheduled job] ──produces──▶ actionable output  ──appended──▶ [INDEX] ◀── human checks (pull)
         │                              │                            │
         │ also writes                  │                       reads the one
         ▼                              │                       place, always
    [run log / audit trail]            │                            │
    (disposable, steward's own)        ▼                       acts on the item
                                   (optionally) pushed              │
                                    to a chat platform        ┌─────┴─────┐
                                    as an enhancement      reconcile    nothing
                                    — if it fails, log         │        to do
                                    and move on; the      mark done +  (silent)
                                    INDEX still has it     archive it
```

## The three rules

### 1. Discovery over delivery
Maintain one **pull-based index** of actionable output that the human can always check. Pushing a
notification to a chat platform is a convenience layered *on top* — never the only path. Push
delivery is platform-dependent and can fail silently; a pull index cannot leave the human blind. If
a configured delivery fails, **log the error and keep going** — the item is still in the index.

> Delivery is an enhancement layer. Discovery is the contract. If you can only build one, build the
> index.

### 2. Separate the audit trail from the actionable output
A job produces two kinds of files, with different consumers and different lifecycles. Don't mix them:

| Class | Examples | Who reads it | Lifecycle |
|-------|----------|--------------|-----------|
| **Audit trail** | Run logs, scan summaries — *what the steward looked at* | The steward (to diff runs) | Disposable; prune on a window you choose |
| **Actionable** | Draft replies, issue drafts, review summaries — *what needs a human* | The human maintainer | Lifecycle-managed; archived once actioned |

When the two share a directory, review cost grows linearly with run count: every "here's what I
scanned, nothing to do" log buries the one "here's a draft that needs you." This is the
[silent-on-no-op](scheduled-jobs.md#silent-on-no-op-the-most-important-rule) rule applied to files —
don't make the human wade through noise to find signal.

### 3. Keep the state honest
Local state the human can't trust is worse than none. When a Band C action is taken (a reply posted,
an issue filed, a PR merged), the steward **reconciles**: mark the item done and move it out of the
review queue. Do it [idempotently](scheduled-jobs.md#idempotent) so a re-run never resurrects a
handled item, and reconcile to live ground truth rather than blindly appending. If the steward's
state and reality disagree, every consumer downstream has to verify by hand — and the local state has
become a liability instead of a convenience.

The trick is *how* the steward learns an action was taken — and the answer is to re-derive it from
the live system, not to wait for the human to tell it. On the next run, for each open item, check the
ground truth the action would have changed: does the issue now have a maintainer reply? Is the PR
merged? Was the draft issue actually filed? If so, the item is done — flip its status and archive it.
This is the [watchdog](watchdog-pattern.md) instinct applied to your own queue: the action's own
record says *what to check*, live state says whether it happened.

## What this can look like

One layout that satisfies the loop. **Adapt the names and locations to your project** — the rules
are the contract, not these paths:

```
state/
  index.md       # the review queue: one line per actionable item, newest first, each with a status box
  actionable/    # the drafts themselves — replies, review summaries, issue drafts
  runs/          # audit trail — what each run scanned; pruned on a retention window you pick
  archive/       # items moved here once actioned
```

A workable index line:

```
- [ ] 2026-06-24 · pr-triage · #482 looks mergeable, needs a rebase note → actionable/2026-06-24-pr-482.md
```

The human reviews `index.md`, opens the linked draft, acts, and the next steward run flips the box to
`[x]` and moves the file to `archive/`. **Retention:** give the disposable classes (run logs,
archived drafts) a window so they don't grow without bound; never prune the persistent state
(scoreboard, ledgers, trust data) — that's the system's memory. Pick the windows that fit your
cadence — as a rough starting point, deployments have found ~7–14 days works for hourly jobs and
30+ days for daily ones — then tune. The framework doesn't dictate the numbers.

**Already running with mixed output?** Migrating is a one-time, non-destructive move: split the
existing files into the two classes (audit-trail vs. actionable), start a fresh index from the items
still open, and let the next run's reconcile pass archive anything that's already been actioned. No
history is lost — the audit trail just moves to its own place.

## The payoff

The human checks **one place**, trusts what it says, and a broken chat integration can never make the
steward go dark. Discovery-as-default is what turns "the crons are running" into "the work is
actually reaching the person who acts on it" — and an honest local state is what lets that person
glance at the queue instead of re-deriving reality from the live system every time.

---

_Related: [designing scheduled jobs](scheduled-jobs.md) · [the triage scoreboard](triage-scoreboard.md) ·
[the watchdog pattern](watchdog-pattern.md)._
