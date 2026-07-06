---
title: Home
layout: default
nav_order: 1
---

# Steward
{: .fs-9 }

An operating model for running a software project with an AI agent as a genuine co-maintainer —
issue triage, PR review, quality gates, community, and the safety model that makes autonomous
action trustworthy.
{: .fs-6 .fw-300 }

[Get started](docs/architecture/index.md){: .btn .btn-primary .fs-5 .mb-4 .mb-md-0 .mr-2 }
[View on GitHub](https://github.com/nesquena/steward-os){: .btn .fs-5 .mb-4 .mb-md-0 }

---

This is not an application. It's a *system* — playbooks, skills, and processes that let you drop an
agent (or a team of agents) into any software project and have it help triage issues, review and
merge pull requests, run quality gates, talk to your community, and keep the whole machine healthy,
at a level of rigor that holds up in a real open-source project.

It is **project-agnostic by design.** You bring the project; the system brings the operating model,
the recipes, and the questions it needs to ask you to wire itself up.

> **Why "Steward"?** A steward doesn't own what they tend — they care for it on the owner's behalf,
> with judgment and restraint, and they know which decisions aren't theirs to make. That's the
> posture this system encodes: an agent that does the tireless work of maintenance but keeps a human
> at every irreversible edge. (It's also one of the system's four roles — the one that keeps the
> project healthy and watches the others.)

## The core idea

> Reading is cheap and safe; **writing to a public surface in the project's voice is the
> irreversible act that needs a human decision.** Everything upstream of that line — discover,
> classify, dedupe, review, draft, rank, gate — an agent can do autonomously with the right
> guardrails. The irreversible, reputational acts stay human-gated, or autonomous-with-a-watchdog.
> That membrane isn't a limitation; it's what makes running the whole thing unattended *safe*.

## Find your way

- **[Quickstart](quickstart.md)** — adopt Steward on your repo in ~15 minutes (Claude Code). Start
  here to *run* it; read the sections below to understand it.
- **[Architecture](docs/architecture/)** — the four roles, the autonomy bands, the security spine.
  Start here; everything builds on it.
- **[Lifecycle](docs/lifecycle/)** — end-to-end playbooks: issues, pull requests, quality gates,
  community, contributor recognition.
- **[Playbooks](docs/playbooks/)** — cross-cutting recipes: the autonomy ladder, the watchdog
  pattern, scheduled jobs, the triage scoreboard.
- **[Reference](docs/reference/)** — glossary, adoption levels, anti-patterns, coding principles,
  the bug-shape catalog, the security spine, and an FAQ.
- **[Setup](setup/setup-interview)** — the interview that wires the system to your project.

## Adopt it gradually

You don't install this all at once. Read the model (Level 0), use the playbooks in supervised
sessions (Level 1), add the read-only scoreboard and digests (Level 2), promote mechanical actions
to watchdogged autonomy (Level 3), then run the full pipeline (Level 4). See
[adoption levels](docs/reference/adoption-levels).
