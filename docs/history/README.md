# Execution History

These records support the [rebuild manuals](../../README.md). They retain
dated commands, outputs, failures, corrections, retests, backup/log hashes,
and rollback results. Original section numbers and historical wording are
preserved where practical. A statement such as "current", "pending", or
"completed" inside a record refers to that session, not today's router state.
Unrun diagnostic and rollback plans inside a record remain unrun.

| Record | Manual |
|---|---|
| [Project baseline](project-baseline.md) | [Policy](../../router-project.md) |
| [Phase 1](phase1-setup.md) | [Basic setup](../../phase1-setup.md) |
| [Storage](storage-expansion.md) | [Expansion](../../storage-expansion.md) |
| [Phase 2](phase2-setup.md) | [Direct-ONU / MAP-E](../../phase2-setup.md) |
| [BUFFALO replacement](phase2-router-mode-replacement.md) | [Replacement](../../phase2-router-mode-replacement.md) |
| [Phase 3A/3B](phase3-monitoring.md) | [Monitoring](../../phase3-monitoring.md) |
| [Router-agent](router-agent.md) | [Canonical specification](../../router-agent/SPEC.md) |
| [Phase 3C](phase3c-monitoring.md) | [Monitoring](../../phase3-monitoring.md) |
| [LAN cable comparison](lan-cable-comparison.md) | [Performance testing](../../network-performance-test-plan.md) |
| [Internet performance](network-performance.md) | [Performance testing](../../network-performance-test-plan.md) |

Append new runs to the appropriate file with this structure:

```text
### YYYY-MM-DD JST - Action (executed / read-only / planned)
Topology and cable state:
Baseline and backup path/hash:
Commands in execution order:
Relevant redacted output and each available exit status:
Configuration contents or diff:
Failures, corrections, and retest results:
Verdict and unverified checks:
Rollback performed and result, or rollback not run:
Ignored raw-log path and SHA-256 when output is too large:
```

## 2026-10-04 - Documentation separation

This was a local documentation edit. No router command, setting change,
service restart, reboot, or cable move was performed. Execution blocks were
moved from the manuals with their contents preserved except for relative
Markdown link relocation. The Phase 3C procedure was rewritten around the
checked-in configuration and the successful recorded corrections. Local
checks covered evidence preservation, Markdown links/anchors, code-fence
balance, and `git diff --check`; this does not revalidate router runtime.

Local verification commands and results (exit `0`):

```text
rtk proxy powershell -NoProfile -File tools/doc-refactor.ps1 evidence
PASS: 25 original evidence blocks preserved across 9 histories (only Markdown link rebasing allowed)

rtk proxy powershell -NoProfile -File tools/doc-refactor.ps1 validate
PASS: 25 Markdown files; local links/anchors and code-fence balance

rtk git diff --check
No whitespace errors (Git emitted only LF-to-CRLF conversion warnings).
```

`doc-refactor.ps1` was a temporary local extraction/check helper and was
removed after verification; it is not a router setup dependency.
