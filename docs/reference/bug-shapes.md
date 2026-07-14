---
title: Bug-shape catalog
layout: default
parent: Reference
nav_order: 6
---

# Bug-shape catalog

Recurring bug *classes* — the shapes that show up again and again across projects, pass unit tests,
survive green CI, and surface only under the right conditions. A reviewer who knows the shapes spots
them in a diff; a builder who knows them avoids writing them.

Each entry: what it looks like, why the usual checks miss it, and how to catch it. The shapes are
language- and framework-neutral — the examples are illustrative, not specific to any stack.

---

## 1. Runtime coexistence

**Shape:** Two implementations of the same thing both remain live — an old helper and its
replacement, two data shapes for the same record, two handlers for the same event. Each works in
isolation; together they conflict, double-fire, or one shadows the other.

**Why checks miss it:** Unit tests exercise each path *alone*, where each is correct. The bug needs
*both* to run, which only happens in the integrated runtime — exactly what unit tests don't cover.

**Catch it:**
- When a change replaces a pattern, grep for the *old* pattern across the whole codebase before
  merging. Leftover callers are the bug.
- A rename or migration must be all-or-nothing. A half-applied rename (new name produced, old name
  still expected downstream) is this shape.
- Prefer deleting the old path over leaving it "just in case." Dead code that still executes isn't
  dead.

---

## 2. Producer changed, consumer didn't

**Shape:** A change updates where a value comes from (a new source of truth, a new format, a renamed
field) but a downstream consumer still expects the old form. The producer side is fully correct in
isolation; the read side silently gets the wrong thing.

**Why checks miss it:** The diff looks complete — the producer was updated and *its* tests pass.
Nobody tested the consumer against the new shape because the consumer wasn't in the diff.

**Catch it:** The moment a change is "swap A for B" / "change the source of truth," trace every
reader of the old value. Probe both ends: is the old shape still produced anywhere? Does every
consumer handle the new shape? (This is [coding principle 8](coding-principles.md#8-read-the-consumer-not-just-the-producer).)

---

## 3. Persistence loss wearing a presentation costume

**Shape:** Data "disappears" or "resets," and it looks like a view/render bug — but the data was
actually lost at the source (a save/clear race, a write dropped on an edge path). You debug the
renderer for hours; the renderer was innocent.

**Why checks miss it:** View-only debugging never inspects the persisted state, so the loss is
invisible. Everything in the view layer looks correct because it *is* correct — it's faithfully
rendering data that's already gone.

**Catch it:** Before touching the view, reload from the source of truth.
- Recovers on reload → presentation/refresh-layer bug.
- Still gone after reload → data-layer loss; fix the write/persist path.

(This is [coding principle 6](coding-principles.md#6-find-which-layer-owns-the-lost-state-before-fixing-it).)

---

## 4. Split ownership of one piece of state

**Shape:** Two layers both control the same thing — two places deciding whether a control is
visible/enabled, two caches of the same value, two flags for the same condition. They drift out of
sync, producing intermittent wrongness.

A common sub-form: **hiding or disabling a control does not disable the state that depends on it.**
A control gets hidden, but the logic that reacts to it (a position calculation, a dependent handler,
a derived value) still runs against the now-hidden thing and computes garbage.

**Why checks miss it:** In the test environment both owners usually agree, so nothing drifts. The
divergence needs a specific sequence (resize, re-entry, a state change between the two writers) that
tests rarely reproduce.

**Catch it:** Give every piece of state exactly one owner; the other side reads, never writes (see
[one state, one owner](coding-principles.md#one-state-one-owner)). When you hide or disable
something, audit what *depends* on it and guard those paths too.

---

## 5. Environment divergence (works locally, fails in CI)

**Shape:** A test passes in one environment and fails in another on the same code. Common causes: a
dependency present locally but absent in CI (or the reverse), a test that imports something only one
environment has, reliance on wall-clock timing or available cores, or a global mutated by an
earlier test that only runs in one shard. The reverse — green in CI, red locally — is the same class.

**Why checks miss it:** "It passes on my machine" is the whole trap — the environment difference *is*
the bug, and you can't see it from inside the environment that passes.

**Catch it:**
- The authoritative signal is the suite passing in the *target* environment (usually CI), not
  locally.
- A test that fails on every version/shard of one environment but passes locally points at an
  environment-specific import or dependency — mock at the boundary rather than importing the thing
  that isn't there.
- A test green in isolation but red in the full run points at cross-test state leakage — isolate it
  (fresh fixtures, no shared globals), don't just re-run it.

---

## 6. The vacuous test

**Shape:** A test that passes whether or not the code is correct — it asserts something always true,
checks for the mere presence of a symbol, or pins a surface string unrelated to the actual behavior.
It adds a green checkmark and zero protection.

**Why checks miss it:** It's green, and green tests don't get scrutinized. It only reveals itself
when a real regression sails through it.

**Catch it:** For every new test, confirm it *fails* when the implementation is reverted or broken
(red-before-green). If it can't fail, it isn't testing anything. Assert the contract — the behavior
that matters — not the incidental surface. (See
[coding principle 5](coding-principles.md#5-test-isolation-and-tests-that-assert-intent).)

---

## 7. The flake that's actually a bug

**Shape:** A test fails intermittently. The tempting read is "flaky, just re-run." Often it's a real
race condition, ordering dependency, or resource bug in the *product* — the test is the only thing
loud enough to surface it.

**Why checks miss it:** A re-run policy is designed to make it invisible. "Transient → rerun"
normalizes papering over a genuine defect.

**Catch it:** Treat every flake as a defect. Root-cause the signature; fix the underlying race or
ordering bug. If you track flakes, the output should be "flake detected — here's the signature, go
fix it," never "ignored, moving on." (See
[quality gates](../lifecycle/quality-gates.md#flakes-never-tolerate-one).)

---

## 8. The instance fix that left the class alone

**Shape:** A bug is reported at one call site, you patch that site, and three sibling call sites with
the identical flaw ship untouched. The report is closed; the bug is still in the product.

**Why checks miss it:** The reported case now works and its test passes. Nothing points at the
siblings because nobody looked for them.

**Catch it:** When you find a defect, grep for its *shape* across the codebase and fix the whole
class in one change. (This is a [guiding principle](../architecture/index.md#the-guiding-principles)
and a recurring [anti-pattern](anti-patterns.md).)

---

_How to use this: skim it before a deep review so the shapes are fresh, and add to it when your
project discovers a new recurring class. A catalog of the bugs that actually bite you is one of the
highest-leverage documents a project keeps._
