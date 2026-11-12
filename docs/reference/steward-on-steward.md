---
title: Steward on Steward
layout: default
parent: Reference
nav_order: 10
---

# Steward on Steward
{: .no_toc }

Steward runs on Steward. A small team of AI agents builds, reviews and merges this repo, working under the model it
describes, and a human maintainer makes the calls that matter. This page shows how that works today, and what isn't
running yet.

## The team

- **The steward** builds changes, reviews them and opens the pull requests. It checks in twice a day for new pull
  requests, issues and CI results, and posts a daily digest to the team's chat.
- **The gate** is a separate agent, on a different stack. It reviews every pull request with its own tools (`codex`
  and `fable`) and merges it once it's clean.
- **Local helpers** run on the maintainer's own computer, for anything a cloud session can't reach.
- **An oversight agent** keeps an eye on all of them and brings hard questions to the maintainer.
- **Stewards of other projects** run the same playbooks and send back what they learn.
- **The maintainer** sets the direction and approves what gets proposed.

The agents talk through [agent-mailbox](https://github.com/nesquena/agent-mailbox), a small signed mailbox kept in
git. Every steward runs the same packaged version of these playbooks. One agent maintains the package, and it improves
with what every project learns. [Working with other agents](../playbooks/working-with-other-agents.md) describes the
patterns behind all of this.

## How a change lands

1. The steward reproduces the problem and makes the change. A second agent, which saw none of its reasoning, attacks
   the result.
2. The steward opens a pull request, and the gate reviews it round by round until it's clean.
3. The steward releases the exact version that was reviewed, and the gate merges it.
4. The steward checks that CI is green and the change is live.

The gate merges because it wrote none of the commits. A PR the merging account finished waits for the maintainer's
explicit OK naming the gated head ([independent readers](../lifecycle/quality-gates.md#independent-readers)).

The refresh of this site, [#98](https://github.com/nesquena/steward-os/pull/98), is a good example. Each review round
caught something real, and nothing merged until a round came back clean.

## Where it is on the ladder

On the [adoption ladder](adoption-levels.md), the review-and-merge pipeline already works the way Level 4 describes,
and the twice-daily check-ins and digests are Level 2. Level 3 isn't running yet: unattended mechanical jobs such as
label sync and auto-close, each with a watchdog.

## The config

This repo's [`setup/config.yaml`](https://github.com/nesquena/steward-os/blob/main/setup/config.yaml) is a filled-in
copy of the [template](https://github.com/nesquena/steward-os/blob/main/setup/config.template.yaml): one public repo,
continuous deploy to GitHub Pages, `bin/ci` as the gate, `codex` and `fable` as the reviewers, and conservative
autonomy bands. Its scheduled jobs are all off, since the check-ins are agent sessions rather than jobs.

## Not running yet

- Unattended mechanical jobs (Level 3).
- Community chat monitoring.
- A contributor trust ledger.

Steward is meant to be adopted one rung at a time, and this repo is climbing the same
[ladder](../playbooks/autonomy-ladder.md) it describes.
