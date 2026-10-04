# Router-Agent Specification and Deployment Manual

Last updated: 2026-09-23  
Execution evidence: [router-agent validation history](../docs/history/router-agent.md).

## 1. Purpose

`router-agent` produces one JSON snapshot of local OpenWrt health and interface
counters. It is a Phase 3B component of the incremental monitoring plan; the
Phase 3A local-counter and `vnstat` rollout remains documented in
[`../phase3-monitoring.md`](../phase3-monitoring.md).

## 2. Scope and Security Boundary

The first slice is a one-shot Rust CLI at `router-agent/`; it is not a resident
service. It exposes no TCP/UDP/Unix listener, MCP interface, web API, UCI write,
ubus call, shell command, packet capture, or forwarding control.

Each invocation reads only these kernel-provided files:

- hostname and kernel release;
- `/proc/uptime`, `/proc/loadavg`, and `/proc/meminfo`;
- `/proc/sys/net/netfilter/nf_conntrack_count`;
- `/proc/net/fib_trie`;
- interface counters under `/sys/class/net/<name>/statistics/`.

It does not calculate throughput from a single snapshot, retain observations,
or associate local IPv4 addresses with interfaces.

## 3. JSON Contract

Schema version is `1`. Every result contains:

- `collected_at_unix`, `hostname`, and `kernel_release`;
- `uptime_seconds`, three `load_average` values, and total/available memory in
  KiB;
- `ipv4_local_addresses`, derived from `/proc/net/fib_trie`;
- `conntrack_entries`;
- requested interface names and these counters: `rx_bytes`, `tx_bytes`,
  `rx_packets`, `tx_packets`, `rx_errors`, `tx_errors`, `rx_dropped`, and
  `tx_dropped`.

Missing scalar kernel values are emitted as JSON `null`; they are never guessed.
The default interfaces are `br-lan` and `eth0`. Repeated `--interface NAME`
options replace the defaults. Names must match `[A-Za-z0-9_.-]+`, be no more
than 15 characters long, and therefore cannot traverse outside the selected
sysfs directory.

## 4. Build and Deployment

Build the static DS57U binary on the PC with the checked-in `rust-lld`
configuration:

```powershell
cd router-agent
cargo fmt --check
cargo test
cargo build --release --target x86_64-unknown-linux-musl
```

Before deployment, create a fresh `sysupgrade` backup and match the router and
PC SHA-256 values. Copy the binary to `/tmp/router-agent`, verify its SHA-256
against the PC artifact, then copy it to `/usr/sbin/router-agent` with mode
`0755`. Do not create an init script or enable a service.

Rollback is removal of `/usr/sbin/router-agent`; the CLI has no configuration,
database, open port, or running process to clean up. The verified pre-deployment
backup remains the recovery artifact.

Verify a default and explicit-interface invocation on the router, and use
`jsonfilter` where available to check `schema_version=1`. Capture `ss -lnt` or
an equivalent listener listing before and after deployment to demonstrate that
no network endpoint was added. A source build and hash check do not replace
router runtime validation.

Record runtime validation in [router-agent history](../docs/history/router-agent.md); use a fresh checklist for each deployment.
