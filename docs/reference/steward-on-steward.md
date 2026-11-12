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
- **Level 2:** scheduled check-ins surface what's waiting and send a digest.
- **Level 4:** deep review and fixes run as [Band B](../architecture/index.md#band-b--session-autonomous)
  agent sessions, several independent readers check every change, and merges stay gated.
- **Not yet running:** Level 3, unattended mechanical jobs with a watchdog.

No step on the ladder was skipped. The review side was run by hand in supervised sessions first, and it climbed as
the evidence built up.

## Who does what

Several agents share the work. Each has one job, and no change ships on a single agent's say-so (the
[four roles](../architecture/index.md#the-four-roles), worn by different agents).

| Role | What it does here |
|---|---|
| **This repo's steward** | Builds and reviews changes, runs its own review gate, and opens the pull request. It runs scheduled check-ins twice a day: new PRs and issues, CI on `main`, its own follow-up queue. It posts a merge digest and release announcements to a private team chat. |
| **The gate** | A separate maintainer agent, on a different stack, reviews every pull request with two review tools (`codex` for code review, `fable` for the adversarial pass) plus its own build and checks. It merges only when the steward sends a release naming the exact head it reviewed. |
| **Local helpers** | Agents on the maintainer's own computer handle what a cloud session can't reach. They're read-only unless the maintainer approves an action in their own session ([a local helper](../playbooks/working-with-other-agents.md#a-local-helper)). |
| **An oversight agent** | Watches the other agents, nudges stalled work, and relays hard calls to the maintainer. It brings back the maintainer's answers quoted, with no authority of its own ([the orchestrator](../playbooks/working-with-other-agents.md#the-orchestrator)). |
| **Stewards of other projects** | Run the same playbooks on other open-source projects. They send back lessons from their own runs, and they review shared changes when asked. |
| **The maintainer** | Owns scope, taste and release calls. They approve every change to this repo's public model before it's proposed. |

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
- Several rounds of review each caught one gap: a contrast failure, a clipped focus ring, and a click that stopped
  working.
- Each gap was fixed and re-checked before the merge.
- The last gap became its own follow-up, [#99](https://github.com/nesquena/steward-os/pull/99).

## The config

This repo's own [`setup/config.yaml`](https://github.com/nesquena/steward-os/blob/main/setup/config.yaml) is a filled
instance of the [template](https://github.com/nesquena/steward-os/blob/main/setup/config.template.yaml):
- one public repo, trunk `main`;
- continuous deploy (merge to `main`, then GitHub Pages);
- `bin/ci` as the gate, with `codex` and `fable` as the two review tools;
- no chat community;
- conservative autonomy bands.

Its `scheduled_jobs` are all off. Those are the deterministic, no-model jobs of Level 3. The scheduled check-ins
above are agent sessions instead, run the way the [proactive sweep](../playbooks/proactive-sweep.md) describes.

## What's aspirational (not yet running)

- **Unattended mechanical jobs.** No label sync, no strict shipped-issue auto-close, no scoreboard refresh and no
  watchdog run on their own. Every `scheduled_jobs` entry is `enabled: false`. This is the Level 3 rung.
- **Chat monitoring.** No community platform is wired: `community.chat.platform` is empty. The team chat only
  receives announcements.
- **A trust ledger.** The `trust` block is off, so contributor history doesn't weight review yet.
- **Public writes without a human decision behind them.** Public writes happen in agent sessions under the
  maintainer's approval (Band B). None runs as an unattended job.

That gap is deliberate. Steward is meant to be adopted one rung at a time, and each rung is climbed only when the one
below it has the evidence and the watchdog to make it safe ([the autonomy ladder](../playbooks/autonomy-ladder.md)).
