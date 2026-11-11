# Contributing

This repository is a *system*, not an application — so contributions look a little different. The
most valuable contributions are **generalizations** (making a pattern work for more projects),
**new playbooks** (a lifecycle area we haven't covered), and **adaptations** (how you applied this
to your project, written up so others can learn).

## What makes a good contribution here

- **It stays project-agnostic.** Nothing in `docs/`, `skills/`, or `setup/` should hardcode a
  specific project's repos, names, paths, channels, or org details. The whole value is generality.
  If you're contributing a pattern you learned on your own project, *strip the specifics* and write
  it as the general case.
- **It respects the model.** New material should fit the [architecture](docs/architecture/index.md):
  name the role(s), state the band, and honor the security spine. If a contribution proposes
  autonomous public action without a watchdog, it'll be sent back.
- **It's honest about trade-offs.** This system is opinionated *because* the opinions are
  hard-won. If you disagree with one, make the case — but "here's a shortcut that skips a gate"
  needs to argue why the gate was wrong, not just that it's faster.

## How to contribute

1. **Open an issue first** for anything substantial — a new playbook, a model change. Small fixes
   (typos, clarifications, a missing link) can go straight to a PR.
2. **One concern per PR.** A doc fix, a new skill, a playbook addition — keep them separate.
3. **Match the voice.** Plain, direct, specific. Sentence-case headings. No filler. Explain *why*,
   not just *what*.
4. **Cross-link.** New docs link to the playbooks they relate to, and the related docs link back.
   Link a rule another doc already states rather than paraphrasing it: a paraphrase comes out
   narrower or broader than the rule, and drifts when the rule changes. A skill step still carries
   the clause it acts on, matching the source and linked to it; text a lint requires word for word
   (the injection guard) stays word for word.
5. **Keep the site buildable.** If you add a doc, add it to the [docs map](docs/README.md) and the
   site nav so it's discoverable.

## What we won't merge

- Anything that hardcodes a specific project's private details.
- Autonomous public-write capability without an [independent watchdog](docs/playbooks/watchdog-pattern.md).
- A "skip the gate to go faster" change that doesn't argue the gate was wrong.
- Vendor-specific lock-in where a generic pattern would do.

## Adaptations & case studies

Used this to run your project? A short write-up of *how* — what you configured, what you changed,
what you'd do differently — is genuinely valuable and welcome (in a `case-studies/` doc). Strip your
secrets and private specifics; share the pattern.

Thanks for helping make the system better for the next maintainer.
