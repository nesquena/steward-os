---
title: Home
layout: default
nav_order: 1
---

<div class="hero">
  <p class="eyebrow">For maintainers working with an AI coding agent</p>
  <h1 class="hero-title" id="steward">Steward</h1>
  <p class="standfirst">Playbooks and skills that turn your AI coding agent into a co-maintainer: triaging issues, reviewing pull requests, building fixes and shipping releases, while you make the calls that matter.</p>
  <div class="actions" markdown="1">
[Get started](quickstart.md){: .btn .btn-primary }
[View on GitHub](https://github.com/nesquena/steward-os)
  </div>
  <img class="mascot" src="assets/images/steward-mascot.webp" alt="Steward’s mascot: a pocket watch in a hooded cape, holding up a lantern" width="520" height="531">
</div>

<section class="jobs" aria-labelledby="what-it-does">
  <p class="eyebrow">What it does for your project</p>
  <h2 id="what-it-does">Eight jobs, from the first report to the release</h2>
  <p class="jobs-lede">The work every maintainer carries, in the order it moves through a project. Steward does the legwork. You make the calls.</p>

  <ol class="rail" role="list" aria-label="The five phases">
    <li><span class="dot" aria-hidden="true"></span>Take in</li>
    <li><span class="dot" aria-hidden="true"></span>Shape</li>
    <li><span class="dot" aria-hidden="true"></span>Build</li>
    <li><span class="dot" aria-hidden="true"></span>Check</li>
    <li><span class="dot" aria-hidden="true"></span>Ship</li>
  </ol>

  <ol class="job-grid" role="list">
    <li class="job">
      <div class="job-head">
        <svg class="icon" viewBox="0 0 24 24" aria-hidden="true"><circle cx="10.5" cy="10.5" r="6"/><path d="M15 15l5.5 5.5M8 10.5h5M10.5 8v5"/></svg>
        <p class="phase">Take in <span class="num" aria-hidden="true">1</span></p>
      </div>
      <h3 id="job-triage">Triage, reply and investigate</h3>
      <p class="promise">Every report read, de-duplicated and answered from the code.</p>
      <ul role="list">
        <li>Replies grounded in your actual code.</li>
        <li>Reproduces bugs and drafts clean issues.</li>
        <li>Spots reporters left waiting, and routes security reports privately.</li>
      </ul>
      <p class="call"><span>Your call:</span> what gets filed.</p>
      <p class="job-foot"><a href="docs/lifecycle/issue-lifecycle.md">Issue lifecycle</a></p>
    </li>

    <li class="job">
      <div class="job-head">
        <svg class="icon" viewBox="0 0 24 24" aria-hidden="true"><rect x="3.5" y="3.5" width="7" height="7"/><rect x="13.5" y="3.5" width="7" height="7"/><rect x="8.5" y="13.5" width="7" height="7"/><path d="M7 10.5v1.5h10v-1.5M12 12v1.5"/></svg>
        <p class="phase">Shape <span class="num" aria-hidden="true">2</span></p>
      </div>
      <h3 id="job-architecture">Architecture</h3>
      <p class="promise">Keeps your system's shape sound as it grows.</p>
      <ul role="list">
        <li>Fixes land in the layer that owns the problem.</li>
        <li>New capabilities go where they belong.</li>
        <li>Design questions get a full review.</li>
      </ul>
      <p class="call"><span>Your call:</span> the design direction.</p>
      <p class="job-foot"><a href="docs/reference/coding-principles.md#one-state-one-owner">One state, one owner</a></p>
    </li>

    <li class="job">
      <div class="job-head">
        <svg class="icon" viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="8.5"/><path d="M15.5 8.5l-2 5-5 2 2-5z"/></svg>
        <p class="phase">Shape <span class="num" aria-hidden="true">3</span></p>
      </div>
      <h3 id="job-design">Software design</h3>
      <p class="promise">Asks whether it's the right change before reviewing the code.</p>
      <ul role="list">
        <li>Traces every problem to its real cause.</li>
        <li>Turns repeated one-offs into one clean interface.</li>
        <li>Fixes the whole class of bug, not just the instance.</li>
      </ul>
      <p class="call"><span>Your call:</span> what's in scope.</p>
      <p class="job-foot"><a href="docs/reference/reviewing-at-volume.md">Reviewing at volume</a></p>
    </li>

    <li class="job">
      <div class="job-head">
        <svg class="icon" viewBox="0 0 24 24" aria-hidden="true"><path d="M4 18a8 8 0 1 1 16 0"/><path d="M12 18l4-6"/><circle cx="12" cy="18" r="1.2"/></svg>
        <p class="phase">Build <span class="num" aria-hidden="true">4</span></p>
      </div>
      <h3 id="job-quality">Code quality and efficiency</h3>
      <p class="promise">Small, surgical changes that fit your codebase.</p>
      <ul role="list">
        <li>Ten coding principles behind every change.</li>
        <li>Reuses what exists before writing anything new.</li>
        <li>Tests that prove intent, and no flaky ones.</li>
      </ul>
      <p class="job-foot"><a href="docs/reference/coding-principles.md">Coding principles</a></p>
    </li>

    <li class="job">
      <div class="job-head">
        <svg class="icon" viewBox="0 0 24 24" aria-hidden="true"><path d="M14.5 5.5a4 4 0 0 0-5 5L4 16l4 4 5.5-5.5a4 4 0 0 0 5-5l-2.5 2.5-2.5-.5-.5-2.5z"/></svg>
        <p class="phase">Build <span class="num" aria-hidden="true">5</span></p>
      </div>
      <h3 id="job-build">Build the fix</h3>
      <p class="promise">Turns confirmed bugs into tested pull requests.</p>
      <ul role="list">
        <li>Every fix ships with a regression test.</li>
        <li>Unblocks contributors' pull requests: rebases, failing tests, small fixes.</li>
        <li>Keeps the original author's credit.</li>
      </ul>
      <p class="call"><span>Your call:</span> the merge.</p>
      <p class="job-foot"><a href="docs/lifecycle/pr-lifecycle.md">Pull-request lifecycle</a></p>
    </li>

    <li class="job">
      <div class="job-head">
        <svg class="icon" viewBox="0 0 24 24" aria-hidden="true"><circle cx="6" cy="5" r="2"/><circle cx="6" cy="19" r="2"/><circle cx="18" cy="19" r="2"/><path d="M6 7v10M18 17v-7a3 3 0 0 0-3-3h-4"/><path d="M13 4.5L10.5 7 13 9.5"/></svg>
        <p class="phase">Check <span class="num" aria-hidden="true">6</span></p>
      </div>
      <h3 id="job-review">Review pull requests</h3>
      <p class="promise">Screens every pull request, and goes deep where it matters.</p>
      <ul role="list">
        <li>Checks fit and scope first.</li>
        <li>Reproduces the problem and tests against known bug patterns.</li>
        <li>Sends back precise, actionable fixes.</li>
      </ul>
      <p class="job-foot"><a href="docs/reference/bug-shapes.md">The bug-shape catalogue</a></p>
    </li>

    <li class="job">
      <div class="job-head">
        <svg class="icon" viewBox="0 0 24 24" aria-hidden="true"><path d="M12 3l7 3v5.5c0 4.2-2.9 7.6-7 9.5-4.1-1.9-7-5.3-7-9.5V6z"/><path d="M8.5 12l2.5 2.5 4.5-5"/></svg>
        <p class="phase">Check <span class="num" aria-hidden="true">7</span></p>
      </div>
      <h3 id="job-final-review">Final review before merge</h3>
      <p class="promise">A fresh, independent check right before anything merges.</p>
      <ul role="list">
        <li>The full test suite plus two independent reviews.</li>
        <li>Visual checks for UI changes.</li>
        <li>Every problem surfaced with its evidence.</li>
      </ul>
      <p class="job-foot"><a href="docs/lifecycle/quality-gates.md">Quality gates</a></p>
    </li>

    <li class="job">
      <div class="job-head">
        <svg class="icon" viewBox="0 0 24 24" aria-hidden="true"><path d="M3.5 12.5V4.5h8l9 9-8 8z"/><circle cx="8" cy="9" r="1.5"/></svg>
        <p class="phase">Ship <span class="num" aria-hidden="true">8</span></p>
      </div>
      <h3 id="job-release">Manage the release</h3>
      <p class="promise">Merge, tag, deploy, and confirm it's live.</p>
      <ul role="list">
        <li>Verifies the release is actually serving.</li>
        <li>Closes resolved issues and credits contributors.</li>
        <li>Drafts the release announcement.</li>
      </ul>
      <p class="call"><span>Your call:</span> shipping and announcing.</p>
      <p class="job-foot"><a href="docs/lifecycle/pr-lifecycle.md#5-merge--release">Merge and release</a></p>
    </li>
  </ol>
</section>

<section class="safety" aria-labelledby="how-it-stays-safe">
  <p class="eyebrow">How it stays safe</p>
  <h2 id="how-it-stays-safe">The agent prepares. You decide what can't be undone.</h2>
  <p class="jobs-lede">Reading is always safe. Routine, reversible work runs on its own. Anything that can't be undone waits for you.</p>
  <div class="ledger">
    <p class="caption">Three levels of autonomy</p>
    <dl class="bands">
      <div class="band-a-row"><dt><span class="mark">A</span><span>On its own</span></dt><dd>Small, reversible and checked afterwards: labels, logging new reports.</dd></div>
      <div class="band-b-row"><dt><span class="mark">B</span><span>With you in reach</span></dt><dd>Works the task and asks at real decisions: reviews, fixes, releases.</dd></div>
      <div class="band-c-row"><dt><span class="mark">C</span><span>You decide</span></dt><dd>The agent prepares, you act: public replies, judgment closes, announcements.</dd></div>
    </dl>
  </div>
  <p class="caption">Four roles, kept separate</p>
  <ol class="roles" role="list" aria-label="The four roles">
    <li><span class="n" aria-hidden="true">i.</span><span class="r">Watcher</span><span class="q">What’s coming in?</span></li>
    <li><span class="n" aria-hidden="true">ii.</span><span class="r">Reviewer</span><span class="q">Is this correct?</span></li>
    <li><span class="n" aria-hidden="true">iii.</span><span class="r">Builder</span><span class="q">Make the change.</span></li>
    <li><span class="n" aria-hidden="true">iv.</span><span class="r">Steward</span><span class="q">Keep the whole thing healthy.</span></li>
  </ol>
  <p class="safety-note">No change is cleared by whoever wrote it. <a href="docs/architecture/index.md">Read the architecture</a></p>
</section>

## What you install

Not an app: three things you add to the coding agent you already use.

- **Playbooks**: how issues, pull requests, quality gates and releases run, end to end.
- **Skills**: installable instructions your agent runs for each job.
- **A setup interview**: a few questions that wire Steward to your project.
{: .cards .cards-3 role="list" }

Start by reading, then hand over more as you build trust, from supervised sessions to a full
pipeline. See [adoption levels](docs/reference/adoption-levels.md).

## Find your way

- **[Quickstart](quickstart.md)**: adopt Steward on your repo in one sitting.
- **[Architecture](docs/architecture/)**: the four roles, the autonomy levels and the security spine.
- **[Lifecycle](docs/lifecycle/)**: end-to-end playbooks for issues, pull requests, quality gates and community.
- **[Playbooks](docs/playbooks/)**: cross-cutting recipes, from the autonomy ladder to the triage scoreboard.
- **[Reference](docs/reference/)**: coding principles, the bug-shape catalogue, reviewing at volume, the glossary and the FAQ.
- **[Setup](setup/setup-interview.md)**: the interview that wires Steward to your project.
{: .cards role="list" }

## Why "Steward"

A steward doesn't own what they tend. They care for it on the owner's behalf, with judgment and
restraint, and they know which decisions aren't theirs to make. That is the posture Steward encodes:
an agent that does the tireless work of maintenance and keeps a human at every irreversible edge.

## Status

In use and evolving. This repo runs on it: several agents build, review, gate and merge its
changes. [Steward on Steward](docs/reference/steward-on-steward.md) shows how.
