---
name: pr-triage
description: Screen and route an open pull request — fit/scope screen, marginal-benefit screen, and lane routing. Use at the front of the PR pipeline before any deep review. Stages 0-2 of the PR lifecycle.
---

# pr-triage

**When to load:** a PR needs an initial decision — does it belong, is it worth it, where does it go?
Runs [PR lifecycle](../../docs/lifecycle/pr-lifecycle.md) stages [0]–[2]. Band B.

## Steps

1. **Read `config.yaml`** — the `scope.anchors`, `scope.philosophy_veto`, and `scope.bypass_scope_gate`
   drive this skill; `security.*` drives the vuln pre-check below.
2. **Vulnerability pre-check (unconditional first pass, before any public action).** Run the
   [vulnerability divert](../../docs/reference/security-spine.md#6-the-vulnerability-divert) on the
   PR's title, description, diff, and linked issues — a "fix" can itself disclose a live exploit,
   PoC, or unfixed sibling. On a hit: take **no** public action (no comment, no public review, no
   fix-spec bounce that reproduces the exploit, no routing record on a public surface), route the PR
   to the private path (`security_contact` → `alarms_to` → private index; never public, never a silent
   no-op), and let a human coordinate the fix (private patch, advisory, then merge). Then stop public
   triage of that PR.
3. **Fit / scope screen [0].** Does the PR serve a scope anchor?
   - Health fix (bug/security/reliability on a shipped feature)? → bypass the scope gate, proceed.
     Note the bypass marker for step 6.
   - Hits an anchor? → in-scope, proceed.
   - Hits no anchor / trips the philosophy veto? → out of scope. Close politely (Band C — draft the
     kind explanation, human sends) or escalate if uncertain. **Never auto-close on scope at <90%
     confidence.** Write no judgment for an out-of-scope or escalated PR.
4. **Marginal-benefit screen [1].** "What would real users concretely lose if we never merged this?"
   If "nothing concrete" → maintainer-review or close, regardless of code quality.
5. **Route [2].** Sort the survivors:
   - small + clean + narrow + no design Q → **fast lane**
   - medium/large / sensitive subsystem / design judgment → **deep lane** (→ `pr-deep-review`)
   - visible surface → **screenshot/UX gate** (request before/after at config'd viewports)
   - `hold` / draft → **skip entirely** (hard block)
6. **Record the routing and the judgment** on the
   [scoreboard](../../docs/playbooks/triage-scoreboard.md): the lane, plus `scope_fit` (or the
   bypass marker), `criticality` and `risk`, scored on
   [the rubric](../../docs/playbooks/triage-scoreboard.md#the-default-rubric) your project uses.
   Set the severity flag only under
   [its rule](../../docs/playbooks/triage-scoreboard.md#severity-is-a-flag). Write no judgment for a
   `hold` or draft PR.
7. **Resume after a ruling.** When a human rules an escalated PR in scope, run step 2 again (the
   PR may have changed while it waited), then continue from step 4.

## Pitfalls
- **Don't code-review before scope-screening** — the cheapest review is the one you skip.
- **Hold/draft is a hard block** — no comment, no action, even if it looks ready.
- **Uncertain scope → escalate with a recommendation**, don't guess and don't silently sit on it.

## Verification
- Every PR routed to a review lane has that lane and an in-range judgment on the scoreboard. This
  skill writes no judgment for a PR that is waiting on a human, on hold or in draft. *A step-2
  diverted PR has only its private-path record and no public scoreboard entry.*
- A diverted PR left no public trace (no comment, review, or routing record) and reached a private
  destination.
- Out-of-scope closes were either human-sent or ≥90%-confidence; uncertain ones escalated.
