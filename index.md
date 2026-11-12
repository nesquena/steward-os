---
title: Home
layout: default
nav_order: 1
---

<div class="hero">
  <p class="eyebrow">An operating model for co-maintained software</p>
  <h1 class="hero-title" id="steward">Steward</h1>
  <p class="standfirst">Run a software project with an AI agent as a genuine co-maintainer: triage, review, quality gates, community, and the safety model that makes autonomous action trustworthy.</p>
  <div class="actions" markdown="1">
[Get started](quickstart.md){: .btn .btn-primary }
[Read the architecture](docs/architecture/)
[View on GitHub](https://github.com/nesquena/steward-os)
  </div>
  <blockquote class="creed"><p>Reading is cheap and safe; writing to a public surface in the project’s voice <strong>needs a human decision</strong> unless it is reversible, mechanical and watched.</p></blockquote>
  <div class="ledger">
    <p class="caption">The autonomy bands</p>
    <dl class="bands">
      <div class="band-a-row"><dt><span class="mark">A</span><span>Autonomous</span></dt><dd>Reversible, low blast radius, mechanical or verified.</dd></div>
      <div class="band-b-row"><dt><span class="mark">B</span><span>Session-autonomous</span></dt><dd>Proceeds on judgment, asks at real decisions.</dd></div>
      <div class="band-c-row"><dt><span class="mark">C</span><span>Human-gated</span></dt><dd>The agent prepares; a human takes the irreversible act.</dd></div>
    </dl>
  </div>
  <ol class="roles" aria-label="The four roles">
    <li><span class="n" aria-hidden="true">i.</span><span class="r">Watcher</span><span class="q">What’s coming in?</span></li>
    <li><span class="n" aria-hidden="true">ii.</span><span class="r">Reviewer</span><span class="q">Is this correct?</span></li>
    <li><span class="n" aria-hidden="true">iii.</span><span class="r">Builder</span><span class="q">Make the change.</span></li>
    <li><span class="n" aria-hidden="true">iv.</span><span class="r">Steward</span><span class="q">Keep the whole thing healthy.</span></li>
  </ol>
</div>

## Find your way

- **[Quickstart](quickstart.md)**: adopt Steward on your repo in one sitting. Start here to *run*
  it; read the sections below to understand it.
- **[Architecture](docs/architecture/)**: the four roles, the autonomy bands, the security spine.
  Everything else builds on it.
- **[Lifecycle](docs/lifecycle/)**: end-to-end playbooks for issues, pull requests, quality gates,
  community, and contributor recognition.
- **[Playbooks](docs/playbooks/)**: cross-cutting recipes. The autonomy ladder, the watchdog
  pattern, scheduled jobs, the triage scoreboard.
- **[Reference](docs/reference/)**: glossary, adoption levels, anti-patterns, coding principles,
  authoring changes, reviewing at volume, the bug-shape catalog, the security spine, and an FAQ.
- **[Setup](setup/setup-interview.md)**: the interview that wires the system to your project.
{: .cards role="list" }

## Why "Steward"

A steward doesn't own what they tend. They care for it on the owner's behalf, with judgment and
restraint, and they know which decisions aren't theirs to make. That is the posture this system
encodes: an agent that does the tireless work of maintenance and keeps a human at every
irreversible edge. It is also the fourth role, the one that keeps the project healthy and watches
the others.

Steward is not an application. It is playbooks, skills, and processes, and it is project-agnostic
by design: you bring the project; Steward brings the operating model, the recipes, and the
questions it needs to ask you to wire itself up.

## Adopt it gradually

You don't install this all at once. Read the model (Level 0), use the playbooks in supervised
sessions (Level 1), add the read-only scoreboard and digests (Level 2), promote mechanical actions
to watchdogged autonomy (Level 3), then run the full pipeline (Level 4). See
[adoption levels](docs/reference/adoption-levels.md).

## Status

Early. The architecture and lifecycle playbooks are the stable core; the skills and the setup
interview are still evolving. Nothing runs on its own: you install the skills into your own coding
agent ([what you need](quickstart.md#before-you-start)), and
[Steward on Steward](docs/reference/steward-on-steward.md) shows what runs on this repo today.
