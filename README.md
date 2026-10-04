# DS57U Router Rebuild Manual

This repository documents rebuilding the Shuttle DS57U with OpenWrt and OCN
Virtual Connect, while keeping BUFFALO in router mode with its existing LAN.
The manuals describe policy, commands, expected results, acceptance checks,
and recovery. Dated execution evidence lives separately in
[docs/history/](docs/history/README.md).

## Reading and rebuild order

| Order | Manual | Purpose |
|---|---|---|
| 1 | [Project policy](router-project.md) | Architecture, topology, scope, and future work |
| 2 | [Phase 1](phase1-setup.md) | Install OpenWrt and verify LAN/WAN behind BUFFALO |
| 3 | [Storage expansion](storage-expansion.md) | Expand ext4 before installing the monitoring stack |
| 4 | [Phase 2](phase2-setup.md) | Prepare and verify direct-ONU IPv6 and MAP-E, with rollback |
| 5 | [BUFFALO replacement](phase2-router-mode-replacement.md) | Connect DS57U LAN to BUFFALO WAN and retain `192.168.11.0/24` |
| 6 | [Phase 3](phase3-monitoring.md) | Install local counters, router-agent, and Prometheus/Grafana |
| As needed | [Performance test plan](network-performance-test-plan.md) | Compare routes under matched conditions |

The Phase 3 monitoring components can also be prepared behind BUFFALO before
Phase 2. Use the checked-in scripts and configuration rather than copying
temporary commands from an old execution record. Reacquire addresses, prefixes,
disk identity, package availability, and backup hashes on every rebuild.
The image/version examples document the existing build; they are not a promise
that a later OpenWrt release has identical behavior.

## Verification limits

The latest recorded direct-ONU trial on 2026-10-04 passed native IPv6, DNS,
IPv4 HTTPS, and IPv4 ping with the guarded MAP-E automation. Reboot, physical
reconnect, new-prefix handling, return-to-BUFFALO cleanup, downstream BUFFALO
acceptance, and external verification of multiple allocated port ranges still
need their own checks. See the [Phase 2 history](docs/history/phase2-setup.md).
These are recorded limits, not results of a new live inspection.

## Documentation rules

- Keep decisions, repeatable procedures, expected-output examples, acceptance,
  and rollback in manuals. Label samples as examples; use placeholders for
  values that must be measured again.
- Keep dates, topology at execution time, commands in execution order, outputs,
  exit statuses, file/config diffs, artifacts and hashes, failures, corrections,
  retests, and actual checklist status in the corresponding history file.
- Do not remove failed attempts or promote planned checks to completed checks.
  Historical checklists remain snapshots of their original session.
- Keep backups, credentials, full packet captures, and large raw logs out of Git.
  History must contain the relevant redacted excerpt and the ignored artifact's
  path/hash when needed to support a conclusion.
- When an experiment changes the recommended procedure, update both the manual
  and its execution history. Keep documentation in English.
