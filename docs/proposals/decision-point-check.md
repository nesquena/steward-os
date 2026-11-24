---
title: "Proposal: the decision-point check"
layout: default
nav_exclude: true
---

# Proposal: the decision-point check

> Status: proposal. Not yet a gate rule. It replaces the wording in closed PR #126 ("break each
> guard").

## The problem

[Gate 1](../lifecycle/quality-gates.md#1-the-test-suite--the-primary-line) asks every fix for a
regression test, and the [pre-fix discipline](../lifecycle/quality-gates.md#the-pre-fix-discipline-before-any-code-changes)
writes that test first, so it fails before the fix. Reverting the whole fix shows that *something*
in it is tested. It doesn't show that each decision in it is: a check can be tightened in one place
and loosened in another, built from several conditions, or removed in favour of another check. Then
one side can go red while the other side goes untested.

#126 tried to close that gap with one rule: break each guard the change adds, changes or removes,
on both sides. Four review rounds found shapes the rule couldn't be followed for. The owner closed
it on that ground: a gate rule that can't be followed as written for some changes does more harm
than good. After round 4, five cases were still open:

1. A refuser outside the repo (a proxy, a framework default) still refuses a required case, but
   "can't be produced in the tree" lets the check be named and waived.
2. The still-refused side doesn't tie the failing test to the case it is about.
3. A change to a check's condition that lives only in config isn't covered.
4. The breaks edit the pinned copy every other leg runs from.
5. A removal with no behaviour change (a moved check, or one another check already covers) can
   never satisfy "put it back and a test must fail".

## The idea: start from cases, not from mutants

#126 started from the code: break the guard, and some test must fail. That fails whenever no case
exists for a break to expose (case 5), or no code in the tree can be broken (case 1). This proposal
starts from the **cases** instead, and asks for a break only where a case gives it something to
expose.

Gate 1's existing rule stays as it is: the fix's regression test fails when the whole fix is
reverted. The decision-point check adds a finer requirement on the same tests.

### Terms

"Guard" already names the [injection guard](../reference/security-spine.md), so this proposal uses
other words.

- **Decision point**: code, or configuration that code reads, that decides whether an input is
  refused, allowed, or sent down one path rather than another. An allowlist entry, a threshold or a
  pattern in a config file counts just as an `if` does (case 3). Prose instructions to an agent (a
  skill's refusal rule, say) are out of scope: the differential and the reading passes cover them.
- **Touched decision point**: one the change adds, edits, removes or moves.
- **Changed case**: an input whose outcome the change alters: newly refused, newly allowed, or sent
  down a different path.
- **Kept case**: an input a touched decision point decided before the change whose outcome must not
  change.
- **Decider**: whatever decides a case after the change. That can be the same decision point,
  another one in the tree, or something outside it. A case can have more than one decider.
- **Break**: the smallest edit that restores a decision point's old decision for a named case while
  the tree still loads: a flipped condition, the old constant, the config entry's old value. It is
  not a literal line revert, which can fail to load when the change also renamed a field or changed
  a signature.

### The case list

The reviewer derives the case list from the diff. The author's list is input to it, not the list.
For each touched decision point, and each condition of a combined one, the list holds at least one
case on each side, and a boundary input where the condition has a boundary. When the differential
applies, every difference it shows must map to a listed changed case; a difference that maps to
none is a finding. This closes the loophole where an edit tightens one condition and loosens
another, and only the tightened side is listed.

### The rule

- **A changed case** needs a named test that runs that input and asserts its new outcome, and fails
  when the decision point that changed it is broken for that case.
- **A kept case** needs a named test that runs that input and asserts its outcome, and fails when
  its decider is broken for that case. The verdict names the decider (case 2).
- **Several deciders.** When a break leaves a case's outcome unchanged because another decider still
  decides it, the verdict names that decider, and the test must fail when all of the case's deciders
  are broken together. Each decider also needs a case it alone decides. One that has none is
  recorded as redundant, and a redundant touched decision point is a finding. Pick kept-case inputs
  that reach exactly one condition wherever the decision point allows it.
- **A break that doesn't load** is remade as a smaller edit. It is never waived.

### Judging a break

Run the named tests with the runner's own test selection. A break counts when the runner exits
non-zero and its own per-test report shows the named test failing on an assertion, not erroring.
That keeps gate 1's rule of judging a run by the runner's exit status and summary, never by a
filter of its output. Other tests failing in the same run neither count nor void it.

### Allowed outcomes other than a failing test

Only two, and the verdict names each one:

- **No case exists** for a side. A removal with no behaviour change has no changed case, so it has
  no put-back break, but its kept cases still need their deciders broken (case 5). "No case" needs
  the reviewer's own argument. Where the differential applies, it must also show no difference on
  that decision point's inputs. A touched decision point with no case on either side is a dead-code
  finding, not a pass. Being hard to set up is not "no case": the break still has to be made.
- **The decider is outside the tree** (a proxy, the framework, the host), for a kept case or a
  changed one (a dependency bump whose new default refuses an input, say). The case is tested at
  the boundary the tree controls, such as the config the tree sends it, wherever that is possible.
  A stub of the external behaviour counts only after the reviewer checks it against the cited
  documentation. On an untrusted PR, a stub the contributor wrote counts only after that same check.
  The gate is **not all-clear** for that case until a human records an **external-decider
  acceptance** through the operator's authenticated direct channel: the case, the decider, the
  boundary-test evidence, and the head and trunk it was judged on. It is kept where receipts are
  kept, and a new head or trunk voids it, like a receipt (case 1).

### Where the breaks run

Breaks never edit the pinned copy every other leg runs from (case 4). Each break runs in an
independent copy built from the pinned commit under the
[spine's pinning rules](../reference/security-spine.md#4-the-sandbox-untrusted-code-execution): a
separate clone or an export, never a worktree that shares the pinned copy's Git directory, whose
hooks and config the trusted copy still uses. Afterwards the pinned copy must still match: its HEAD
is the pinned commit, and a status that includes untracked and ignored files is empty. On an
untrusted PR the breaks run where the sandbox rule puts the suite, and a human-run receipt can
supply them like the other execution legs.

## The five cases, answered

| Open case | Answer |
|---|---|
| 1. Refuser outside the repo | Tested at the boundary where possible. Otherwise a named external decider, which blocks all-clear until a human records an acceptance; a new head voids it. |
| 2. Still-refused side not tied to a case | Every kept case is a named input with a named decider, and a break counts only when that test fails on an assertion. |
| 3. Config-only changes | Configuration that code reads is a decision point. Its break is the entry's old value. |
| 4. Breaks edit the pinned copy | Breaks run in an independent clone or export, never a shared worktree, and the pinned copy is checked clean afterwards. |
| 5. Removal with no behaviour change | No changed case, so no put-back break. Each kept case's decider is named and broken instead. |

## Cost

The check is a gate 1 leg, so gate 5's fresh re-run before merge repeats every break on each new
head, and on an untrusted PR at default settings each break is one more human-run leg. A PR with
many touched decision points pays for that on every fixup commit.

## Where the text would land

One PR after this design is accepted, all pinned in `test/skills_contract_test.rb`:

- [Gate 1](../lifecycle/quality-gates.md#1-the-test-suite--the-primary-line): the rule, as one
  bullet, named "the decision-point check".
- `skills/pr-deep-review/SKILL.md`: step 5 lists the check among gate 1's legs, step 6's receipt
  scope names it, and Verification gets one line: every changed case and kept case has its failing
  test or its named outcome.
- The sandbox rule: the receipt scope names the check, and the external-decider acceptance is added
  as a record beside the receipt.
- [Gate 1's untrusted-code note](../lifecycle/quality-gates.md#untrusted-code-execution) names the
  check beside the suite and the differential.
- The [glossary](../reference/glossary.md) defines decision point, changed case, kept case, decider
  and break.

## Decisions for the maintainer

1. **External deciders.** Should one block all-clear until a human records an acceptance
   (proposed: fail-closed, like a skipped run leg), or pass as a named dependency?
2. **Rollout.** Should the check land as a gate rule at once, or first as a recommendation for a
   few PRs, to measure the cost above? Proposed: recommendation first.
3. **Prose rules.** steward-os is mostly prose, so with prose out of scope the check rarely applies
   to this repo itself. Keep prose out (proposed), or design a separate check for prose refusal
   rules?
