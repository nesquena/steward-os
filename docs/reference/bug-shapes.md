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

Several shapes (7, 8 and 13) survive through a [special case](coding-principles.md#special-cases-are-a-signal)
a diff adds: ask what general cause it stands in for before accepting it.

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

## 9. The shared helper that deadlocks under a held lock

**Shape:** You widen a fix across sibling call sites by factoring it into one shared helper — the
right dedupe move. But the call sites differ in whether they *already hold a lock*. The helper
unconditionally re-acquires a non-reentrant lock, so the caller that already holds it hangs forever.

**Why checks miss it:** A mocked lock in a unit test doesn't block, so every test stays green. The
deadlock needs a *real* lock object and the specific caller that enters the helper already holding
it — an integration condition unit tests don't set up.

**Catch it:** When you extract shared code that touches a lock, audit each call site for whether it
already holds that lock, and make the helper's locking explicit (reentrant, or take-lock vs.
assume-lock variants). Prove it with a real-object end-to-end run, not a mock.

_Contributed by Teknium — see [reviewing at volume](reviewing-at-volume.md#two-traps-when-you-widen)._

---

## 10. Cleanup at the wrong lifecycle phase

**Shape:** A sibling site *looks* like the same bug as one you just fixed — unbounded growth of a map,
say — so you add the same cleanup there. But that site is a different lifecycle phase where the state
is still needed. Pruning per-item state at cache-eviction time is wrong if an evicted item's
*session* is still alive and rebuilds itself from that state.

**Why checks miss it:** The cleanup looks correct and its immediate test passes — the state does get
freed. The breakage only appears when something *downstream* tries to read the state after it's been
pruned, on a path the cleanup test never exercises.

**Catch it:** Before widening a cleanup, grep for where the state is *read* on resume/rebuild.
"Evicted from cache" and "the work ended" are different lifecycle phases; put the cleanup at the phase
where the state is provably no longer needed, not at the first phase that resembles the original bug.

_Contributed by Teknium — see [reviewing at volume](reviewing-at-volume.md#two-traps-when-you-widen)._

---

## 11. The stale branch that reverts recent work on merge

**Shape:** You merge a branch cut from an older trunk, and it silently reverts recent work — but
*only* when a stale copy of an unrelated file is part of the branch's own changes. A normal merge
(including a squash) is a three-way merge against the merge-base, so a file the branch never touched
keeps the trunk's newer version. The revert happens when the old copy rides *inside the diff*: an
agent that committed its whole working tree, a regenerated or vendored artifact, a wholesale file
rewrite, a conflict resolution that took the branch's side — or a salvage done with non-merge
mechanics (`git diff main..branch | git apply`, `git checkout branch -- .`) that replays stale
content wholesale.

**Why checks miss it:** The change under review looks correct and its tests pass. The reverted file
rides in on the diff as an incidental hunk nobody scrutinizes, or on the merge mechanics of a
non-standard salvage.

**Catch it:** Scan the branch's changed-file *list* for anything outside the change's stated intent —
a file the fix had no reason to touch is the red flag (being merely *behind* on untouched files is
normal and safe). Read the effective diff, not the commit list: a hunk that deletes recent trunk work
is the tell. Re-fetch the trunk immediately before merge (a green change can be superseded during its
own CI run by a parallel fix) and preview the merge result;
`git log <head-id>^{commit}..<trunk-id>^{commit} -- <changed files>` shows what landed since you
branched so you can inspect any overlap. Use commit IDs pinned the way the
[security spine](security-spine.md#4-the-sandbox-untrusted-code-execution) describes, not names
resolved in your clone: a proposal can bring in a tag called `origin/main` that empties this check.

_Contributed by Teknium — see [reviewing at volume](reviewing-at-volume.md#the-stale-branch-revert)._

---

## 12. The invariant the tests don't encode

**Shape:** A locally-correct diff violates an architectural invariant that no test checks — a cache
prefix that must stay stable across turns, a message sequence that must alternate roles, an id that
must be derived deterministically so a content-keyed cache still hits, a cache key that must include
every identity axis. The change behaves *identically* in every test and breaks (or silently taxes
everyone) in production.

**Why checks miss it:** The invariant isn't written down as an assertion anywhere, so "passes tests"
says nothing about it. The cost is often invisible (a cache-hit-rate collapse, a per-request price
multiplier) rather than a crash.

**Catch it:** Keep a short **invariants list** in the repo's agent-entry file, and require any review
of a touched subsystem to check the change against it. When you discover a new invariant the hard way,
add it to the list *and* — where possible — add a test that encodes it so it graduates from tribal
knowledge to an automatic check.

_Contributed by Teknium — see [reviewing at volume](reviewing-at-volume.md#invariants-a-reviewer-cant-see-in-the-diff)._

---

## 13. The refusal rule fixed one hole at a time

**Shape:** A denylist, permission check or input filter is fixed in rounds, and each round opens a
new hole: it now refuses something legitimate that the rule didn't anticipate (generated code, a
wrapper, an unnamed or nested type), or it still misses a variant of what it meant to stop.

**Why checks miss it:** Each round's test covers the case that round found. Nothing checks the
other side of the rule, so a fix that over-refuses or under-refuses passes its own test.

**Catch it:** Test both sides every round: what must be refused and what must keep working. Turn
each variant a round finds into a test on its side, and send every round's head through adversarial
review: it is done when that pass reproduces no new hole. After two or three rounds that each
reproduce one, stop patching and change the rule's shape (an allowlist, or parsing the input's
structure instead of matching patterns).

---

## 14. The refresh that overwrites what it couldn't read

**Shape:** A job rebuilds a file each run and carries part of it forward: it recomputes the fresh
data and merges in the judgment from the last copy. One run finds the last copy unparseable (a
truncated write, a hand edit with a typo, a format change) and treats it as empty. It writes a clean
new file, and every carried value is gone. The next run reads the clean file and has nothing left to
recover.

**Why checks miss it:** "Parse error, start fresh" looks like sensible defensive code, and every
test that feeds it a good file passes. The loss happens once, quietly, and the file it leaves is
valid.

**Catch it:** A read that fails is an error, not an empty result. When the prior state can't be
parsed, alert once, leave the file as it is, and write nothing over it until a human repairs it.
That rule covers every cause above. To stop a crash from causing a truncated write in the first
place, write each new copy to a uniquely named temporary file in the same directory, flush it to
disk, then rename it into place. Test it with a corrupt prior file and assert the file is unchanged
afterwards.

---

## 15. The one-way archive

**Shape:** An item leaves the active set (closed, merged, resolved) and its state moves to an
archive or is dropped with it. Then the same item comes back: reopened, or its revert reverted. The
job looks only in the active set, so it treats the item as new, and what it had built up (a
judgment, a counter, a parked mark) is gone or stranded in the archive. This is
[entry 10](#10-cleanup-at-the-wrong-lifecycle-phase) with a twist: the phase that ended can
restart, under the same id.

**Why checks miss it:** Tests cover the forward path: open, handled, closed, archived. Reopening is
rare, no fixture has it, and a reopened item looks exactly like a new one.

**Catch it:** For every path that takes state out of the active set, write down the path that
brings it back, and test the round trip: close, reopen, and assert what came back. When an item
reappears, look it up by its stable id, archive included, before treating it as new. If some
state shouldn't return (a judgment of content that changed while it was closed), mark it stale
rather than dropping it.

---

## 16. The lock held by a reused process id

**Shape:** A job's lock file records its owner's process id, and a new run checks whether that
process is alive before taking the lock over. The owner crashed, and the operating system has since
given its id to an unrelated process. The check finds a live process, so the lock is never taken
over. Every later run skips, and since skipping is the quiet path, nothing reports it.

**Why checks miss it:** An id is reused only after the counter wraps or across a reboot, which tests
never reach. In a container whose lock file survives the run (on a volume, or across restarts),
every run can start with the same low id, so the new run finds itself "alive" and the collision is
the common case. A naive check can also read "not allowed to signal that process" as alive.

**Catch it:** "A process with that id exists" doesn't mean "the owner is alive". Prefer a lock the
operating system releases when its holder exits: an advisory lock on a file held open for the run,
on a local filesystem. A flock lock stays held until every copy of its descriptor is closed, a
forked child's included, so set close-on-exec to keep a program the job starts from holding it, and
close the descriptor in any child the job forks without exec. Otherwise record the process start
time together with a boot id, since start times count from boot. A live but hung holder keeps any
lock, so a run that skips for a held lock reports how long it has been held, and alerts past a
limit. (The
[simple file lock](../playbooks/scheduled-jobs.md#coordination--durability) is usually enough; this
is how it goes wrong.)

---

## 17. Zero rows that read as an empty backlog

**Shape:** A job publishes a list (a board, a digest, a queue), and readers take it as the state of
the world. One run's fetch fails quietly: an expired token, a rate limit, a query that matches
nothing because a field was renamed. The job gets zero rows, publishes an empty list and exits zero.
Readers see nothing to do.

**Why checks miss it:** Empty is a valid result, and under
[silent-on-no-op](../playbooks/scheduled-jobs.md#silent-on-no-op-the-most-important-rule) a run
with nothing to report is a quiet one, so a failed fetch passes for one. Unless it checks, the job
can't tell "there is nothing" from "I couldn't see anything".

**Catch it:** Check each source's status, not just its row count, and fail the run on an error, as
[failure surfacing](../playbooks/scheduled-jobs.md#failure-surfacing) says.
Where a sudden drop to zero is unlikely (an open backlog of forty items going to none), compare with
the last run and alert instead of publishing. A list people trust says when it was fetched and which
sources answered, so an empty one can be checked.

---

## 18. The run record stamped at start

**Shape:** A job writes `last run: <time>` when it starts, then does its work. A run that crashes,
hangs or is killed halfway still leaves a current time. A watchdog or a reader checking freshness
sees a recent run and reports all clear, though nothing finished.

**Why checks miss it:** In every test the run finishes, so start and finish agree. They differ only
when a run dies, and a dead run is what the record is there to catch.

**Catch it:** Record start and finish separately. Write the finish record on every exit path,
failure included, with its outcome, and never before the work it vouches for; write it the way
[entry 14](#14-the-refresh-that-overwrites-what-it-couldnt-read) writes a file. A freshness check
reads the last successful finish, and treats a start with no finish after the job's timeout as a
failure. It's the logic of the
[fleet heartbeat](../playbooks/scheduled-jobs.md#the-heartbeat-exception): an absence is the alarm,
so nothing may fill it early.

---

## 19. The stored result that outlives the rules that made it

**Shape:** A job stores a derived result (a judgment, a classification, a score) so it doesn't redo
the work every run, and keys "already done" on the item alone. Then the rules change: a new rubric,
prompt, model or scoring fix. The stored results were made under the old rules, but the items
haven't changed, so the job never redoes them. Old-rule and new-rule values sit side by side with
nothing to tell them apart.

**Why checks miss it:** The cache is right for the case it was built for: unchanged rules. Tests
check that an unchanged item is skipped, which is exactly the behavior that hides this.

**Catch it:** Key a stored result on everything that produced it: the item's inputs and the version
of the rules (rubric, prompt, model id, schema). When the version changes, mark the old results
stale and re-queue them at a capped rate, rather than redoing everything at once or never. This is
[entry 12](#12-the-invariant-the-tests-dont-encode)'s "every identity axis" applied to stored
results. The [scoreboard's staleness rules](../playbooks/triage-scoreboard.md#when-a-judgment-goes-stale)
are this fix, and the per-item stamp in
[scheduled jobs](../playbooks/scheduled-jobs.md#when-a-models-output-feeds-a-script) uses the same
idea to bring parked items back.

---

_How to use this: skim it before a deep review so the shapes are fresh, and add to it when your
project discovers a new recurring class. A catalog of the bugs that actually bite you is one of the
highest-leverage documents a project keeps._
