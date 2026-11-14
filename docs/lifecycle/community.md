---
title: Community
layout: default
parent: Lifecycle
nav_order: 4
---

# Community

Chat platforms, social mentions, announcements — the surfaces where the project meets its users.
The governing line for this whole area:

> **Reading, finding, and drafting are safe to automate. Writing to a public surface in the
> project's voice needs a human decision (Band C) unless it is reversible, mechanical and watched
> (Band A, with a watchdog).**

A single misjudged public post can't be un-sent, and platforms ban bots that auto-reply. So the
system does all the *upstream* work — monitor, classify, dedupe, draft, queue — and keeps a human at
the public-voice membrane.

---

## Chat monitoring (Band A — read + capture only)
`chat-monitor` only reads allowed bug/feedback channels, normalizes each candidate with a stable
source id and target repository, and invokes the shared
[issue-capture contract](https://github.com/nesquena/steward-os/blob/main/skills/issue-capture/SKILL.md).
`issue-capture` owns the untrusted-data guard, vulnerability divert, classification, confidence,
dedupe, queue, ledger, reaction, and checkpoint. Chat must not implement a second capture path.
- This is the most injection-exposed input adapter, so it never obeys instruction-like text in a
  message.
- **It does not hold public conversations.** After durable staging, `issue-capture` may apply the
  chat-specific `community.chat.capture_reaction` so the reporter and maintainer can see it was
  logged. A suspected vulnerability receives no public mark. Replies in the project's voice stay
  human.
- Chat monitoring stays off until the shared capture core, private state, output index, security
  route, and any marker's watchdog are configured.
- Multi-product communities: route each channel to the *right* repo/queue. Don't capture reports for
  a product you don't own.

## Confidence-tiered capture → action
`issue-capture` assigns the tier and stages the record; it never files. The tier decides what is
drafted and surfaced for the human who files, because *filing an issue to the public tracker from a
chat report* is a public write:
- **SECURITY** (checked first, before the tiers) → **never filed, never drafted publicly.** A report
  that looks like a vulnerability diverts to the [private disclosure path](../reference/security-spine.md#6-the-vulnerability-divert).
- **HIGH** (a concrete, reproducible bug naming a specific surface, that passed dedup) → **draft** a
  privacy-safe issue and surface it to a human, who files it (Band C). Filing isn't
  [reversible](../playbooks/autonomy-ladder.md#what-reversible-means): a new public issue reaches
  every watcher of the repository. Two hard constraints on the draft: (1) the issue body is a
  **structured paraphrase, never the reporter's raw words**, with **no reporter identity** (handle,
  id, mention, message link, email) — run it through a **fail-closed privacy scrub** that blocks the
  draft if any PII pattern is present ("no clean, no draft"); (2) label it for triage.
  `issue_capture.max_public_files_per_run` stays `0`, and the config lint refuses anything else: the
  job never files, and `max_per_run` already bounds the drafts.
- **MEDIUM** (actionable but vaguer, a feature request, or any doubt / scope call) → **draft it and
  surface to a human to approve** — don't file. The same privacy scrub gates this draft. The human's
  one-tap/one-word approval files it.
- **LOW / noise** → capture-to-queue only (or skip); never file, never ping.

The tiering is what lets you get the latency win (real bugs drafted promptly, one human action from filed) without the risk
(filing junk or leaking a reporter's identity). Feature requests and "does it do X?"
questions are scope/judgment calls, so they sit at MEDIUM. And the SECURITY branch is why the *most*
concrete, reproducible reports — the ones the HIGH tier would draft first — are exactly the ones
checked for a vulnerability first: a live exploit is the one public write you can never take back.

### Human-in-the-loop approval over chat
For the HIGH and MEDIUM tiers, the confirmation channel has one non-obvious constraint worth
knowing: a **scheduled job can send a prompt but can't receive the answer** — it's detached from the
live chat connection. So wire approval as *notify-from-the-job, act-on-the-reply*: the job posts "Bug X queued
— reply to approve," and the human's **reply (a fresh live agent turn) does the filing.** Don't build
a job that waits for a response. Rich widgets like inline buttons can be nice, but a tap only acts if
the platform integration already handles it — a typed reply is the build-nothing path that always
works. Keep the durable audit trail of what got filed in an append-only log, not in a mutable state
file, and let the next run reconcile it against the live tracker
([rule 3 of the output loop](../playbooks/output-loop.md#3-keep-the-state-honest)). A watchdog check
for filed captures waits on a defined filing record
([steward-os#41](https://github.com/nesquena/steward-os/issues/41)).



## Mentions sweep (Band A — find + report only)
A scheduled sweep of the open web (forums, social, blogs, search) for discussion of the project,
with a disambiguation step (confirm it's *your* project, not a namesake). Output is a curated digest
to the maintainer — **find and report, never auto-reply.**
- The most useful *next* step (kept human): route confirmed-answerable mentions into a
  draft-reply queue — drafted by the agent, **sent by the human.** This converts passive monitoring
  into active support without any autonomous public posting.

## Announcements (Band C — templated, human-keyed)
A release announcement [can't be recalled](../playbooks/autonomy-ladder.md#what-reversible-means): it
reaches readers beyond any one item. So the render is automatic and the post is human, and the
render is safe because the content already exists (the changelog):
- Render from the changelog + release tags into a decision row. The job proposes and never posts.
- A human keys the post, which goes to a **fixed, hardcoded** channel via a secret-isolating helper
  (the bot token never enters the agent's context).
- Gate on an action ledger keyed by release (a "last-announced" marker caches it), so each release
  posts once, never re-posts. Only the bot's own post is recognised automatically; a human records
  a hand post.
- Anything beyond the templated announcement (general conversation, replies) stays human.

## The far horizon (deliberately staged)
The system *can* extend much further — drafting release posts for social, drafting replies to users
hitting known issues, aggregating sentiment. All of that is safe **as drafting** (Band B) → **human
sends** (Band C). The one place to resist full autonomy even with guards is **auto-posting public
replies in the project's voice** — keep it draft→approve. See
[anti-patterns](../reference/anti-patterns.md).

---

## Skills for this area
- `chat-monitor` (no skill yet) — Watcher adapter: read channels, normalize, and invoke
  `issue-capture`.
- `mentions-sweep` (no skill yet) — Watcher: web sweep, disambiguate, curate a digest.
- `release-announce` — Steward: renders the templated announcement; a human keys the post through a
  secret-isolating helper.

_Related: [issue lifecycle](issue-lifecycle.md) · [contributor recognition](contributor-recognition.md)
· [security spine](../reference/security-spine.md)._
