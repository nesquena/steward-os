---
name: pr-deep-review
description: Deep-review a routed PR and run the authoritative quality gate before merge. Reads the whole diff, reproduces, runs the layered gates fresh, bounces with a fix-spec or fixes mechanical blockers. Stages 3-4 of the PR lifecycle.
---

# pr-deep-review

**When to load:** a PR has cleared triage and needs full review + the pre-merge gate. Runs
[PR lifecycle](../../docs/lifecycle/pr-lifecycle.md) stages [3]–[4] and the
[quality gates](../../docs/lifecycle/quality-gates.md). Band B.

## Steps

1. **Read the whole diff**, not just the hunks. Read changed files at the PR head *and* on the trunk
   to see what changed and why. Reproduce the bug / exercise the change.
2. **For each flaw, decide bounce vs. fix:**
   - **Bounce** with an *exact, reproducible* fix-spec. Reconcile against the live thread first so
     you don't duplicate feedback.
   - **Fix it yourself** (Builder) for mechanical blockers (rebase, a few failing tests, a small
     nit) — on the author's branch, preserving authorship.
3. **Run the authoritative gate [4] — fresh, independent of any prior verdict:**
   - full **test suite** to completion (command + runtime from `config.yaml`) — never sample
   - **automated code review** pass
   - **adversarial review** pass (a second, differently-tuned reviewer; stricter wins on a
     reproduced finding)
   - **visual verification** for any visible surface (screenshots at config'd viewports; *drive*
     interactions, don't just screenshot them)
4. **If the gate finds something:** Builder fixes it, gate **re-runs**. Loop until all-clear.
5. **Add the regression test** for any fix so the [living suite](../../docs/lifecycle/quality-gates.md)
   grows. If you rebuilt the worktree, re-apply your hand-fix to the fresh tree (a 3-dot diff
   captures only the PR's commits, not your post-merge fix).
6. **Hand off to `release-pipeline`** (merge + credit) only on an all-clear gate.

## Pitfalls
- **Green CI ≠ ready.** The fresh authoritative gate routinely catches what CI + prior review missed.
- **A prior "looks clean" (human, agent, or cached dossier) is context, not the gate.** It may have
  checked only one code path or a stale base. Re-run fresh.
- **Untrusted code → sandbox.** If a gate must *run* the PR's code, use the
  [sandbox](../../docs/reference/security-spine.md#4-the-sandbox-untrusted-code-execution); never
  bare-run contributor code. Reading the diff is always safe.
- **A vuln can surface mid-review.** The high-recall intake check can miss what only reproduction
  reveals. If deep review shows the PR discloses a live vulnerability, the
  [divert](../../docs/reference/security-spine.md#6-the-vulnerability-divert) applies now — a public
  bounce or fix-spec that reproduces the exploit is itself a disclosure; route it private instead.
- **Never tolerate a flake** surfaced by the suite — root-cause it.

## Verification
- The full suite passed to completion on the *current* code.
- Both review passes ran; findings reconciled.
- Visible surfaces inspected. Regression test present. Authorship preserved.
