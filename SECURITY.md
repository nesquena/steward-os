# Security policy

## Reporting a vulnerability

**Do not open a public issue for a security vulnerability.** Steward's own model treats a suspected
vulnerability as the one report that must never reach a public tracker — see
[the vulnerability divert](docs/reference/security-spine.md#6-the-vulnerability-divert).

Report privately via this repository's **[GitHub private security advisories](https://github.com/nesquena/steward-os/security/advisories/new)**.
Include what you observed, how to reproduce it, and the impact. You'll get an acknowledgement, and
disclosure is coordinated — a fix ships before any public write.

## Scope

This repository is a documentation and operating-model system, not a running service, so its own
attack surface is small. The most relevant "security" concern here is the **model itself**: if you
find a place where a playbook, skill, or config would lead an adopting agent to take an unsafe
autonomous action (a public write without a human or watchdog, a secret entering an agent's context,
untrusted input treated as instruction), that is in scope — report it the same private way.
