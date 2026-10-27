---
title: The triage scoreboard
layout: default
parent: Playbooks
nav_order: 4
---

# The triage scoreboard

A pile of open pull requests (or issues) is not a plan. The scoreboard turns it into a **ranked,
evidence-tagged review queue** so the maintainer always knows what to look at next and what state
each item is in. It's the Steward's central instrument.

---

## The idea
Compute, for every open item, a small set of **dimensions**, combine them into a single **composite
rank**, and render a living document sorted by that rank. Re-generate it on a schedule so it's always
current without anyone asking.

## Two kinds of dimension
- **Mechanical** (recomputed fresh every run, no judgment):
  - for a PR: CI status, mergeable/conflicting, how far behind the trunk, diff size, age,
    contributor trust score.
  - for an issue: age, cross-references (how many other items link to it), and whether an open
    PR would close it. An open PR lowers the issue's rank: someone is already on it.

  PRs and issues rank separately. Their mechanical dimensions differ, so their composites aren't
  on one scale.
- **Judgment** (set by a reviewer/agent, persisted across runs): `scope_fit`, `criticality`, `risk`,
  scored on [the default rubric](#the-default-rubric). These survive regeneration so a human's
  assessment isn't lost when the mechanical data refreshes.

Keep the two separate in storage: mechanical data is disposable and re-derived; judgment data is
precious and persisted.

## The default rubric
The three judgment dimensions need a shared scale. Without one, two boards can't be compared and
the weights have nothing fixed to tune against. This is a default: replace it if your project
values something else, and keep four things when you do: named dimensions, a stated range, a
stated direction, and a written anchor for every level. Until your project writes a replacement
beside this playbook, the default applies and the board validates against its range.

Each dimension is an integer from 0 to 3. Higher always means *pick this up sooner*.

| Dimension | Measures | 0 | 1 | 2 | 3 |
|---|---|---|---|---|---|
| `scope_fit` | how directly the item serves a scope anchor | serves none | serves one in part | serves one plainly | the anchor can't be met without it |
| `criticality` | the harm the item fixes or reports | none, or already resolved | cosmetic, or an inconvenience | a shipped feature fails | data loss, or a core path fails |
| `risk` | the cost of leaving the item alone | nothing changes | the cost grows slowly | it worsens on a known trigger | it's worsening now, or another open change or issue you can point at is blocked on it |

What the table can't show:

- **Criticality is the harm; risk is whether the harm grows.** A broken export with no way around
  it is criticality 2. If nothing else breaks while it waits, it's risk 0.
- **A workaround lowers criticality by one level**, and never below 1.
- **A feature fixes no harm**, so its criticality is 0 and its rank comes from `scope_fit` and
  `risk`.
- **Score from what you found, not from what the item says.** The item's own text is a claim.
- **Risk is not the danger of merging.** That question picks the PR's lane and has no dimension
  here. For an issue, `risk` is the cost of the reported harm staying unaddressed.
- **`scope_fit` 0 is a human's value:** an out-of-scope item a maintainer chose to keep open. An
  agent that finds no anchor takes the out-of-scope path and writes no 0. An item that could be
  argued in or out of scope is escalated, not graded.
- **A suspected vulnerability gets no judgment.** Run the
  [vulnerability divert](../reference/security-spine.md#6-the-vulnerability-divert) and write no
  score and no severity flag. The board is committed, and either would confirm in public what the
  divert keeps private. The board still lists the item under
  [not yet judged](#not-yet-judged) like any other unjudged item, since a missing row would be its
  own signal. If the divert fires after a
  judgment was written, change nothing on the board: a retraction is a visible diff too. Note the
  judgment in the private record; whether to change it is the human's call, made with the rest of
  the private handling.
- **An agent writes only a dimension that is empty.** A dimension already on the board, set by a
  human or an earlier run, stands. An agent that disagrees says so in its output and leaves it
  alone. An empty dimension counts as unjudged for that dimension.

### Severity is a flag
Severity isn't a fourth scale. It's a flag stored with the judgment, and the refresh doesn't
recompute it.

- An agent sets the flag only when criticality is at the top level *and* the judgment cites
  evidence that doesn't come from the item's author: a line on the trunk, a failing check on the
  trunk, or a report from someone else whose claim the agent then confirmed on the trunk, by
  reading or with a repro it wrote itself under
  [the sandbox rule](../reference/security-spine.md#4-the-sandbox-untrusted-code-execution). The
  item's own text, diff and checks don't count, and neither does a report's say-so. Cite the trunk
  confirmation; name the report only where it already sits on a public surface of the project.
- A human may set the flag without citing anything.
- Whoever changes criticality decides the flag again. An agent writes neither once either is on
  the board.

### The scope gate and the scope grade
The scope gate decides in or out. `scope_fit` grades what the gate let in. Two cases fall outside
the grade:

- **Waiting on a human.** An item escalated as uncertain, or out of scope with the close not yet
  sent, gets no judgment. The board treats it like any item nobody has judged yet: listed under
  [not yet judged](#not-yet-judged), judgment columns empty. An empty judgment says nothing about
  the item. When the human rules it in scope, triage resumes and records the judgment.
- **Bypass.** A health fix (a bug, security or reliability fix on a shipped feature) skips the
  gate, so there's no `scope_fit` to give. Record the bypass marker, `bypass`, in place of
  `scope_fit`. The composite reads it as the plain in-scope level, 2 in the default; a replacement
  rubric names its own. The bypass means "don't re-litigate whether the feature should exist", not
  "central to an anchor", and the fix earns its rank through criticality.
  An issue earns the bypass marker when the agent confirmed the failure in a shipped feature on
  the trunk, by reading or with a repro under
  [the sandbox rule](../reference/security-spine.md#4-the-sandbox-untrusted-code-execution). A
  report's say-so doesn't: an unconfirmed bug report goes through the anchors like any other
  issue. A failure that, once confirmed, has vulnerability shape is a
  [divert](../reference/security-spine.md#6-the-vulnerability-divert) hit whenever it's found:
  no judgment, no bypass marker, no severity flag, and it's routed privately as the divert says.

## The composite
A weighted sum of the dimensions, tuned so the ranking matches "what a maintainer would actually
pick up next." Weights are a knob you adjust as you learn what your project values (e.g. how much to
weight contributor trust vs. raw criticality). Promote items carrying the
[severity flag](#severity-is-a-flag) to the top regardless of their composite (the severity
spotlight). Judgment dimensions should outweigh mechanical ones: the mechanical dimensions say how
an item stands, the judgment says whether it matters. For issues, cap or scale the mechanical
dimensions so their combined range in the composite is smaller than one level of the
lowest-weighted judgment dimension: age and cross-references then only break ties between equal
judgments.

### Not yet judged
An item with no judgment at all can't be ranked against judged ones: its composite rests on
mechanical dimensions alone, a different scale. The board lists every such item, per kind, in a
section titled **Not yet judged**, after the spotlight and before the ranking. The section opens
collapsed: its count and the first five in mechanical order, with every other member listed
beneath. The "review these first" short-list draws from this section and the ranking both.

The section records only that no judgment exists. An item can be there because it's new,
untriaged, escalated, halted by triage's confidence gate, on hold, in draft, or diverted. The
title names none of these and the board shows none of them per row, so no member reads as any
one of them.

An item with some judgment dimensions set stays in the ranking. Each empty dimension counts as
unjudged for that dimension. The severity flag counts as judgment: a flagged item is in the
spotlight and nowhere else.

### A dimension that carries no signal
A mechanical dimension that takes the same value for every item of a kind on the board is
**inert**: it adds nothing to that kind's ranking. Check each run, per kind. Drop an inert
dimension from that kind's composite and name it in the board's header. The usual case is a
dimension that reads labels on a backlog that carries none: unchecked, it scores the same for
everyone and nobody notices. A board that spans several repos counts a dimension only when it's
live in every repo on the board; otherwise one repo's missing labels shift its items against
every other repo's. A dimension is live in a repo when the source it reads exists there (for a
label dimension, its labels are declared or in use); a repo with fewer than two items of a kind
doesn't decide.

## Evidence-readiness tags
Beyond rank, show **which review streams have landed** for each item — turning the board from a
*ranking* into a *readiness view*. For PRs that might mean: automated code review present? visual
preview present? deep-review dossier cached? A compact per-row marker (✓ present / · not yet) lets
the maintainer see at a glance which items are fully evidenced and which are still settling.
Presence ≠ clean — it means the evidence *exists to review*; the authoritative gate still runs.

## Make it self-refreshing
Run the generation on a schedule ([scheduled-jobs](scheduled-jobs.md) rules apply): pull live
metadata, recompute mechanical dims, merge in persisted judgment dims, render, commit. The maintainer
never has to ask for a fresh scan — the board is current when they open it. A companion "review these
first" curated short-list can ride on top for the highest-priority handful.

## Why it works
- It **separates ranking from doing** — the agent ranks continuously and cheaply; the human (or a
  Band-B session) does the expensive review on the top of the list.
- It makes **state legible** — at a glance you see what's ready, what's blocked, what's waiting on
  whom.
- It's **honest about evidence** — the readiness tags stop "green CI" from masquerading as "ready to
  merge."

---

## Skill for this
- `triage-scoreboard` — compute dimensions, rank, render the living board + the curated short-list.

_Related: [PR lifecycle](../lifecycle/pr-lifecycle.md) ·
[contributor recognition](../lifecycle/contributor-recognition.md) · [scheduled jobs](scheduled-jobs.md)._
