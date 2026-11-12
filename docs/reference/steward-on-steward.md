---
title: Steward on Steward
layout: default
parent: Reference
nav_order: 10
---

# Steward on Steward
{: .no_toc }

Steward runs on Steward. This page shows how: who does what, how a change gets from an idea to `main`, the config
it uses, and a plain split of what's live today versus what's still aspirational. Nothing here is a demo. If a
capability isn't running yet, this page says so, which is the same discipline the
[output loop](../playbooks/output-loop.md) asks for everywhere else.

## Where it sits on the ladder

On the [adoption ladder](adoption-levels.md), this repo runs **Level 2, plus Level 4's review pipeline**:
- **Level 2, in part:** scheduled check-ins surface what's waiting and send a digest of what merged and what's open.
  The scoreboard job is still off.
- **Level 4's review pipeline:** deep review and fixes run as
  [Band B](../architecture/index.md#band-b--session-autonomous) agent sessions, several independent readers check
  every change, and merges stay gated.
- **Not yet running:** Level 3, unattended mechanical jobs with a watchdog.

The review side climbed on its own evidence: it ran by hand in supervised sessions first.

## Who does what

Several agents share the work, and no change ships on a single agent's say-so: the reviews that clear a change come
from agents that didn't write it ([the four roles](../architecture/index.md#the-four-roles)).

| Role | What it does here |
|---|---|
| **This repo's steward** | Builds and reviews changes, runs its own review gate, and opens the pull request. It runs scheduled check-ins twice a day: new PRs and issues, CI on `main`, its own follow-up queue. It posts a digest of what merged and what's open to a private team chat, at most once a day. |
| **The gate** | A separate maintainer agent, on a different stack, reviews every pull request with two review tools (`codex` for code review, `fable` for the adversarial pass) plus its own build and checks. It merges only when the steward sends a release naming the exact head it reviewed and the trunk it was checked against. |
| **Local helpers** | Agents on the maintainer's own computer handle what a cloud session can't reach. They're read-only by their tools; a write runs only after the maintainer approves it in their own session ([a local helper](../playbooks/working-with-other-agents.md#a-local-helper)). |
| **An oversight agent** | Watches the other agents, nudges stalled work, and relays hard calls to the maintainer. It brings back the maintainer's answers quoted, with no authority of its own ([the orchestrator](../playbooks/working-with-other-agents.md#the-orchestrator)). |
| **Stewards of other projects** | Run the same playbooks on other open-source projects. They send back lessons from their own runs, and they review shared changes when asked. |
| **The maintainer** | Owns scope, taste and the merge rules. They approve each change the steward proposes to this repo before its pull request opens. |

### The shared playbook package

Every steward runs one packaged version of these playbooks. The package is versioned, with a changelog, and has a
single writer: one maintainer agent ([owning a shared asset](../playbooks/working-with-other-agents.md#owning-a-shared-asset)).
- A lesson from any project goes in only after its own review.
- Changes to this repo are folded back into the package.

### The mailbox

The agents talk through [agent-mailbox](https://github.com/nesquena/agent-mailbox), a small, file-based mailbox kept in
a git repository, with signed messages. Each message has one topic and says what it needs from the reader. Holds and
releases name an exact version or commit, so "go" always means a specific head
([working with other agents](../playbooks/working-with-other-agents.md)).

## How a change lands

1. **The steward builds it** on a branch. It reproduces the problem first, then makes the change.
2. **The steward's own gate:**
   - its own full review;
   - an independent adversarial pass on the final head, by an agent that saw none of the writer's reasoning;
   - after any later push, a fresh pass on the new head;
   - CI green on that exact head.

   Visible changes get screenshots in the PR description.
3. **The gate reviews it**, round by round, until it's clean. Every fix is a new head, and every new head is
   reviewed again ([independent readers](../lifecycle/quality-gates.md#independent-readers)).
4. **The steward releases that head** by name, and the gate merges it.
5. **The steward confirms the result:** CI on `main`, and the deployed site serving the change.

**Merge authority.** The maintainer's standing instruction covers a merge by an agent that wrote no commit in the
PR's range, which is why the gate merges and the steward doesn't. A PR the merging account finished waits for the
maintainer's explicit OK naming the gated head ([independent readers](../lifecycle/quality-gates.md#independent-readers)).

For an example, see [#98](https://github.com/nesquena/steward-os/pull/98), the refresh of this site:
- The gate's first round found two regressions: list numbers below contrast in the light scheme, and a focus ring
  cut off in wide tables on phones.
- The fix for the second stopped mouse clicks on table links, and the next round caught it.
- Each was fixed and re-checked on a new head before the gate merged.
- A related gap, focused controls hidden under the floating search button on phones, is its own pull request,
  [#99](https://github.com/nesquena/steward-os/pull/99).

## The config

This repo's own [`setup/config.yaml`](https://github.com/nesquena/steward-os/blob/main/setup/config.yaml) is a filled
instance of the [template](https://github.com/nesquena/steward-os/blob/main/setup/config.template.yaml):
- one public repo, trunk `main`;
- continuous deploy (merge to `main`, then GitHub Pages);
- `bin/ci` as the gate, with `codex` and `fable` as the two review tools;
- no chat community;
- conservative autonomy bands.

Its `scheduled_jobs` are all off: `scoreboard-refresh` (Level 2's scoreboard) and `action-watchdog` (Level 3's
watchdog) are deterministic, no-model jobs. The scheduled check-ins above are agent sessions instead, run the way the
[proactive sweep](../playbooks/proactive-sweep.md) describes.

## What's aspirational (not yet running)

- **The scoreboard.** No job ranks open work on a schedule (Level 2's scoreboard).
- **Unattended mechanical jobs.** No label sync, no strict shipped-issue auto-close and no watchdog run on their own:
  the Level 3 rung. Every `scheduled_jobs` entry is `enabled: false`.
- **Chat monitoring.** No community platform is wired: `community.chat.platform` is empty. The team chat only
  receives announcements.
- **A trust ledger.** The `trust` block is off, so contributor history doesn't weight review yet.
- **Unattended public writes.** Each public write runs at the band the config sets (merges, labels and triage replies
  at B; issue auto-close and announcements at C), always in an agent session. None runs as an unattended job, and no
  credentials file is configured.

That gap is deliberate. Steward is meant to be adopted one rung at a time, and each rung is climbed only when the one
below it has the evidence and the watchdog to make it safe ([the autonomy ladder](../playbooks/autonomy-ladder.md)).
