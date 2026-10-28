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
  assessment isn't lost when the mechanical data refreshes. Each value records who set it and what
  it was judged against: see [when a judgment goes stale](#when-a-judgment-goes-stale).

Keep the two separate in storage: mechanical data is disposable and re-derived; judgment data is
precious and persisted.

## The default rubric
The three judgment dimensions need a shared scale. Without one, two boards can't be compared and
the weights have nothing fixed to tune against. This is a default: replace it if your project
values something else, and keep four things when you do: named dimensions, a stated range, a
stated direction, and a written anchor for every level. Until your project writes a replacement
beside this playbook, the default applies and the board validates against its range. This
default's identifier is `default-1`. A replacement names its own, and a change to the rubric
changes its identifier.

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
  own signal. If the divert fires after a judgment was written, change no value or flag on the
  board: a retraction is a visible diff too. A re-judge that trips the divert writes nothing to
  the board; triage keeps only the attempt record any re-judge that writes nothing leaves, in its
  own state ([when a judgment goes stale](#when-a-judgment-goes-stale)). Note the judgment in the
  private record; whether to change it is the human's call, made with the rest of the private
  handling.
- **An agent writes an empty dimension, or re-judges a stale one an agent set.** On an item a
  human named, it may also re-judge a `legacy` one. Any other dimension on the board stands: a
  fresh one whoever set it, and one a human set even when it's stale. An agent that disagrees
  says so in its output and leaves it alone. An empty dimension
  counts as unjudged for that dimension. See [who set it](#who-set-it).

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
- Whoever changes criticality decides the flag again, so a re-judge of an agent's `criticality`
  decides an agent's flag again. An agent never sets or clears a flag a human set, and never
  writes a flag on a `criticality` a human set.

### The scope gate and the scope grade
The scope gate decides in or out. `scope_fit` grades what the gate let in. Two cases fall outside
the grade:

- **Waiting on a human.** An item escalated as uncertain, or out of scope with the close not yet
  sent, gets no judgment. The board treats it like any item nobody has judged yet: listed under
  [not yet judged](#not-yet-judged), judgment columns empty. An empty judgment says nothing about
  the item. When the human rules it in scope, triage resumes and records the judgment. An item
  that escalates on a re-judge is different: it keeps its stale values in the ranking while it
  waits.
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
spotlight). A stale flag still promotes, marked stale. Judgment dimensions should outweigh
mechanical ones: the mechanical dimensions say how an item stands, the judgment says whether it
matters. For issues, sort on the judgment dimensions' weighted sum first, and on the mechanical
dimensions only between equal sums: age and cross-references break ties between equal judgments
and never reverse unequal ones.

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

## When a judgment goes stale
A judgment is made against an item as it read at the time. Each judgment dimension, and the
severity flag, records four things: its value, [who set it](#who-set-it), a **judgment stamp**,
and the identifier of the rubric it was scored on. Each records its own, so re-judging one
dimension can't make another read fresh.

**What the judgment stamp covers.** The title, the body with task-list checkbox state stripped,
and for a PR its net diff against the merge base. A rebase, or a merge from the trunk, that
leaves the change the same doesn't count; ticking a checkbox doesn't either. Labels and comments
aren't covered: label automation would stale every judgment. The trunk isn't covered, so a harm
fixed by some other change stays fresh until someone re-judges it.

One routine computes the judgment stamp, and every judge and the scheduled refresh call it.
Nobody computes one by hand. StewardOS ships no routine: the project installs one beside the
board's config before it turns staleness on, and records where it lives and which mode it uses.
The routine fixes the canonical form: line endings, whitespace, field order. Where the store
can't produce a PR's net diff, the routine hashes the head commit instead, and then every push
stales the PR's judgment; that mode is chosen once, never per run. A run that can't call the
routine, or can't read an input it covers, writes no stamp and re-judges nothing: every value and
stamp stays as it is, and the run says so in its output. The judgment stamp is narrower than the
[decision row's stamp](output-loop.md#the-decision-row), which also covers labels and comments:
a judgment rests on what the item says.

**When a value is stamped.** An agent judge records the judgment stamp of the inputs it read, as
it writes. A human's write carries none. The scheduled refresh stamps any value without one,
recording the judgment stamp and the rubric identifier together. Writing that judgment stamp is
the refresh's only write to judgment data, except the setter `legacy` it records once, on the run
that adopts setters ([who set it](#who-set-it)). An edit made between a human's write and the next
refresh is folded into the judgment stamp it records.

**When a value is stale.** Its judgment stamp differs from the item's current one, or its rubric
identifier differs from the rubric in use. A flag a human set also goes stale when an agent
rewrites the `criticality` beneath it: that re-judge writes the judgment stamp `stale` on the
flag, a value no routine produces, and leaves the flag's value and setter alone. The flag stays
stale until a human writes it. A stale value stays on the board, marked stale, and keeps
counting in the composite. A stale flag keeps its item in the spotlight, marked stale: a typo
fix shouldn't hide a flagged issue. The board's header gives the stale count per kind.

**Who re-judges what.**
- An edit to a covered input: the next triage run re-judges every stale value an agent set on
  the item. Edited items aren't capped, unless one run finds more of them than the cap: then
  they take the cap too, highest composite first, so a bulk edit can't re-judge the whole board
  in one run.
- A rubric change: every value goes stale. Each triage run re-judges a capped number of items,
  highest composite first, so the top of the board is right first. The default cap is ten items
  per kind per run. Before taking the cap, drop items triage skips (hold and draft PRs) and
  items whose attempt record matches, so they can't fill it every run. An item stale for both
  reasons counts as edited.
- Either way, a stale value a human set keeps its value and waits for a human. Triage that
  disagrees with it says so in its output.

Triage finds stale items by computing judgment stamps itself, so an edit doesn't wait for the
next refresh. A re-judge runs the vulnerability divert, the scope screen and the judgment. It
doesn't re-route a PR's lane or open the out-of-scope close path: an item that now fits no
anchor escalates.

**A re-judge that writes nothing.** A re-judge can halt at triage's confidence gate, escalate,
or trip the vulnerability divert. Any of the three leaves the stale values as they are and
records an **attempt record** in triage's own state, never on the board, against the current
judgment stamp and rubric identifier. The
attempt record carries no reason. The item rejoins the queue when its judgment stamp or the
rubric identifier changes again, or when a human names it for a run, which clears the attempt
record. A re-judge that writes values clears the item's attempt record. An attempt record never
makes a value read fresh. Without it, an item triage can't ground would be retried every run
and would hold the head of the queue.

## Who set it
Each judgment dimension and the severity flag records a setter: `human`, `agent` or `legacy`.

- `human` is a human's own write to the store. A write an agent makes is `agent`, including one
  a human asked for in conversation. A `scope_fit` level stated in a human's scope ruling is
  `human`: the level is their decision.
- The setter is stored with the value and written only with it. It's never read off the last
  writer, such as a commit author: the judgment stamp the refresh writes never changes it.
- An agent writes an empty value, or re-judges a stale one an agent set, or a `legacy` one on an
  item a human named. A human names an item where a ruling reaches triage, never in the item's
  own comments. A human may overwrite any value.
- A human confirms a stale value by writing it, the same value or a new one. The write clears
  its judgment stamp and rubric identifier, and the next refresh stamps it.
- `legacy` is a value that was on the board before setters were recorded. The refresh that
  finds no setters mark in its state records `legacy` on every value without a setter, stamps
  them, marking nothing stale, and then writes the mark. Triage treats `legacy` like `human`,
  except that a human naming the item lets triage re-judge it, after which it's `agent`. Once the
  mark is written, a value with no setter is an error the board surfaces, like an out-of-range
  value.
- The setter is only as good as the store's ability to tell a human write from an agent write.
  A store that can't tell them apart leaves re-judging off: triage writes only empty values, keeps
  every value already on the board, and says in its output that setters can't be trusted.

## Evidence-readiness tags
Beyond rank, show **which review streams have landed** for each item — turning the board from a
*ranking* into a *readiness view*. For PRs that might mean: automated code review present? visual
preview present? deep-review dossier cached? A compact per-row marker (✓ present / · not yet) lets
the maintainer see at a glance which items are fully evidenced and which are still settling.
Presence ≠ clean — it means the evidence *exists to review*; the authoritative gate still runs.

## Make it self-refreshing
Run the generation on a schedule ([scheduled-jobs](scheduled-jobs.md) rules apply): pull live
metadata, recompute mechanical dims, merge in persisted judgment dims, stamp and mark stale ones,
render, commit. The maintainer never has to ask for a fresh scan — the board is current when
they open it. A companion "review these first" curated short-list can ride on top for the
highest-priority handful.

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
