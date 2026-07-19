---
title: Reviewing at volume
layout: default
parent: Reference
nav_order: 8
---

# Reviewing at volume — field notes

Most of this repo is written to the **author** of a change: how to write correct code
([coding principles](coding-principles.md)) and how to present it so it lands in one round
([authoring a change that lands](authoring-changes.md)). This page is the **maintainer-side**
companion — the review-time discipline that decides whether a change actually *lands*, and the
failure modes that show up most often at high volume, especially when a large share of the incoming
changes are written by AI agents.

> **Contributed by Teknium ([@teknium1](https://github.com/teknium1)) — co-founder of Nous Research**,
> whose team builds the open-source Hermes models and the Hermes agent. These notes are distilled from
> reviewing tens of thousands of pull requests on that fast-moving, open-source AI-agent codebase —
> one carrying heavy contribution volume from both humans and agents. Shared here with his permission
> and generalized for any open-source project: the project-specific detail is stripped, the scars kept.

Some of what follows sharpens rules this repo already states from the author's side. Those are kept
here on purpose, in the reviewer's voice, so this page reads as one coherent playbook rather than a
list of cross-references. Where a point has a fuller home elsewhere, it links there.

---

## Wrong premise beats bad code

The single most common reason a *well-built* change gets closed is not code quality. It's that the
change rests on a **wrong mental model of the system**, or it treats an **intentional design as a
gap**. This is the review-side edge of [surface ambiguity](coding-principles.md#1-surface-ambiguity-before-writing-code),
and it is sharper than the author-side version.

- **Intentional design, not a gap.** A limitation that looks like an oversight is often deliberate.
  A "missing" link between two isolated components may be missing *because the isolation is the
  design* — with a separate, sanctioned path already covering the legitimate use case. Before
  "fixing" an absence, read the history of the code that would change (`git log -p -S "<symbol>"`
  finds the commit that introduced it) and recover the original intent. The absence may be
  load-bearing.
- **The premise doesn't hold against how the system actually works.** A change can be internally
  coherent and still target a bug that doesn't exist as described — a guard that re-tries something
  already proven pointless, a new branch that provably never executes because an earlier guard
  already consumed the state it depends on.
- **The bar to enforce.** If the author cannot point to the exact line where the bug manifests *and*
  show that the fix changes that line's behavior, the premise is unverified. A confirmed
  reproduction on the current trunk beats a plausible-sounding rationale every time.

This deserves to be its own principle: **verify the claim *and* the intent against the codebase
before writing the fix.** Agents are especially prone to the failure — they produce fluent,
internally-consistent rationales for fixes to bugs that aren't real.

A corollary for anyone running *automated* triage: wrong-premise and "we don't want this" closes are
**taste calls that stay with a human.** Automation can safely close the mechanical categories —
already-fixed-on-trunk, cannot-reproduce, incoherent — but it must never close on design taste. The
sweeper's job is to avoid wrongly closing legitimate work, not to make the won't-implement call.
(This is the review-side of [closing on taste autonomously](anti-patterns.md#scope--contributor-anti-patterns).)

---

## Widen to the whole class before you merge

This repo already says [fix the class, not the instance](bug-shapes.md#8-the-instance-fix-that-left-the-class-alone).
The operational addition from high-volume review: **widening to sibling sites is part of the fix,
not a follow-up.** The default posture is *never merge incomplete code to the trunk — salvage it and
finish it first.*

- If a change clears state on one reset path, audit *every* reset path in the file before merge.
- If it guards one call to an endpoint, audit every call.
- "Merge now, open a tracking issue for the siblings" is an anti-pattern when the widening is cheap —
  and it usually is, a couple of lines per site. Tracking issues for cheap widening are where bug
  classes go to survive.

### Two traps when you widen

Widening a fix across sibling sites has two failure modes worth naming, both cataloged as bug shapes:

- **A shared helper can deadlock.** Factoring the fix into one helper that every sibling calls is the
  right dedupe move — but the call sites differ in whether they already hold a lock. A helper that
  unconditionally re-acquires a non-reentrant lock hangs the caller that already holds it. A mocked
  lock in a test doesn't block, so unit tests stay green; only a real-object end-to-end run catches
  it. See [bug-shape #9](bug-shapes.md#9-the-shared-helper-that-deadlocks-under-a-held-lock).
- **The same structure at the wrong lifecycle phase.** A sibling site that *looks* like the same bug
  (say, unbounded growth of a map) may be a phase where the state is still needed. Pruning
  per-item state at cache-eviction time is wrong if an evicted item's *session* is still alive and
  rebuilds itself from that state — the correct home is session-finalize, not eviction. Before
  widening a cleanup, grep for where the state is *read* on resume. "Evicted from cache" and "the
  work ended" are different lifecycle phases. See [bug-shape #10](bug-shapes.md#10-cleanup-at-the-wrong-lifecycle-phase).

---

## Salvage over request-changes

The biggest lever on both throughput and community health: **default to salvaging a change, not
bouncing it.** Most external changes on a fast repo are stale against the trunk. That's the normal
case, not a defect — asking every contributor to rebase creates weeks of latency and abandoned work.

The flow that scales:

1. **Sweep for duplicates first.** A popular bug attracts two to four independent fixes. Search open
   *and* closed changes with several keyword variants — including synonyms, because "toggle" /
   "gate" / "disable" / "respect &lt;setting&gt;" all describe the same config-flag feature — plus the
   issue number. Pick the cleanest fix and **credit the earliest submitter.** A phrasing-only sweep
   that misses the actual first submitter forces an awkward credit-correction later.
2. **Cherry-pick the contributor's commits onto the current trunk** — authorship survives in git
   history.
3. **Widen to sibling sites as a separate commit** (yours).
4. **Rebase-merge, never squash, when contributor commits are in the branch.** Squash destroys
   authorship. Squash only when every commit is yours.
5. **Close the original change with credit and a link.**
6. **The post-merge sweep is mandatory.** Re-search for open changes or issues the merge now
   resolves — a duplicate may have arrived while you were building. The highest-risk shape is the
   *investigation that became a fix*: you never entered "review mode," so the pre-flight dedupe sweep
   never fired.

This extends the repo's [bounce with care](../lifecycle/contributor-recognition.md#bounce-with-care) into a
default: prefer building on a contributor's commits over reimplementing cleanly from scratch, because
[credit is non-negotiable](../lifecycle/contributor-recognition.md#credit-the-unbreakable-rule) and credit lives
in the commits.

### The stale-branch revert

A named trap that belongs with salvage work: **squash-merging a stale branch silently reverts recent
fixes.** The stale branch's copy of an unrelated file overwrites the newer trunk when squashed. The
guards:

- Before pushing a salvage, confirm the branch isn't behind on files it didn't mean to touch.
- After merging, diff the merge itself — an unexpected deletion is a red flag.
- **Re-fetch the trunk immediately before merge.** A green change can be superseded during its own CI
  run by a parallel fix; ten seconds of `git log HEAD..origin/main -- <changed files>` beats
  discovering it through a later conflict.

See [bug-shape #11](bug-shapes.md#11-the-stale-branch-that-reverts-recent-work-on-merge).

---

## Two test anti-patterns that generate the most noise

This repo's [test discipline](coding-principles.md#5-test-isolation-and-tests-that-assert-intent)
covers isolation and asserting intent. Two concrete, enforceable rules account for a large share of
review friction at volume:

- **No change-detector tests.** A test is a change-detector if it fails whenever data that is
  *expected to change* gets updated — a catalog count, a version literal, an enumeration size, a
  hardcoded list. `assert len(providers) == 8` adds zero behavioral coverage and guarantees routine
  updates break CI. The litmus: if the test reads like a snapshot of current data, delete it; if it
  reads like a contract about how two pieces of data must relate, keep it. Rewrite
  `assert "item-x" in catalog` into `for item in catalog: assert item in the_related_index`.
- **Never read source code in a test.** A test that regexes a source file is testing the *shape of
  the code*, not its behavior. It passes when the implementation is subtly broken and fails on
  correct refactors — wrong in both directions — and it blocks structural cleanup forever. If the
  logic can't be called directly because it's buried inline, that's the signal to extract it into a
  testable function, not to regex around it. Agent-authored changes produce this constantly because
  it's the cheapest way to make a test go green.

Both are cataloged with the [vacuous test](anti-patterns.md#review--quality-anti-patterns). And the
enforcement teeth for [verify the real thing](coding-principles.md#4-define-done-up-front-then-verify-the-real-thing):
**a fix's test must fail against the *unfixed* code, for the right reason** — ask for that proof in
the change description. Green mocks are not evidence. Environment-variable loading, config
resolution, module caching, symlink handling, and container-networking bugs are all invisible to
mocked unit tests. For anything touching resolution chains, security boundaries, or I/O, require an
end-to-end run against a real (temp-dir-isolated) environment before merge.

---

## Don't absorb model failures into the codebase

This category doesn't exist in general-purpose contribution guides yet, and it matters for any
project whose consumers include LLMs. You get a steady stream of well-built changes whose fix
direction is *compensating for a model's mistakes*. Close them — even when the bug is real and the
tests pass:

- **Alias or synonym coalescing for wrong parameter names.** A model sends `cron` instead of
  `schedule`? The schema already names the parameter. Alias coverage is open-ended — the synonym set
  grows with every misbehaving model, forever, and it masks the real failure instead of surfacing
  it. The rejection *is* the correct behavior.
- **Repairing malformed tool-call output.** A clever self-validating pass that reconstructs broken
  JSON from a weak model is an unbounded game against every way a model can break its output. The
  right fix lives upstream: constrained decoding, or a better model.
- **Anything that stops sending tools to the model.** In an agent codebase, a change that quietly
  drops the tools list — usually as a side effect of overloading an unrelated config flag — silently
  deletes the product's core capability while passing every test.

The general principle: **distinguish wire-transport artifacts (fix them) from model non-compliance
(surface it).** A framework for agent-era open source should name this boundary explicitly, because
these are the hardest closes to make — real bug, clean diff, passing tests, wrong direction. This is
also an [anti-pattern](anti-patterns.md#scope--contributor-anti-patterns).

---

## The footprint ladder: where a capability lands

The [minimalism ladder](coding-principles.md#the-minimalism-ladder) is about *lines of code*. There
is a second axis: **where a capability lands determines its permanent cost.** In an agent codebase,
every core tool schema ships on every request for every user, forever — so a 100-line core tool can
be more expensive than a 1,000-line plugin. This has its own home next to the minimalism ladder — the
[footprint ladder](coding-principles.md#the-footprint-ladder) — and the review habit is to ask
**"which layer is this landing in?"** *before* "is the code good?"

Two ladder-adjacent closes recur, and both are coupling decisions rather than quality bars — say so
in the close:

- **Speculative infrastructure.** A hook or callback with no concrete consumer. Adding one is easy;
  removing it after third parties depend on it is nearly impossible. The nuance: a hook is *not*
  speculative if the contributor names a real use case, even if the consumer ships separately. The
  test is a real problem, not bundled consumer code.
- **Third-party product integrations in the core tree.** A vendor connector in the main repo becomes
  the maintainer's burden against a backend they don't own. Ship it as a standalone plugin. The
  plugin can be excellent and still be a close.

---

## Invariants a reviewer can't see in the diff

Every mature codebase has architectural invariants a locally-correct diff can silently violate.
These are the bugs CI can't catch — they pass every test and behave identically until production. A
review framework should force naming them. Examples of the genre from an agent codebase:

- **Prompt-cache stability.** A long conversation reuses a cached prefix every turn. Any change that
  mutates past context, swaps toolsets mid-conversation, or rebuilds the system prompt invalidates
  the cache and multiplies every user's cost — while behaving *identically* in tests.
- **Message-role alternation.** Many providers reject or mishandle two same-role messages in a row. A
  change that injects a synthetic message mid-loop passes every unit test and breaks in production.
- **Determinism where a cache keys off content.** A random-id fallback for a missing identifier looks
  harmless; it silently makes every replay of the same input a cache miss. Deriving the id
  deterministically from content is the invisible-but-mandatory choice.
- **Key by complete identity.** A partially-keyed cache leaks across profiles, sessions, or tenants —
  exactly and only under concurrency. (This one already has a home:
  [scope by complete identity](authoring-changes.md#validate-at-the-point-of-use-and-scope-by-complete-identity).)

The teachable move: keep a short **invariants list** in the repo's agent-entry file, and require any
review of a touched subsystem to check the change against it. "Passes tests" says nothing about the
invariants the tests don't encode. See [bug-shape #12](bug-shapes.md#12-the-invariant-the-tests-dont-encode).

---

## Design an interface when the third duplicate arrives

When three or more open changes integrate the same *category* of thing — storage backends,
providers, notifiers — stop merging them one at a time. Each one-off adds its own manager, its own
config surface, its own slice of the core. Instead: design an abstraction plus an orchestrator, wrap
the existing built-in as the first implementation behind it, adapt the best-submitted change as the
reference implementation, and turn the competing changes into plugins against the interface.

The trigger is mechanical — **the third duplicate is the signal** — which is what makes it teachable.
It turns N competing ~200-line core additions into N ~100-line implementations behind one integration
point.

---

## Trust boundaries on contributor claims

This repo already holds [never trust a contributor's stated numbers](anti-patterns.md#review--quality-anti-patterns).
Two extensions from the agent era:

- **Self-reports of side effects are not verification.** A claim of "uploaded successfully" or "all
  47 tests pass" must be re-derived by the reviewer: fetch the URL, run the suite, read back the
  artifact. This is doubly true for agent-authored changes, which state unverified claims with
  perfect confidence.
- **Fabricated identities.** A first-time contributor may open a burst of changes with commits
  authored as invented, official-looking identities. Policy: close all, salvage nothing — bundled
  commits can mix appropriated work with unverified changes. But disambiguate first. A *known*
  contributor's declared, agent-assisted alternate identity (a long real history plus a self-declared
  mapping) is legitimate. The tell is history plus self-declaration, not the odd-looking email
  address alone.

---

## Closing well is part of the job

A close is public and represents the project. Every close of a good-faith change gets three things:

1. explicit acknowledgment of the work's quality,
2. the specific reasoning — premise, design intent, or policy — with links,
3. credit if you implement an alternative.

**Credit outranks cosmetics:** prefer building on a contributor's commits over reimplementing
cleanly from scratch. The maintainer-side tone rules compound over years into whether people keep
contributing at all. This is the same value the repo states as
[credit is non-negotiable](../lifecycle/contributor-recognition.md#credit-the-unbreakable-rule), applied to the
moment a change *doesn't* land.

---

## Miscellany that earns its place

- **Docs and tests must run where the change lives.** A test in one language asserting about an
  artifact in another won't run when only the other language's files change — green on the change,
  red on the trunk. Tests live in the suite that the CI change-classifier triggers for the files they
  guard. (An [environment-divergence](bug-shapes.md#5-environment-divergence-works-locally-fails-in-ci)
  sibling.)
- **Mark deliberate ceilings.** A shortcut a reviewer can't distinguish from an oversight *is* an
  oversight. The repo already holds this — [mark deliberate simplifications](coding-principles.md#mark-deliberate-simplifications)
  — and it is worth endorsing loudly from the review side.
- **No lazy-reading escape hatches on instructional content.** If a tool or doc serves procedural
  content an agent must follow completely, don't paginate it — models read page one and confidently
  skip the pitfalls on page three. Pagination belongs where partial reading is legitimate, not on a
  checklist that must be followed end to end.
- **A mitigation that destroys the feature it secures is the wrong mitigation.** Read the original
  commit's intent before restricting behavior, then find the fix that preserves the feature. Security
  changes are the most frequent offenders.
- **Dependency hygiene as policy, not preference.** Every dependency gets an upper bound; git URLs
  pin to commit hashes; CI actions pin to hashes. Established after real supply-chain incidents. A
  bare lower-bound-only constraint (`>=X.Y.Z` with no ceiling) is an auto-reject at review.

---

_Related: [PR lifecycle](../lifecycle/pr-lifecycle.md) · [quality gates](../lifecycle/quality-gates.md)
· [coding principles](coding-principles.md) · [the bug-shape catalog](bug-shapes.md) ·
[anti-patterns](anti-patterns.md) · [contributor recognition](../lifecycle/contributor-recognition.md).
This page is the maintainer-side counterpart to [authoring a change that lands](authoring-changes.md)._
