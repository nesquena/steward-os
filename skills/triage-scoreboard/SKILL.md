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
3. **Merge in persisted judgment** (scope_fit, criticality, risk, the severity flag, each with
   its setter, judgment stamp and rubric identifier) from the prior board. Compute each item's
   judgment stamp with the shared routine. Stamp any value that has none, with the current
   judgment stamp and rubric identifier, setter unchanged; on the first run after adoption,
   record a value with no setter as `legacy`. Mark a value stale when its judgment stamp or
   rubric identifier doesn't match
   ([the rule](../../docs/playbooks/triage-scoreboard.md#when-a-judgment-goes-stale)); a judgment
   stamp of `stale` never matches. Keep its value. After that first run, a value with no setter
   is an error: surface it.
4. **Compute the composite** = weighted sum of dimensions (weights from config; tune to match "what
   I'd pick up next"). Read the bypass marker (`bypass`) as the plain in-scope level of the rubric
   your project uses ([the default](../../docs/playbooks/triage-scoreboard.md#the-default-rubric),
   or its replacement). Rank PRs and issues separately; sort issues on the judgment dimensions'
   weighted sum first, and on the mechanical dimensions only between equal sums. An item with no
   judgment at all leaves the
   ranking for the [not yet judged](../../docs/playbooks/triage-scoreboard.md#not-yet-judged)
   section; an item with some judgment ranks, and an empty dimension counts as unjudged for that
   dimension. Promote items carrying the
   severity flag to a spotlight at the top; the flag counts as judgment, and a flagged item is
   listed nowhere else. A stale value counts like a fresh one, and a stale flag still promotes.
5. **Tag evidence-readiness** per item: which review streams have landed (automated review present?
   visual preview? deep-review dossier?). Compact ✓/· marker. Presence ≠ clean.
6. **Render** the living board: the spotlight, then per kind the not yet judged section (its count
   and first five in mechanical order) and the ranking by composite; name inert dimensions in the
   header; mark each stale value and give the stale count per kind in the header; add a curated "review these first" short-list drawn from both.
   Persist the computed data as a machine-readable artifact for other jobs.
7. **Commit** following [scheduled-job](../../docs/playbooks/scheduled-jobs.md) rules
   (idempotent, silent-on-no-op).

## Pitfalls
- **Keep mechanical and judgment dims in separate storage** — mechanical is re-derived and
  disposable; judgment is precious and persisted. Don't let a refresh wipe a human's assessment.
- **Mark, never re-judge** — the refresh's one judgment write is the judgment stamp on a value
  that has none. It never changes a value or a setter, never drops a stale value, and never shows
  one as fresh. Re-judging is triage's.
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
- A changed title, body or PR diff marks every value on that item stale on the next run, and a
  rubric change marks every value stale; no value or setter changed.
