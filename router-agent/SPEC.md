# Router-Agent Specification and Validation Record

Last updated: 2026-09-23  
Status: **Implemented and deployed as the bounded Phase 3B one-shot CLI.**

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

## 5. Observed Implementation and Validation

### 2026-09-23 — Implementation, deployment, and validation

The dependency-free agent was created with no subprocess execution. `cargo fmt
--check` initially reported formatting differences; `cargo fmt` corrected them.
`cargo fmt --check` and `cargo test` then passed. The two initial unit tests
covered JSON escaping and unsafe-interface rejection.

The Windows host initially lacked the musl standard-library target. After it was
installed, the first release build failed because linker `cc` was unavailable.
The checked-in `.cargo/config.toml` setting (`rust-lld` with
`link-self-contained=yes`) corrected the build. The resulting static Linux
artifact was `target/x86_64-unknown-linux-musl/release/router-agent`, `669648`
bytes.

The router was inspected in one persistent SSH session at
`2026-09-22T16:46:57+00:00` (2026-09-23 JST), with the normal topology unchanged:
`ONU -> BUFFALO -> DS57U eth0`, and the management/test PC on the white `eth1`
LAN cable. Root free space was `117.7G`. `ss` was unavailable, so `netstat -lnt`
and `/proc/net/tcp*` were the listener observations.

A fresh pre-deployment backup completed successfully:

```sh
umask 077
sysupgrade -b /tmp/phase3b-before-agent.tar.gz; echo BACKUP_EXIT=$?
sha256sum /tmp/phase3b-before-agent.tar.gz
```

`BACKUP_EXIT=0`; the router SHA-256 was
`19471d481eb22157921c47875ef3cd4d4e330bcd84a2f8219863f06a16f1a573`.
The ignored PC copy at `backups/phase3b-before-agent.tar.gz`, made with `scp -O`,
had the same hash.

The PC release binary SHA-256 was
`c3c7bf1fb70bb5f2cc47b7a3276aa2b9434de6f7605bbe18dcb2092f81ac4524`.
After copying to `/tmp/router-agent`, its router SHA-256 matched. The initial
direct execution failed with `Permission denied` and exit `126` because `scp`
had assigned mode `0644`; it was recorded but not treated as runtime proof.

The deliberate deployment then succeeded:

```sh
cp /tmp/router-agent /usr/sbin/router-agent; echo COPY_EXIT=$?
chmod 0755 /usr/sbin/router-agent; echo CHMOD_EXIT=$?
sha256sum /usr/sbin/router-agent
/usr/sbin/router-agent --interface eth0 --interface br-lan > /tmp/router-agent.deployed.json; echo DEPLOYED_RUN_EXIT=$?
jsonfilter -i /tmp/router-agent.deployed.json -e '@.schema_version'; echo DEPLOYED_JSONFILTER_EXIT=$?
```

Both copy and mode changes exited `0`; the installed hash matched the PC
artifact. The explicit-interface invocation and `jsonfilter` schema check both
exited `0`. The snapshot included hostname `OpenWrt`, kernel `6.12.94`,
`conntrack_entries: 41`, zero load averages, and `br-lan`/`eth0` counters.
Those are point-in-time observations, not throughput measurements.

The default invocation exited `0` and returned ordered defaults `br-lan`, then
`eth0`. An explicit traversal attempt, `--interface '../../etc/passwd'`, exited
`2` with `router-agent: invalid interface name: ../../etc/passwd`.

`netstat -lnt` before and after deployment showed only pre-existing HTTP, HTTPS,
SSH, and DNS listeners. No `/etc/init.d/router-agent` exists, `ps w | grep
'[r]outer-agent'` returned no process after each one-shot invocation, and `uci
changes` was empty. Thus the deployment added no resident process, listener, or
UCI change.

### 2026-09-23 — Local IPv4 address query

The initial schema had no address field. The agent was extended within the same
no-subprocess, no-listener boundary: it parses only `/proc/net/fib_trie` and
emits `ipv4_local_addresses`. A unit-test fixture covers duplicate local
records, broadcast records, malformed text, and the special non-host
`127.0.0.0` routing-trie entry. The latter initially appeared in live output,
then was filtered before the corrected binary was accepted.

After the correction, `cargo fmt --check`, `cargo test` (three tests), and the
static musl release build passed. The final PC/router binary SHA-256 matched:
`2f5c17f2f73e569669de0b0ad15a0d246907fa3da3d9e482a540ffffb40386bf`.

```sh
/usr/sbin/router-agent > /tmp/router-agent.addresses-v3.json; echo AGENT_EXIT=$?
jsonfilter -i /tmp/router-agent.addresses-v3.json -e '@.ipv4_local_addresses[*]'; echo ADDRESSES_EXIT=$?
```

Both commands exited `0`. The agent-sourced point-in-time values were
`127.0.0.1`, `192.168.1.1`, and `192.168.11.108`. The latter two are the DS57U
LAN address and its then-current BUFFALO-side WAN address; `uci changes`
remained empty.

## 6. Checklist

- [x] Implemented a dependency-free one-shot agent and unit-tested JSON escaping/interface validation
- [x] Built a static OpenWrt x86_64 binary and matched PC/router deployment hashes
- [x] Created and hash-verified a fresh pre-deployment router backup
- [x] Validated default and explicit-interface JSON snapshots on the router
- [x] Confirmed rejection of an unsafe interface name
- [x] Confirmed no service, running process, listener, or UCI change
- [x] Added and validated local IPv4 address output without broadening the read-only boundary
