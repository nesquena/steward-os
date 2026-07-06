---
title: Steward on Steward
layout: default
parent: Reference
nav_order: 8
---

# Steward on Steward
{: .no_toc }

Steward runs on Steward. This page is the honest reference instance: the real config, the real
artifacts, and a plain split of what's actually live versus what's still aspirational. No demo
fiction - the credibility is in the honesty, which is the whole [output-loop](../playbooks/output-loop.md) value.

## The real config

This repo's own [`setup/config.yaml`](https://github.com/nesquena/steward-os/blob/main/setup/config.yaml)
is a filled instance of the [template](https://github.com/nesquena/steward-os/blob/main/setup/config.template.yaml):
one public repo, trunk `main`, continuous deploy (merge to main → GitHub Pages), the Jekyll build as
the gate, no chat community, conservative autonomy bands, and **no scheduled jobs enabled** - because
nothing runs unattended here yet.

## What's live today

- **Supervised sessions.** Contributions and edits go through an agent working *with* a human, who
  approves every public write. This is Level 1, and it's how the docs you're reading were built.
- **Human-gated PR review.** Every change lands via pull request with a human in the loop. See
  [#1](https://github.com/nesquena/steward-os/pull/1) (the output-loop playbook) and
  [#3](https://github.com/nesquena/steward-os/pull/3) (the minimalism ladder) - real PRs that went
  through human-gated [PR lifecycle](../lifecycle/pr-lifecycle.md) review before merge.
- **The editorial loop.** Discovery over delivery: work is proposed, reviewed, and trimmed in the
  open, exactly as the [output-loop playbook](../playbooks/output-loop.md) prescribes.

## What's aspirational (not yet running)

- **Scheduled autonomy.** No cron jobs, no unattended runs. Every `scheduled_jobs` entry is
  `enabled: false`.
- **Chat monitoring / mentions sweep.** No community platform is wired; `community.chat.platform` is
  empty.
- **Autonomous public writes.** No credentials file is configured; the agent never posts as the
  project unsupervised.

That gap is deliberate. Steward is designed to be adopted one rung at a time, and this instance is
honestly near the bottom of its own [adoption ladder](adoption-levels.md) - which is exactly where a
careful project should start.
