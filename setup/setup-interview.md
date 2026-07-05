---
title: Setup interview
layout: default
nav_order: 7
---

# The setup interview

This is how the system wires itself to *your* project. An agent works through these questions with
you, and the answers produce your project's [config](https://github.com/nesquena/steward-os/blob/main/setup/config.template.yaml) — which then
parameterizes every playbook and skill.

**How to run it:** point your agent at this file and say *"run the setup interview."* It asks the
questions below in order, confirms each answer, and writes `config.yaml`. You can also fill the
[config template](https://github.com/nesquena/steward-os/blob/main/setup/config.template.yaml) by hand. The agent should ask only what it needs, accept
"skip / not yet" for any optional area, and **never guess** — an unanswered question becomes a
documented TODO, not an assumption.

> Design note: the interview is deliberately a *conversation with a documented script*, not a rigid
> form. The agent adapts follow-ups to your answers (if you say "no Discord," it skips the whole
> chat-monitoring block) and explains *why* it's asking, so you're configuring with understanding.

---

## Section 1 — Identity & repositories *(required)*
1. **What is the project?** One-line description. (Used in every public-facing template.)
2. **Which repositories does it span?** For each: host/owner/name, role (primary app, desktop,
   mobile, docs…), and visibility. Multi-repo projects route work to the right repo — list them all.
3. **What's the default branch / trunk?** (e.g. `main`.)
4. **What's the release model?** Tag-per-release? A changelog file? How does "shipped" get verified
   (a tag, a deploy, a running version)? → feeds the [PR lifecycle](../docs/lifecycle/pr-lifecycle.md)
   "done means shipped" rule.

## Section 2 — Scope anchors *(required — this is the most important section)*
The system can't screen PRs/issues for fit without knowing what "fits."
5. **What are your scope anchors?** The 1–4 things a change must serve to be in-scope. (e.g.
   "parity with X," "our core use case Y.") Anything hitting none of these gets the philosophy veto.
6. **What's your philosophy veto?** The qualities that disqualify a change even if it's well-built
   (e.g. "we are single-user not multi-tenant," "elegant not gimmicky"). → drives the
   [PR fit screen](../docs/lifecycle/pr-lifecycle.md#0-fit--scope-screen).
7. **What bypasses the scope gate?** (Default: bug/security/reliability fixes on already-shipped
   features. Confirm or adjust.)

## Section 3 — Chat & community *(optional)*
8. **Do you have a chat community?** (Discord/Slack/etc.) If yes: which platform, which channels
   carry bug reports vs. general chat, and the server/guild id.
9. **Should the agent monitor chat?** (Recommended: read + capture + a "captured" reaction; **no**
   autonomous text replies — keep the public voice human.) Confirm the reaction marker to use.
10. **Mentions sweep?** Should the agent sweep the open web for mentions of the project? Any namesake
    to disambiguate against?

## Section 4 — CI, tests & review tooling *(required for the gates)*
11. **How do you run the test suite?** The exact command, and roughly how long it takes (so jobs
    budget correctly and never sample it).
12. **What CI runs on PRs?** (So the system can read CI status into the scoreboard.)
13. **What review tooling exists?** Automated code-review bot? A second/adversarial reviewer? A
    visual-preview tool? → these become the [quality gates](../docs/lifecycle/quality-gates.md) layers.
14. **Visible-surface viewports?** If the project has a UI, which viewports must screenshots cover
    (desktop/mobile sizes)?

## Section 5 — Autonomy posture *(required)*
15. **What's your starting autonomy band per area?** For each of {labeling, issue-triage replies,
    issue auto-close, announcements, PR merge}: start at C, B, or A? (Default conservative: most
    start at B/C; only mechanical+reversible+watched actions start at A.) →
    [autonomy ladder](../docs/playbooks/autonomy-ladder.md).
16. **Where is the human reachable** for Band-B decision points and Band-C approvals? (Which
    channel/DM.)

## Section 6 — Secrets & safety *(required if any autonomous public write)*
17. **Where do credentials live?** Confirm they're in a permission-locked file that only
    secret-isolating helper scripts read — **never** pasted into config or an agent prompt.
18. **Will the system ever execute contributor code?** (e.g. run PR tests.) If yes, confirm a
    sandbox is available; if not, that capability stays disabled. →
    [security spine](../docs/reference/security-spine.md).

## Section 7 — Scheduled jobs *(optional, grows over time)*
19. **Which jobs do you want running, and how often?** (scoreboard refresh, chat monitor, mentions
    sweep, announcements, label-sync, issue-autoclose, the watchdog, a fleet heartbeat.) Start with
    a few; add as you climb the autonomy ladder. → [scheduled jobs](../docs/playbooks/scheduled-jobs.md).
20. **How does steward output reach you?** Default is a pull-based index you check (discovery);
    pushing a digest to a chat channel is an optional add-on. Also: where should watchdog alarms go?
    → [the output loop](../docs/playbooks/output-loop.md).

---

## What the interview produces
- A filled **[`config.yaml`](https://github.com/nesquena/steward-os/blob/main/setup/config.template.yaml)** capturing every answer.
- A short **TODO list** of any sections you skipped, so it's clear what's not yet wired.
- A recommended **starting job set** based on your autonomy posture.

Once config exists, every playbook and skill reads from it — the scope anchors drive the PR screen,
the repo list drives routing, the test command drives the gate, and so on. Re-run the interview any
time your project changes; it reconciles rather than overwrites.

---

_Next: load the [`project-system-setup`](https://github.com/nesquena/steward-os/blob/main/skills/project-system-setup/SKILL.md) skill, which runs
this interview as a guided procedure._
