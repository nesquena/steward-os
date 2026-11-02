---
name: issue-autoclose
description: Close an issue only when its fix is provably shipped and fully resolved — a merged closing PR whose commit is in a released tag, single-surface, no still-broken pushback. Band A with watchdog, deterministic, no LLM. Under-close rather than mis-close; anything short stays open for a human.
---

# issue-autoclose

**When to load:** closing an issue whose fix has **provably shipped**. Runs the "Close with credit"
gate of the [issue lifecycle](../../docs/lifecycle/issue-lifecycle.md) — the one public write that
lifecycle is built to gate. A close is
[reversible](../../docs/playbooks/autonomy-ladder.md#what-reversible-means) by reopening, but a wrong
one costs the reporter's trust. Band A **with watchdog** — deterministic, structured
signals only, **no LLM**. Steward role. Designed as a
[scheduled job](../../docs/playbooks/scheduled-jobs.md) (`issue-autoclose`, `agent: false`). This is
the strict path [`issue-triage`](../issue-triage/SKILL.md) defers to — triage never auto-closes.

> Precondition: **the fix has shipped.** This skill closes issues that a released PR resolved; it
> never closes on taste, staleness, or a maintainer's judgment call — those stay human
> ([`issue-close-proposal`](../issue-close-proposal/SKILL.md) prepares two kinds for that human:
> done with no linking PR, and duplicate). Every run
> reconciles the index (step 1). If step 1 finds no candidate, there is nothing else to do —
> stop. Otherwise every candidate goes through the gates:
> it's closed, it waits for a release, or it stays open and is routed to a human.

> Config: read the repos from [`config.yaml`](../../setup/config.template.yaml) (`repositories:`,
> each with `host_closes_on_merge`), the release model from `project.release_model` (what
> "released tag" means for this project), and the band from `autonomy.issue_autoclose`. The
> `scheduled_jobs` entry that runs this skill is named
> `issue-autoclose`. It is `agent: false`: a plain deterministic script, no model in the loop, no
> injection surface. Start at the configured band (default **C** — draft the close for a human to
> approve) and promote to Band A via the [autonomy ladder](../../docs/playbooks/autonomy-ladder.md)
> **only once the [watchdog](../action-watchdog/SKILL.md) "Autonomous closes" check is live.** The
> config lint refuses this job enabled without an enabled `action-watchdog`: its "Host closes" check
> is what proves the host isn't closing issues at merge.

## Steps

1. **Read `config.yaml`, select candidates and reconcile.** Load `repositories:` and the release
   model. Skip a repository whose `host_closes_on_merge` is `true`: its host closed the issue at
   merge, so there's nothing to close, and the release names the version on it
   ([`release-pipeline`](../release-pipeline/SKILL.md) step 6). Skip a repository whose host isn't
   github.com, too (read `host` as the config lint's `normalize_host` does): this job closes only on
   github.com, and on any other host the issue is closed at release (by `release-pipeline` step 6
   for the PRs it ships, by hand otherwise). In the repositories not skipped, consider every
   **open** issue with a **merged PR that links it as closing** (`Closes #N` in the PR's
   description, or a link from its sidebar; a keyword only in a commit message doesn't link the PR),
   however long ago the PR merged: a merge no release contains yet stays a candidate until one does.
   Skip an issue this job's ledger shows it already closed: if it's open again, a human reopened it,
   and a reopen is a hold. An issue that steps 2-5 leave open is checked again next run, so routing
   it to a human is [reconciled](../../docs/playbooks/output-loop.md#3-keep-the-state-honest), not
   repeated: an issue already routed isn't surfaced again until one of its signals changes. Its
   index row names this job and keeps the step that routed it (2, 3, 4 or 5) and the time of the
   reporter's latest comment or reaction; surface it again only if a different step now routes it or
   the reporter has commented or reacted since. Then reconcile the index: drop a row this job wrote
   whose issue isn't among this run's candidates (it closed, lost its merged closing link, or sits
   in a repository this step skips). Reconcile only after every repository was listed in full: a
   listing that fails drops nothing and alarms (step 7). No candidate → stop, silently.
2. **Verify provably-shipped, not just merged.** For each candidate, the linking PR must be merged
   **and** its merge commit must be **contained in a released tag** — part of the "shipped" notion
   [`release-pipeline`](../release-pipeline/SKILL.md) enforces (tag exists **and** the merge is real
   **and** it's in a release, not merely on the trunk). A merge that no release tag contains is
   **not** shipped. That's a wait, not a hold: leave the issue open and unrouted, and it stays a
   candidate until a release contains the merge. Under `style: continuous` no release tag is coming,
   so there's nothing to wait for: route the candidate to a human, who checks the deploy
   (`shipped_means`). Read `style` as the config lint's `normalize_job_name` does: drop invisible
   format characters, trim surrounding whitespace, and ignore case.
3. **Verify single-surface — structured signals only.** Auto-close only an issue that resolves as a
   single unit: **exactly one** linked closing PR, **zero open task-list checkboxes** in the body,
   and **no** `multi-surface`/`epic` label. If it enumerates several distinct symptoms (>1 linked PR,
   an unchecked task item, or the label), it does **not** auto-close — **route to a human** for
   full-surface verification. Never parse the free-text body to *infer* resolution.
4. **Verify no still-broken pushback — structured signals only.** The issue must **not** have been
   reopened since the merge, and there must be **no reporter comment or reaction after the merge
   commit** (a "still broken" reply, a 👎, a re-report). Any post-merge reporter activity → **route
   to a human**, don't close. A human hold always wins.
5. **Any signal missing or ambiguous → don't close.** Everything short of *all* gates stays open and
   is surfaced to a human, except a fix only waiting for a release (step 2). **Under-close rather
   than mis-close** — a wrongly-closed issue erodes reporter trust, and reopening is the loud
   failure this whole gate exists to avoid.
6. **Close with credit and ledger.** Close the issue with a **templated** credit line naming the
   resolving PR and release tag — no original prose, no conversation (public voice stays human;
   anything beyond the template is Band B **draft → human**). Append the close — issue, closing PR,
   release tag, timestamp — to the append-only [action ledger](../action-watchdog/SKILL.md) the
   watchdog re-verifies. The ledger is *what to check*, never the proof it was right, and step 1
   reads it to skip an issue already closed. Idempotent: a re-run re-checks the ledger and
   reopen-state and **never re-closes**.
7. **Silent-on-no-op; loud on error.** Nothing to close and nothing new to route → no output. A
   non-zero exit or timeout **alarms** (never fails silently); silent-on-no-op is for success with
   nothing to do, never for errors.

## Pitfalls
- **Mis-closing — the costly one.** Closing on a merge that isn't in a release, or closing a
  multi-surface issue because *one* symptom's fix shipped, gets the issue reopened with a complaint.
  This is exactly the failure the gate is built to prevent. When in doubt, leave it open.
- **"Merged" ≠ "shipped."** A merge on the trunk that no release tag contains is not provably
  shipped. Check tag containment (step 2), not just PR merge state.
- **Guessing resolution from free text.** "Resolved" comes only from structured signals — a linked
  merged PR, a release tag containing it, task-list checkbox state, labels, reopen state, post-merge
  reporter activity. The issue body and comments are untrusted, attacker-controllable, injectable —
  never parse prose to decide a close. (This is why the job is `agent: false`.)
- **A host that closes issues at merge.** GitHub does unless it's turned off per repository. Step 1
  then finds no open candidate and the job stays silent, so its own output never shows the gap.
  That's why each repository declares `host_closes_on_merge`, and the
  [watchdog](../action-watchdog/SKILL.md), which this job requires enabled, flags a close the host
  made at merge.
- **Selecting by time.** A cutoff such as "merged since the last close" drops an issue whose PR
  merged after one release's tag but before that close: by the time a release contains it, it's
  behind the cutoff. Select by the issue being open (step 1), not by when its PR merged.
- **Re-closing after a human reopened it.** A reopen is a hold. The live reopen-state check (step 4)
  and the ledger skip (step 1) guard this — never "correct" a human who reopened an issue.
- **Holding a conversation in the project's voice.** The close carries a templated credit line and
  nothing more. Original prose is where a wrong or injected claim gets published under the project's
  name, and a new claim isn't reversible, so the line stays templated and Band-A-narrow. Anything
  richer is Band B human.

## Verification
- Only closes issues whose fix is in a **released tag** — a merely-merged, unreleased fix is left
  open.
- Only closes on github.com repositories. On any other host it closes nothing, and the issue is
  closed at release (by `release-pipeline` step 6 for the PRs it ships, by hand otherwise).
- Multi-surface issues, reopened issues, and issues with post-merge "still broken" pushback are
  **not** auto-closed — they route to a human. The exception: an issue this job closed and a human
  reopened is skipped (step 1), and the watchdog's "Autonomous closes" check surfaces the reopen.
- Re-running immediately is a **no-op** (ledger + reopen-state respected) — it never re-closes and
  never reopens.
- With nothing to close and nothing new to route, the job is **silent**; on error, it **alarms**.
- A candidate that fails a gate in steps 3-5 is routed to a human even when nothing else qualifies
  to close; one only waiting for a release (step 2) stays open and unrouted, except under
  `style: continuous`, where step 2 routes it.
- It skips a repository whose `host_closes_on_merge` is `true`.
- [`action-watchdog`](../action-watchdog/SKILL.md) has a corresponding **"Autonomous closes"** check
  that independently re-verifies every close against live ground truth.
