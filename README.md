# Steward

**An operating model for running a software project with an AI agent as a genuine co-maintainer.**

Steward is not an application. It is a *system* — a set of playbooks, skills, and processes that let
you drop an agent (or a team of agents) into any software project and have it help triage issues,
review and merge pull requests, run quality gates, talk to your community, and keep the whole
machine healthy — at a level of rigor that holds up in a real open-source project.

It is **project-agnostic by design.** Nothing here is specific to any one codebase. You bring the
project; Steward brings the operating model, the recipes, and the questions it needs to ask you to
wire itself up.

> If you run an open-source project and you've ever wished you had a tireless, careful co-maintainer
> who reads every diff, never drops a contributor's question, and gets *more* trustworthy over time
> instead of less — that's what Steward is for.

**Why "Steward"?** A steward doesn't own the thing they tend — they care for it on the owner's
behalf, with judgment and restraint, and they know which decisions aren't theirs to make. That's
exactly the posture this system encodes: an agent that does the tireless work of maintenance but
keeps a human at every irreversible edge. ("Steward" is also one of the system's
[four roles](docs/architecture/index.md#the-four-roles) — the one that keeps the whole project
healthy and watches the others. The system is named for it.)

---

## What you get

- **An operating model** — the four-role architecture (Watcher · Reviewer · Builder · Steward),
  a human-in-the-loop spectrum (Bands A/B/C), and a security spine that makes autonomous action
  safe instead of reckless.
- **End-to-end lifecycle playbooks** — how work travels from "someone mentioned a bug on chat"
  all the way to "shipped in a release, issue closed with credit," with the exact decision states
  at every step.
- **A quality-gate pipeline** — layered, independent checks (automated review, adversarial review,
  the test suite as a growing body of regressions, visual verification) so that "the suite is the
  primary line of defense and the other gates are the secondary line."
- **Skills** — focused, loadable procedures an agent runs (set up the system, triage a PR, triage
  an issue, run the release pipeline).
- **A setup interview** — a documented question list the agent works through with you to learn your
  repos, your chat platform, your CI, your review tools — and configure the system to your project.
- **A documentation site** — everything organized by lifecycle area, published with GitHub Pages.

## Who it's for

- Maintainers of open-source projects who want an agent co-maintainer.
- Teams standing up an autonomous or semi-autonomous maintenance system.
- Anyone who has built a one-off agent workflow and wants a principled, reusable foundation instead.

## The core idea in one paragraph

Reading is cheap and safe; **writing to a public surface in the project's voice needs a human
decision unless it is reversible, mechanical and watched.** Everything upstream of that line —
discover, classify, dedupe, review, draft, rank, gate — an agent can do autonomously with the right
guardrails. The irreversible, reputational acts (merging code, closing on taste, posting publicly
as the project) stay human-gated, and a reversible, mechanical public write runs unattended only
with an independent watchdog. That membrane is not a limitation; it's what makes running the whole
thing unattended *safe*.

---

## Start here

- **[Quickstart](quickstart.md)**: adopt Steward on your repo in one sitting. It gets the skills in, runs the
  setup interview and runs one supervised loop.
- **[Architecture overview](docs/architecture/index.md)**: the four roles, the bands and the security spine.
  About 15 minutes; everything else builds on it.

Full map: **[docs/README.md](docs/README.md)** · Published site: **<https://nesquena.github.io/steward-os/>**

## Repository layout

```
docs/
  architecture/    the operating model — roles, bands, security spine, principles
  lifecycle/       end-to-end playbooks per area (issues, PRs, gates, community, contributors)
  playbooks/       cross-cutting recipes (autonomy ladder, watchdog pattern, cron design)
  reference/       glossary, FAQ, adoption levels, anti-patterns
setup/
  setup-interview.md   the documented question list the agent runs with you
  config.template.*    the config the interview produces
  config.yaml          this repo's own filled config (a worked example)
skills/            loadable agent procedures, linked from the playbooks
bin/               the three contract lints (skills, config, anchor links) and bin/ci
lib/               the code behind the lints
test/              their tests
```

To run what CI runs, use `bin/ci` (needs Ruby, version in `.ruby-version`, and `bundle install`).
`bin/ci contracts` runs the tests and lints. `bin/ci site` builds the site and checks its links.

## Status

In use, and still evolving. The architecture and lifecycle playbooks are the stable core; the skills and the setup
interview keep improving with use. This repo runs on Steward itself, with several agents building, reviewing, gating
and merging its changes: [Steward on Steward](docs/reference/steward-on-steward.md) shows how, and what isn't
running yet. Contributions and adaptations to your own project are the whole point — see
[CONTRIBUTING.md](CONTRIBUTING.md).

## License

[MIT](LICENSE) — use it, adapt it, run your project with it.
