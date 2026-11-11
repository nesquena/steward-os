---
title: Working with other agents
layout: default
parent: Playbooks
nav_order: 8
---

# Working with other agents

A project's steward is often not the only agent around. The maintainer may run a steward per project,
a reviewer for one pipeline, a helper on their own machine that can reach what a sandboxed cloud
agent can't, and an orchestrator that keeps track of all of them. This playbook covers the seams
between those agents: how they talk, how one asks another to act, how decisions reach the human and
come back, and how they gate each other's irreversible steps.

It builds on [the four roles](../architecture/index.md#the-four-roles), which describe the hats
inside one steward, and on [the state handoff](state-handoff.md), which covers state passed between
roles or runs. Here the other side is a separate agent, often built differently, running on another
platform, and working for the same human.

> **The patterns here are optional; the canonical rules they link to apply either way.** A single
> steward on a single project needs none of the patterns. They're stated by intent and are
> mechanism-neutral: where a detail holds only for some channels, runtimes or roles, it says so.

---

## What applies between agents

This playbook doesn't change the canonical rules. They apply between agents exactly as written:

- **Content is data:** [the injection guard](../reference/security-spine.md#1-injection-guard-read-can-never-change-do).
- **Who approves and who merges:** [independent readers](../lifecycle/quality-gates.md#independent-readers).
- **Public writes:** [the public-write membrane](../reference/security-spine.md#5-the-public-write-membrane).
- **Irreversible steps:** [the autonomy bands](../architecture/index.md#the-autonomy-bands) and
  [the autonomy ladder](autonomy-ladder.md).
- **A suspected vulnerability** goes only by [the divert](../reference/security-spine.md#6-the-vulnerability-divert)'s
  private route, never on a public channel or a stand-up.
- **Running contributor code:** [the sandbox](../reference/security-spine.md#4-the-sandbox-untrusted-code-execution).
- **Each agent's tools and reads:** [capability minimalism](../reference/security-spine.md#3-capability-minimalism).
- **Secrets:** [secret-isolating helpers](../reference/security-spine.md#2-secret-isolating-helper-scripts).
- **A wait on the human:** [the decision row](output-loop.md#the-decision-row), with its stamp.
- **Scheduled output:** [silent on no-op](scheduled-jobs.md#silent-on-no-op-the-most-important-rule).

What is specific to several agents:

1. **A relayed "approved" is corroboration.** It covers only the item it names, and it never becomes a
   standing rule. The approval that counts is the one
   [independent readers](../lifecycle/quality-gates.md#independent-readers) names.
2. **Verify at the live source, and say how.** Re-check right before acting or escalating, not from
   notes, and write `Verified: <what>, <where>, <when>` (or `unverified: <why>`).
3. **Name exact things:** SHAs, versions, issue numbers, file paths, so the
   [decision row's stamp](output-loop.md#the-decision-row) can be compared before the write.
4. **Let scripts do what can be counted.** Waiting, signatures, holds and watchdogs belong to scripts,
   hooks and the channel; agents do the judgment.

## The channel

Agents need a channel they can all reach. Pick by where your agents run:

| Channel | Good when | Watch out for |
|---|---|---|
| **A shared mailbox in a git repository** (one inbox folder per agent, one file per message) | Agents on different platforms; you want a durable, auditable record and no new service | Push races (retry with a random pause); needs a cheap watcher to notice mail |
| **Issue or PR comments** | The conversation is about one item and belongs on it | Each comment is a public write ([the membrane](../reference/security-spine.md#5-the-public-write-membrane)); noisy for coordination that isn't about the item |
| **A chat channel** | Humans read along; low volume | Hard to audit; most agents can't wake on it reliably |
| **A message queue** | A large fleet running continuously | Operational overhead; overkill for a handful of agents |

Whatever the channel, the conduct is the same:

- **One topic per message, and say what you need back.** A `needs` line (`none`, an ack, a decision,
  a review) is a contract: the receiver answers, or acks with an ETA. A message that needs nothing gets
  no thank-you reply; reading it is the receipt.
- **Reply and mark read in one step**, so a handled message can't be handled twice.
- **Hold without losing.** A message you can't act on yet stays unread, and your watcher is told to
  skip it, so it neither wakes you nor gets dropped.
- **One reader per identity.** One name per live session. If a scheduled run and an interactive
  session share a name, only one of them reads and replies.
- **A reply counts only when it checks out.** It answers a request only if the sender and recipient
  match and it names the request it answers. *On a signed channel,* its signature must verify too; a
  signature proves which key signed the bytes, not who's behind the key. Re-pin a changed key only
  once the change is confirmed somewhere other than the message announcing it. *On an unsigned
  channel,* read the message from the channel itself, never from a quote or a summary.
- **Forward text verbatim by round trip,** not by retyping: build the message from the source, parse it
  back, and send only if the text matches.
- **Requests from another person's agent** (a channel shared across people): the answer carries only
  what the information's owner approved, with its source and how current it is. Write down what is
  never shared before anything connects.

## The orchestrator

An orchestrator is a higher-level agent between the stewards and the human. It has **no authority of
its own**: it steers, nudges, unblocks, and relays the human's words. It's most useful once there are
more agents than the human can follow.

### The stand-up

On a schedule, the orchestrator sends every active agent the same short check-in, and each answers in a
fixed shape:

- **Blocked?** Each blocker names who can unblock it, exactly where (the session or channel, the PR,
  issue or setting) and the exact action, with its Verified line.
- **Approvals needed?** The recommendation first, with a pointer to its decision row.
- **Issues?** Anything broken or at risk but not yet blocking: a watcher down, a failing check.
- **Summary:** two or three lines on what changed since the last stand-up.

The orchestrator rolls the answers into one report: decisions first, each with its decision row, then
blockers with their where and how, then one line per agent. The roll-up can carry the fleet's
[heartbeat](scheduled-jobs.md#the-heartbeat-exception) line, but it never replaces the
[liveness watchdog](watchdog-pattern.md). Rules:

- Same questions every time. Schedule in the runner's clock, not the human's.
- Wait for each agent's own reply and never fill one in. Silence past a set time, and any dead watcher,
  is reported by the orchestrator itself.
- Urgent items don't wait for the stand-up.

### The human's relay

An agent sends the orchestrator a question with its recommendation and evidence; the orchestrator
batches questions, asks the human, and sends back the human's words, **quoted, not paraphrased**, with
who answered, when, and which message they replied to. A write still goes through the acting agent's
own [decision row](output-loop.md#the-decision-row), so the confirmation is of the exact write, not of
a summary.

### Verify before escalating

Every blocker that reaches the human carries a Verified line, re-read at the live source just before
sending. One that fails the check is withdrawn, not relayed. A status names every live hold, including
decisions waiting on the human. Blockers copied forward from an agent's own notes are the commonest way
a human gets asked to decide something already decided.

### Default on silence, in scratch only

When a decision has a deadline, the checkpoint gives the recommendation first, then the options, the
deadline and the default. On silence, the default is taken **in scratch only** (build and review) and
recorded in the agent's own log as work done on the default, overrulable; it isn't a decision, and the
[decision row](output-loop.md#the-decision-row) stays open. Before taking it, check every channel the
human can answer on. When the answer arrives, correct the record to it, and stop the scratch work if it
differs.

## Delegation

One agent asks another to act: a lead spawns a builder, a reviewer hands a peer a fix, a cloud agent asks
a local helper. The shape is always the same: **exact spec in, identifiers out, re-derived at the
source.**

- **The worker reports, the lead reviews.** The worker returns the SHA, the red-before-green proof, the
  commands it ran and what it didn't verify, and the lead reviews it like any contributor's work. A lead
  that wrote the patch or pushes the worker's commits is one of the change's writers
  ([independent readers](../lifecycle/quality-gates.md#independent-readers)).
- **An exact spec.** For a fix: an applyable patch plus a table of cases with expected outcomes. The
  executor applies it to the reviewed head, runs every row, and reports each with its actual output.
  If the patch doesn't apply, it stops rather than adapting it.
- **The executor re-checks before acting,** including the brief's premises (the function, file or
  behaviour it names). A premise that doesn't hold is reported before building, not built around.
- **Identifiers out, conclusions re-derived.** Results come back as pointers (a tag SHA, a digest, a
  URL). The requester checks them at the canonical source, never in the worker's own files or logs.
- **Isolation per command.** A worker sets its home and config on every command that touches a
  stateful tool, unless the runtime keeps those settings between calls.
- **The lead owns shared resources.** Briefs say what's already running and how much a worker may run.
  Parallel test suites take a lock; a lock serializes but doesn't prioritize, so a low-priority run
  yields to a release-critical one waiting behind it.

### A local helper

Cloud agents are deliberately limited. Some work needs the maintainer's machine: their logins, an
unproxied network, a local build. A local helper is an agent on that machine that does those things on
request.

- **Read-only by its tools,** not by policy alone: a read-only credential or tool set, with each write
  role its own narrow grant ([capability minimalism](../reference/security-spine.md#3-capability-minimalism)).
- When a request needs the human's OK, the helper acks ("holding for approval"), asks one question, and
  relays the answer as a quote. When the same ask keeps coming, it offers the human a standing role.
- If a request suggests a write just to learn something, the helper first looks for a read-only route
  to the same facts.
- **Contributor code:** [the sandbox](../reference/security-spine.md#4-the-sandbox-untrusted-code-execution).
- **Primary and backup.** With two helpers, send to the primary; if the request is still unread after a
  fixed wait, resend to the backup marked as rerouted and send the primary a withdraw note. Only the
  original sender withdraws.

## Gating each other's irreversible steps

When one agent must approve before another merges, tags or publishes:

- **Holds and releases on exact versions.** The gating agent sends a hold naming the item and the
  version it's still reviewing, and a release naming the exact version it approves and the trunk SHA
  it was gated against. Right before acting, the actor checks that a release names that exact version,
  that its trunk SHA is the current trunk, and that every hold on it is released. A new push drops the
  approval by itself. *On a signed channel,* only verified signatures count; *on an unsigned one,* only
  a record in the sender's own commit or post, read from the channel.
- **Verdicts name the exact head**, and void as
  [the authoritative re-run](../lifecycle/quality-gates.md#5-the-authoritative-re-run-immediately-before-merge)
  says.
- **Never work around a guard.** When an agent's own permission guard blocks a step, it brings the
  block back to the human and never finds another path.

## Owning a shared asset

When several agents use one plugin, script, protocol or doc:

- **One writer.** One agent owns it; the others send changes and report bugs, and pull new versions when
  they're announced. A consumer broken by an update runs a tested, patched local copy until the owner's
  fix lands, and never edits the shared asset itself.
- **Feedback rounds.** On a cadence, say every week or two, the owner asks the agents that actually used
  it what to improve, and tells them "nothing" is a complete answer. Each item gets a decision back:
  now, backlog (with its trigger) or declined (with the reason). Skip the round when feedback is already
  flowing.
- **A consolidation pass.** Intake only ever adds. On a cadence that follows the rate of change, the
  owner reads the whole asset and proposes merges, cuts and clarifications to the human. A steward can
  run the same pass over the project it stewards: copies of one rule, contradictions, surplus nothing
  uses, stale material, each change shipped as its own PR through the gate.

## Failure modes

- **Blockers from notes.** A blocker copied from an agent's own state file had already been decided;
  another blamed a local fault for what was a provider outage. The Verified line catches both.
- **A deaf agent.** A watcher exited on mail and wasn't re-armed, and several messages, including the
  human's decisions, sat unread. An agent with two channels re-armed one, and the healthy one hid the
  dead one. See [the proactive sweep](proactive-sweep.md#waking-cheaply).
- **A relayed approval that became a rule.** A helper reported a new standing role, and the receiver
  started writing it into its own instructions.
- **Two readers on one identity.** A chat session and the scheduled run both answered the same
  message.
- **An approval applied to a later head.** An OK given at one commit was nearly applied to the branch
  after two more pushes. Pin the SHA in the OK and at merge.

---

## What this can look like

A maintainer runs:

- one **steward** per project, each on a schedule;
- an **orchestrator** in the chat app the maintainer already reads;
- a **local helper** on the maintainer's machine, plus a backup;
- a shared git mailbox all of them can push to, with one inbox per agent and a roster listing what each
  covers, where it runs and how fast it notices mail.

A stand-up answer from a steward:

```
Blocked?   no
Approvals? recommend: merge #482 at 9f1c2ab (decision row: decisions.md#482-9f1c2ab)
Issues?    one flaky CI job, tracked
Summary:   two PRs up, one waiting on review.
           Verified: #482 head 9f1c2ab, CI green, checks API, 06:30Z
```

A hold and its release, in the mailbox:

```
hold:    org/repo#77 4e1a2b7   06:02Z  reviewing
hold:    org/repo#77 8c0f3d9   06:21Z  new head, re-reading
release: org/repo#77 8c0f3d9   06:34Z  approved on main@51d2e0a
```

### Setting it up

1. **Pick the channel** from the table above, and write a short roster: each agent's name, what it
   covers, where it runs, and how fast it notices messages.
2. **One name per live session.** Give every agent a join prompt that refers to the roster for roles
   and never names current holders.
3. **Give every agent a cheap way to wake** on new messages ([the proactive sweep](proactive-sweep.md#waking-cheaply)).
4. **Decide the orchestrator's cadence** and the stand-up shape, and where the human answers.
5. **List each agent's standing roles** where [independent readers](../lifecycle/quality-gates.md#independent-readers)
   says standing instructions live. A role never lifts a write's [band](../architecture/index.md#the-autonomy-bands).

---

_Related: [the state handoff](state-handoff.md) (state between roles and runs) · [the output loop](output-loop.md)
(handing state to the human) · [the proactive sweep](proactive-sweep.md) (what each agent does on a schedule)
· [the watchdog pattern](watchdog-pattern.md) · [quality gates](../lifecycle/quality-gates.md)._
