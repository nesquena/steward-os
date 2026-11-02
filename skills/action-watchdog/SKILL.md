---
name: action-watchdog
description: Independently fact-check the autonomous actions the system took (issue closes, labels, capture marks, etc.) against live ground truth, and alarm on any mismatch. Run on a schedule. This is what makes Band-A public actions safe.
---

# action-watchdog

**When to load:** auditing autonomous actions for correctness. Runs the
[watchdog pattern](../../docs/playbooks/watchdog-pattern.md). Band A, deterministic, read-only.
**Build and enable this before promoting any public-write action to Band A.**

## Steps

1. **Read the action ledgers** — the append-only records each action the system executes writes:
   what it closed, labeled or marked on its own, and the announcement posts a human keyed. The ledger
   is the list of *what to check*, never the evidence of correctness.
2. **Re-verify each action against LIVE ground truth, independently:**
   - **Autonomous closes** ([`issue-autoclose`](../issue-autoclose/SKILL.md)): is the issue still
     closed? Is the cited PR actually merged and does it still link the issue? Does the cited release
     tag actually contain the merge commit? Was it reopened with a complaint? → any mismatch = 🔴.
   - **Autonomous labels** ([`label-sync`](../label-sync/SKILL.md)): for each ledger'd label, does it
     still match its source signal, is it within the declared `labels:` allowlist, and was it
     *add-only* — i.e. did the job avoid removing, reassigning, or overriding a human-applied label?
     → a mislabel, an out-of-allowlist label, or an overridden human label = 🟡 (a human's label
     always wins).
   - **Announcements** ([`release-announce`](../release-announce/SKILL.md)): does each
     ledger'd announcement correspond to a real release tag with merged content? Was each release
     posted to the fixed channel **exactly once**, counting `bot` and `hand` entries? Does each `bot`
     post match the changelog entry it claims to render? A `hand` entry is a post a human wrote and
     recorded: check its release and its once-only, not its text. → a duplicate, or an announcement of
     an absent/unshipped release, or bot text that adds claims beyond the changelog = 🔴; a drifted
     last-announced marker = 🟡.
   - **Autonomous capture marks** ([`issue-capture`](../issue-capture/SKILL.md)): for each ledger'd
     mark, does exactly one durable staged record and terminal `captured` event exist for the same
     adapter + source item + target-repository key, and does the source carry exactly the configured
     marker? Did every vulnerability-diverted item receive **no** public mark? → a mark without a
     staged record, a missing/duplicate mark, or any public mark on a diverted item = 🔴; a stale
     nonterminal capture intent with no public action yet = 🟡.
   - **Host closes** (no ledger: the host acts on its own, and nothing in the system records it):
     for each repository whose `host_closes_on_merge` is `false`, read what closed each issue closed
     since that repository's window opened. Keep each repository's window start in the watchdog's
     own private state. A repository with no recorded start (the first run, a repository added or
     switched from `true`, or a lost record) opens its window now and reports that once as 🟡, since
     closes before then went unchecked: a no-model script can't tell those cases apart, so it treats
     them alike. On GitHub, read the `ClosedEvent`'s `closer`. On GitLab, read the issue's resource
     state events (a `closed` event with a `source_merge_request_id` or a `source_commit`), and the
     project's `autoclose_referenced_issues` setting, which its API reports. On any other host
     (Gitea, Forgejo, or a self-managed instance), there's nothing to read: report once per window,
     as 🟡, that host closes can't be observed there. → an issue the host closed from a merge or a
     commit, or a GitLab setting that's on = 🟡: a human checks the repository's setting and decides
     about the issue.
   - **(Add a check here for every new autonomous action — same change that adds the action.)**
3. **Classify severities.** 🔴 = correctness failure (an action was *wrong* — act now). 🟡 = drift
   (stale, reconcile soon).
4. **Report only on findings.** Silent when all-clear. Route 🔴 to a human immediately; 🟡 to the
   reconcile queue. (Exception: a dedicated fleet-liveness heartbeat always reports, so its silence
   is the alarm.)
5. **Never fix anything.** The watchdog verifies and surfaces; a human (or a separate, itself-watched
   action) fixes. An auto-fixing watchdog is just another unverified actor.

## Pitfalls
- **Independence is the whole point** — re-derive correctness from live state, don't trust the
  action's own success report.
- **Deterministic, no LLM** where possible — it's comparing recorded actions to live data; no model
  means no injection surface and no nondeterminism.
- **Don't let it page on every run** — alarm fatigue defeats it. Silent-on-all-clear.

## Verification
- Deliberately record a *wrong* action (in a test ledger) and confirm the watchdog flags it 🔴.
- On a repository declared `host_closes_on_merge: false`, merge a PR that closes a test issue with
  the host's closing on, and confirm the watchdog flags it 🟡.
- On a clean state, the watchdog is silent.
- Every autonomous public action in the system has a corresponding check here.
