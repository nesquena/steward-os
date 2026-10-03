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

**The sanctioned middle path is notify-on-findings.** The two obvious delivery modes are both traps:
push *every* run to a chat and you train the human to ignore the channel (and an active session gets
interrupted by "nothing to do" noise); push *nothing* and a run with real findings sits unseen until
someone thinks to check the index. Neither is right. The middle path: **always write to the index
(discovery), and push a one-line summary only on the runs that produced actionable items** — silent
otherwise, exactly like [silent-on-no-op](scheduled-jobs.md#silent-on-no-op-the-most-important-rule).
The human is neither spammed nor blind, and the index stays the durable source of truth regardless of
whether any push succeeded.

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

**Reconcile in both directions.** It's not enough to remove items that are done — the index must also
*gain* the items it never saw. A run only ever writes about the work it touched, so an item that was
open the whole time but simply never came up in a run is silently absent from the queue: still live,
never actioned, invisible. So reconcile the index against the **complete** live open set both ways:
drop what reached a terminal state, and add any still-open item missing from the index. Otherwise the
queue quietly drifts from "everything that needs a human" to "the subset a run happened to mention."

## The decision row

The index line says an item is waiting. The **decision row** is what the human reads before
deciding: the content the index line points to. A human who approves from a summary has approved
something they haven't seen, so the membrane is only as good as the decision row.

Any item that waits on a human before a public or irreversible write carries one. That's every
Band C approval, and the final call of a Band B task (the merge, the release).
A Band B question with no write behind it (a design call, a dedupe pick) needs only the first two
properties.

Like [the state handoff](state-handoff.md#the-contract-mechanism-neutral), this is a contract
stated as properties, not a mechanism. A decision row can live in a markdown file, a chat message,
a terminal prompt, or a dashboard. It's also a bar, not a description of today: the properties and
the three rules below say what a skill should do, and the skills that prepare human-gated work
predate this section.

1. **One recommendation, stated first.** The action the agent proposes, and the capability it
   belongs to. A list of options with no pick isn't a recommendation.
2. **Evidence that resolves.** Each claim the recommendation rests on points at something the human
   can open: a commit, a file and line, an item number, a quoted line. Where a pointer can be
   checked without a model (the path exists, the commit is on trunk, the item is open), it's
   checked before the decision row is shown. If the evidence doesn't resolve, there is no decision
   row. The item itself stays in the index, as [rule 3](#3-keep-the-state-honest) requires of every
   open item; it just carries no recommendation yet.
3. **The exact write.** The full text that will be sent, verbatim. A summary of the text isn't the
   text. For an action with no text of its own (a close, a label, a merge), the exact write is the
   action and its target, plus any text that goes with it.
4. **The undo.** How the write is reversed, or a plain statement that it can't be. An irreversible
   approval is weighed differently, and the human needs to know which kind this one is.
5. **The state it was made against.** A stamp of the decision's inputs at proposal time: enough to
   tell later whether they changed. Include whatever would change the recommendation (title, body,
   labels, comments, linked changes, and any other item the evidence cites), not only the body.
   Leave out what wouldn't change it (a mechanical size label, the agent's own capture mark), and
   say which inputs the stamp covers, so the comparison before the write is reproducible and routine
   churn can't void an approval. When unsure, include it: a voided row costs one re-propose, a
   missed change costs a wrong write.

One workable form:

```
Recommend   close #482 as a duplicate of #310                     capability: issue close, Band C
Evidence    #310 is open and reports the same crash on the same path (src/sync.py:88)
Will send   close #482, with the comment:
            "Closing as a duplicate of #310, which tracks the same crash in the sync path."
Undo        reopen #482, delete the comment
Made at     #482 3f9c1a, #310 9b2e07    covers: title, body, labels, comments, linked changes
```

Three rules hold it together.

**What is sent is what the human approved.** The band says who may send: at Band C the human takes
the action, and where a reply starts the step that acts
([approval over chat](../lifecycle/community.md#human-in-the-loop-approval-over-chat)), that step
sends for them. Whoever sends, the stored write goes out as shown and nothing composes text after
the approval: no redraft, no tidy-up, no fresh summary. A sender with no model in it is the stronger
form, because it can't recompose. If the human edits the text, the edited text is the approved one,
and it's what goes out. Anything the decision row didn't show isn't sent. The rule is about what is
sent: a surface may normalize text on its side (line endings, whitespace, rendering), and that isn't
a breach.

**A decision row expires when its inputs change.** Immediately before the write, re-read the inputs
the stamp covers (the item, and any other item the evidence cites) and compare them with the stamp
from property 5. That's a comparison of stamps, not a fresh assessment. If they differ, the decision
row is void: send nothing, discard the approval, and prepare a new decision row against the new
state. An approval never carries over to a decision row the human hasn't seen. This is
[never authoritative, re-derive from live truth](state-handoff.md#the-contract-mechanism-neutral)
applied at the last possible moment.

**Accept and reject are both explicit.** Each costs the human one action, and neither is the
default. Silence isn't a decision, and a decision row that ages out wasn't approved. A refresh must
never replace a decision row the human is in the middle of deciding: a decision applies to the row
they saw, or to nothing. [Rule 3 of the loop](#3-keep-the-state-honest) says to re-derive what
happened from the live system rather than wait to be told, and that still holds for whether an
action was taken. A rejection is the one thing the live system can't show, because it changes
nothing there, so it's the one thing the human has to say. Record it against the item and its
stamp, so the next run doesn't propose the same write against the same state.

`autonomy.human_reachable_at` names *where* the human is asked. The decision row is *what* they're
asked with. A push to that channel may carry the whole decision row or only a pointer; either way
the index still holds the item, per [rule 1](#1-discovery-over-delivery).

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
[the watchdog pattern](watchdog-pattern.md) · [the state handoff](state-handoff.md) (the agent-to-agent sibling of this playbook)._
