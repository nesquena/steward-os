---
title: Quickstart
layout: default
nav_order: 2
---

# Quickstart: adopt Steward in ~15 minutes
{: .fs-8 }

Get an agent co-maintaining your repo, in supervised mode. No autonomy yet —
this is the on-ramp: read the model, wire the config, run one loop by hand, then climb.
{: .fs-5 .fw-300 }

---

## Before you start

- **A coding agent that can load skills** — anything that reads a `SKILL.md`-style procedure or a
  project rules file. Examples below use Claude Code, but nothing here depends on it.
- A **repository and an issue tracker** you maintain.
  The examples use a GitHub repository and the `gh` CLI. Your tracker and host can differ.
  With `gh`, check that it is authenticated (`gh auth status`).
- Ruby, to run `bin/config-lint` from the steward-os checkout.
- **Steward checked out locally** (`git clone https://github.com/nesquena/steward-os`) — you'll copy its skills in step 2.
- ~15 minutes and an open issue or PR you can practice on.

You do **not** need any autonomy, scheduled jobs, or a chat integration to start. Those come later,
on the [adoption ladder](docs/reference/adoption-levels.md).

The [skills](https://github.com/nesquena/steward-os/tree/main/skills) are runtime-agnostic
`SKILL.md` procedures. Wherever a step names a Claude Code path or command, it's a worked example —
the equivalent in your own agent works the same way. See
[adapting a skill to your runtime](https://github.com/nesquena/steward-os/tree/main/skills#adapting-a-skill-to-your-agent-runtime).

## 1. Read the model (5 min)

Skim the [architecture overview](docs/architecture/index.md) — the four roles, the autonomy bands,
and the one idea everything rests on: *reading is cheap; writing to a public surface in the
project's voice needs a human decision unless it is reversible, mechanical and watched.* You don't need the whole site
yet.

## 2. Get the skills into your repo

Put Steward's loadable procedures where your agent discovers skills. In Claude Code that's
`.claude/skills/`:

```bash
# from your project root, with steward-os checked out alongside it
mkdir -p .claude/skills
cp -R /path/to/steward-os/skills/* .claude/skills/
```

Your agent picks these up on next launch. (Using a different runtime? Drop them wherever it loads
skills, or point its rules file at them — the `SKILL.md` bodies are the same.) They're the
procedures the setup interview and the lifecycle playbooks tell the agent to load.

Keep the steward-os checkout in place and tell your agent where it is (for example in your rules
file). The skills link to its
`setup/` and `docs/` with paths written for the checkout's layout (like
`../../setup/setup-interview.md`), so from `.claude/skills/` the agent reads them in the checkout.

## 3. Wire it to your project

Have your agent load the **`project-system-setup`** skill and tell it:

> run the setup interview

The agent works through the [setup interview](setup/setup-interview.md) — your repos, scope anchors,
CI, review tools, autonomy posture — and writes a `config.yaml` for your project. It asks only what
it needs, accepts "skip" for anything optional, and never guesses.

Keep `config.yaml` on your trunk or outside the repo, and have the agent read it from there, never
from a pull request's checkout: the gates read it
([operator-controlled](docs/reference/security-spine.md#4-the-sandbox-untrusted-code-execution)).

To see a finished one, read Steward's own
[`setup/config.yaml`](https://github.com/nesquena/steward-os/blob/main/setup/config.yaml), which
configures this repo.

## Your tracker is your wiring

steward-os defines procedures. Your runtime supplies the tools that read and write issues.
steward-os ships no adapter and names no tracker.

- **Skills already say what they need.** Each `SKILL.md` names the facts it reads.
- **A missing fact stays missing.** If your tracker cannot supply a fact, the skill reports it as missing
  and never treats it as zero.
- **Write gates don't move.** Every write keeps its band, from `autonomy:` or from the skill that
  makes it, whatever the tool. A private tracker doesn't lower a band.

## 4. Prove it with one supervised loop (Level 1)

Pick an open issue or PR. Ask the agent to run the matching playbook **in a supervised session** —
you watch, it proposes, you approve every public write:

- An issue → load `issue-triage`, ask it to triage that issue and draft (not post) a reply. Pick
  one no one has answered yet: the skill drafts replies only for those (an answered issue still gets
  judged).
- A PR → load `pr-triage`, ask it to run the [fit screen](docs/lifecycle/pr-lifecycle.md#0-fit--scope-screen)
  and summarize.

`issue-triage` judges issues opened after its first run, plus any you name in your request, so your
practice issue still gets a judgment. The skills record judgments on a scoreboard and keep marks in
their own state. Until you've set those up, tell the agent where to keep them (state somewhere
private that only you write; the board no more visible than your issues), or to show them in the
session, in which case nothing carries over to later runs.

Nothing is posted without your say-so. That's Level 1: the playbooks run in supervised sessions, so
you get value on day one without handing over any autonomy.

## 5. Climb

You've done the read→run step. From here you add capability deliberately, one rung at a time:

- **Level 2:** a read-only [triage scoreboard](docs/playbooks/triage-scoreboard.md) and digests.
- **Level 3:** promote mechanical, reversible, watched actions to autonomy behind the
  [watchdog pattern](docs/playbooks/watchdog-pattern.md).
- **Level 4:** the full pipeline.

See the [adoption levels](docs/reference/adoption-levels.md) for the whole ladder, and
[Steward on Steward](docs/reference/steward-on-steward.md) to see it applied to this repo.
