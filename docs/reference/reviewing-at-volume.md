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

---

## Wrong premise beats bad code

The single most common reason a *well-built* change gets closed is not code quality. It's that the
change rests on a **wrong mental model of the system**, or it treats an **intentional design as a
gap**. This is the review-side edge of [surface ambiguity](coding-principles.md#1-surface-ambiguity-before-writing-code),
and it is sharper than the author-side version.

- **Intentional design, not a gap.** A limitation that looks like an oversight is often deliberate.
  A "missing" link between two isolated components may be missing *because the isolation is the
  design* — with a separate, sanctioned path already covering the legitimate use case. Before
  "fixing" an absence, read the history of the code that would change (`git log -p -- <path>` and
  `git blame` recover the commit and the reasoning; `git log -S <string>` when you're hunting the
  exact addition or removal of a literal) and recover the original intent. The absence may be
  load-bearing.
- **The premise doesn't hold against how the system actually works.** A change can be internally
  coherent and still target a bug that doesn't exist as described — a guard that re-tries something
  already proven pointless, a new branch that provably never executes because an earlier guard
  already consumed the state it depends on.
- **The bar to enforce.** Require falsifiable evidence: a reproduction on the current trunk (or
  another concrete demonstration) *and* a traced code path from symptom to cause. "The fix changes
  this exact line's behavior" is the ideal when the bug has a single manifestation site; emergent or
  cross-component bugs won't, so the general bar is *demonstrated, not asserted.* A confirmed
  reproduction beats a plausible-sounding rationale every time.

This deserves to be its own principle: **verify the claim *and* the intent against the codebase
before writing the fix.** Agents are especially prone to the failure — they produce fluent,
internally-consistent rationales for fixes to bugs that aren't real.

A corollary for anyone running *automated* triage: wrong-premise and "we don't want this" closes are
**taste calls that stay with a human.** Automation can *classify* a change (already-fixed-on-trunk,
cannot-reproduce, incoherent), request more information, and *recommend* a close — but the autonomous
*close* itself belongs only to the mechanically-provable gate this repo already defines: a fix proven
shipped and fully resolved ([issue lifecycle](../lifecycle/issue-lifecycle.md#close-with-credit-careful--this-is-public)),
or the tightly-bounded reversible cases under [closing on taste autonomously](anti-patterns.md#scope--contributor-anti-patterns).
Cannot-reproduce and incoherent both routinely turn out to be environment gaps or communication
problems, so they warrant a needinfo or a recommendation, not an unattended close. The sweeper's job
is to avoid wrongly closing legitimate work.

---

## Widen to the whole class before you merge

This repo already says [fix the class, not the instance](bug-shapes.md#8-the-instance-fix-that-left-the-class-alone).
The operational addition from high-volume review: **widening to sibling sites is part of the fix,
not a follow-up.** The default posture is *never merge incomplete code to the trunk — salvage it and
finish it first.*

- If a change clears state on one reset path, audit *every* reset path in the file before merge.
- If it guards one call to an endpoint, audit every call.
- This repo also treats history as evidence for missed siblings, the files that change together
  with the ones a diff touches: see [what changes together lives together](coding-principles.md#what-changes-together-lives-together).
- "Merge now, open a tracking issue for the siblings" is an anti-pattern when the widening is cheap —
  and it usually is, a couple of lines per site. Tracking issues for cheap widening are where bug
  classes go to survive.

### Two traps when you widen

Widening a fix across sibling sites has two failure modes worth naming, both cataloged as bug
shapes: a shared helper that re-acquires a lock some of its callers already hold
([bug-shape #9](bug-shapes.md#9-the-shared-helper-that-deadlocks-under-a-held-lock)), and a cleanup
copied to a sibling site at a lifecycle phase where the state is still needed
([bug-shape #10](bug-shapes.md#10-cleanup-at-the-wrong-lifecycle-phase)).

---

## Salvage over request-changes

The biggest lever on both throughput and community health: **default to salvaging a change, not
bouncing it.** Most external changes on a fast repo are stale against the trunk. That's the normal
case, not a defect — asking every contributor to rebase creates weeks of latency and abandoned work.

The flow that scales:

1. **Sweep for duplicates first.** A popular bug attracts two to four independent fixes. Search open
   *and* closed changes with several keyword variants — including synonyms, because "toggle" /
   "gate" / "disable" / "respect &lt;setting&gt;" all describe the same config-flag feature — plus the
   issue number. Pick the cleanest fix to build on, **credit the author of the commits you actually
   ship**, and acknowledge the earliest independent submitter (and anyone whose work you fold in)
   separately in the close. A phrasing-only sweep that misses an earlier duplicate forces an awkward
   credit-correction later — find them all before you decide whose commits ship.
2. **Cherry-pick the contributor's commits onto the current trunk** — authorship survives in git
   history.
3. **Widen to sibling sites as a separate commit** (yours).
4. **Preserve contributor authorship through the merge — verify it survived.** A rebase/merge that
   keeps the individual commits is the simplest way; a squash collapses commit-level authorship, so
   if your platform or merge queue requires squash, carry the credit explicitly with `Co-authored-by`
   trailers. The invariant is *the contributor's attribution is intact on the trunk after merge* —
   confirm it, don't assume the merge method preserved it.
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

A named trap that belongs with salvage work: **merging a stale branch can silently revert recent
fixes, but only when the stale copy rides inside the branch's own diff**, a risk the flow above
carries when a cherry-picked commit contains a stale whole-file rewrite. The shape and its guards
(scan the changed-file list, read the effective diff, re-fetch the trunk and preview the merge) are
[bug-shape #11](bug-shapes.md#11-the-stale-branch-that-reverts-recent-work-on-merge).

---

## Two test anti-patterns that generate the most noise

This repo's [test discipline](coding-principles.md#5-test-isolation-and-tests-that-assert-intent)
covers isolation and asserting intent. Two concrete, enforceable rules account for a large share of
review friction at volume:

- **No change-detector tests.** A test is a change-detector if it fails whenever data that is
  *expected to change* gets updated — a catalog count, a version literal, an enumeration size, a
  hardcoded list — *and that data is not itself the contract.* `assert len(providers) == 8` adds zero
  behavioral coverage and guarantees routine updates break CI. The litmus: if the test pins
  incidental current data, delete it; if it encodes a contract about how two pieces of data must
  relate, keep it. Rewrite `assert "item-x" in catalog` into
  `for item in catalog: assert item in the_related_index`. (The exception that proves the rule: when a
  specific value, snapshot, or member genuinely *is* the guarantee — a required entry, a golden output
  a consumer depends on — pinning it is a real contract, not a change-detector.)
- **Don't test the shape of the source.** A test that regexes a source file is testing the *shape of
  the code*, not its behavior. It passes when the implementation is subtly broken and fails on
  correct refactors — wrong in both directions — and it blocks structural cleanup forever. If the
  logic can't be called directly because it's buried inline, that's the signal to extract it into a
  testable function, not to regex around it. Agent-authored changes produce this constantly because
  it's the cheapest way to make a test go green. (The narrow exception: when a *structural or
  layout* property genuinely is the contract — a generated-file marker, a security policy that no
  source path may import a forbidden module — a test that asserts it directly is legitimate, provided
  it fails on a real violation.)

Both now live as [anti-patterns](anti-patterns.md#review--quality-anti-patterns), alongside the
[vacuous test](bug-shapes.md#6-the-vacuous-test). And the
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
direction is *compensating for a model's mistakes*. The default is to close them — even when the bug
is real and the tests pass — because they push an open-ended repair burden into the code:

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
these are the hardest closes to make — real bug, clean diff, passing tests, wrong direction. The
line to hold: reject *open-ended, heuristic* repair that masks the failure; a *bounded, documented*
compatibility shim can be a legitimate, deliberate feature when the project can't control an upstream
consumer — the test is whether the behavior is finite and declared, not whether it touches model
output at all. For a scheduled job,
[the model-output rules](../playbooks/scheduled-jobs.md#when-a-models-output-feeds-a-script) draw
the line: declared shims for how a reply arrives, then a closed schema that rejects. This is also an
[anti-pattern](anti-patterns.md#review--quality-anti-patterns).

---

## The footprint ladder: where a capability lands

The [minimalism ladder](coding-principles.md#the-minimalism-ladder) is about *lines of code*; the
[footprint ladder](coding-principles.md#the-footprint-ladder) is the second axis: **where a
capability lands determines its permanent cost.** The review habit is to ask **"which layer is this
landing in, and what does that layer cost forever?"** *before* "is the code good?", and to say in
its two recurring closes (speculative infrastructure, third-party integrations in the core tree)
that they're coupling decisions, not quality bars.

---

## Invariants a reviewer can't see in the diff

Every mature codebase has architectural invariants a locally-correct diff can silently violate:
they pass every test and behave identically until production, so CI can't catch them. Keep a short
**invariants list** in the repo's agent-entry file and check any review of a touched subsystem
against it; [bug-shape #12](bug-shapes.md#12-the-invariant-the-tests-dont-encode) has examples of
the genre and how to catch them.

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
- **Fabricated identities.** A contributor may open a burst of changes with commits authored as
  invented, official-looking identities (impersonating a maintainer or a CI bot). Close on
  *evidence*, not appearance: confirmed impersonation, misattributed authorship, or provenance you
  can't verify. When it's genuinely one of those, close all and salvage nothing — bundled commits can
  mix appropriated work with unverified changes. But an unusual name or email is not itself proof: a
  legitimate newcomer, a pseudonym, or a privacy identity looks the same from the outside, and a
  *known* contributor's declared, agent-assisted alternate identity is fine. When only the appearance
  is odd, ask for an authorship attestation and review the commits on their merits rather than
  rejecting on identity inference — an inference that would also lock out first-time contributors.

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
  oversight: [mark deliberate simplifications](coding-principles.md#mark-deliberate-simplifications).
- **No lazy-reading escape hatches on instructional content.** If a tool or doc serves procedural
  content an agent must follow completely, don't paginate it — models read page one and confidently
  skip the pitfalls on page three. Pagination belongs where partial reading is legitimate, not on a
  checklist that must be followed end to end.
- **A mitigation that destroys the feature it secures is the wrong mitigation.** Read the original
  commit's intent before restricting behavior, then find the fix that preserves the feature. Security
  changes are the most frequent offenders.
- **Dependency hygiene as policy, not preference.** Pin what you deploy and pin what executes: an
  application or deployable carries a lockfile (or an upper bound where it owns its runtime), git-URL
  dependencies pin to a commit hash, and CI actions pin to a hash. These close real supply-chain
  holes. The one place to *not* apply a blanket ceiling is a **library's** published constraints — a
  reflexive upper bound there pushes unresolvable version conflicts onto every downstream consumer, so
  a library caps only on a *known* incompatibility and lets consumers' lockfiles carry the pin. So a
  bare lower-bound-only constraint is an auto-reject in an application, but expected in a library.

---

_Related: [PR lifecycle](../lifecycle/pr-lifecycle.md) · [quality gates](../lifecycle/quality-gates.md)
· [coding principles](coding-principles.md) · [the bug-shape catalog](bug-shapes.md) ·
[anti-patterns](anti-patterns.md) · [contributor recognition](../lifecycle/contributor-recognition.md).
This page is the maintainer-side counterpart to [authoring a change that lands](authoring-changes.md)._
