---
name: triage-scoreboard
description: Compute and render the living, ranked triage board of open work — mechanical + judgment dimensions into a composite rank, with evidence-readiness tags. Run on a schedule so the board is always current.
---

# triage-scoreboard

**When to load:** generating or refreshing the [triage scoreboard](../../docs/playbooks/triage-scoreboard.md).
Band A (read-only, deterministic where possible). Ideal as a scheduled job.

## Steps

1. **Pull live metadata** for every open item: for PRs, CI status, mergeable/behind, size, age,
   author; for issues, created date, cross-reference count, and open PRs that would close it. Read
   repos from `config.yaml`.
2. **Recompute mechanical dimensions** fresh each run (disposable): CI, conflict state, behind-count,
   size bucket, contributor trust score (computed by [`contributor-trust`](../contributor-trust/SKILL.md)
   from the [trust ledger](../../docs/lifecycle/contributor-recognition.md)). PRs and issues have
   different sets ([the playbook](../../docs/playbooks/triage-scoreboard.md#two-kinds-of-dimension)).
   A dimension with one value for every item of its kind is
   [inert](../../docs/playbooks/triage-scoreboard.md#a-dimension-that-carries-no-signal): drop it
   from that kind's composite and record it for the header.
3. **Merge in persisted judgment dimensions** (scope_fit, criticality, risk) and the severity flag
   from the prior board — these survive regeneration so human/agent assessments aren't lost.
4. **Compute the composite** = weighted sum of dimensions (weights from config; tune to match "what
   I'd pick up next"). Read the bypass marker (`bypass`) as the plain in-scope level of the rubric
   your project uses ([the default](../../docs/playbooks/triage-scoreboard.md#the-default-rubric),
   or its replacement). Rank PRs and issues separately. An item with no judgment at all leaves the
   ranking for the [not yet judged](../../docs/playbooks/triage-scoreboard.md#not-yet-judged)
   section; an item with some judgment ranks, and an empty dimension counts as unjudged for that
   dimension. Promote items carrying the
   severity flag to a spotlight at the top; the flag counts as judgment, and a flagged item is
   listed nowhere else.
5. **Tag evidence-readiness** per item: which review streams have landed (automated review present?
   visual preview? deep-review dossier?). Compact ✓/· marker. Presence ≠ clean.
6. **Render** the living board: the spotlight, then per kind the not yet judged section (its count
   and first five in mechanical order) and the ranking by composite; name inert dimensions in the
   header; add a curated "review these first" short-list drawn from both.
   Persist the computed data as a machine-readable artifact for other jobs.
7. **Commit** following [scheduled-job](../../docs/playbooks/scheduled-jobs.md) rules
   (idempotent, silent-on-no-op).

## Pitfalls
- **Keep mechanical and judgment dims in separate storage** — mechanical is re-derived and
  disposable; judgment is precious and persisted. Don't let a refresh wipe a human's assessment.
- **A dimension that reads labels goes inert without an error** — on a backlog with no labels it
  scores the same for every item. Name it in the header; never let it count silently.
- **An out-of-range value is an error, not a number to clamp** — surface it. In range means an
  integer in the rubric's range, the bypass marker in `scope_fit`, or an empty cell. A clamped
  value hides a judge scoring on a different rubric.
- **Evidence presence is not a verdict** — `✓` means the evidence exists to review, not that it's
  clean. The authoritative gate still runs at merge.
- **Re-run cheaply** — this should be incremental and idempotent; it's a read-only ranking, not an
  action.

## Verification
- Board re-renders with current data; judgment dims preserved across runs.
- Composite ordering matches intuition for the top handful.
- Evidence tags reflect actual review-stream presence.
