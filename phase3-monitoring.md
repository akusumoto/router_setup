# Phase 3 — Incremental Monitoring

Last updated: 2026-09-23  
Status: **Phase 3A and the bounded Phase 3B CLI implementation completed on 2026-09-23 JST. `vnstat` is enabled locally; the deployed Rust router-agent is a one-shot JSON CLI with no listener or service.**

## 1. Objective and Boundary

Add monitoring in small, reversible slices while preserving the existing DS57U routing path. The current topology remains `ONU -> BUFFALO -> DS57U eth0`, with the test PC attached through the white `eth1` LAN cable. Phase 2 direct-ONU/MAP-E testing remains incomplete and is not implied by this work.

| Slice | Scope | Completion condition | State |
|---|---|---|---|
| 3A | Local connection and traffic counters | Current conntrack/interface/resource baseline is recorded; `vnstat` is installed and its local database/service are verified | Implemented; history accumulating |
| 3B | Router-agent | A separately reviewed agent exposes bounded local measurements without changing forwarding | Implemented as a one-shot local CLI |
| 3C | Metrics export and visualization | Prometheus-compatible endpoint and Grafana use are separately sized, secured, and verified | Not started |
| 3D | Flow analysis | ntopng or an alternative is selected only after resource and privacy review | Not started |

Do not install Grafana, Prometheus, ntopng, or a custom router-agent as part of 3A. They have materially different storage, CPU, network exposure, and data-retention consequences.

## 2. Phase 3A Design

`conntrack` is already installed from Phase 1 and provides current flow counts. `vnstat` is proposed as the first persistent traffic counter because it uses local interface byte counters and a small local database. Its counters are historical observations, not packet captures or per-flow logs.

Expected monitored data:

- conntrack entry count, router load, memory, and per-interface packet/error/drop counters (read-only snapshots);
- cumulative interface traffic retained by `vnstat` locally on the router.

Not collected in 3A: packet payloads, DNS queries, client identities, remote metrics, or any listening service exposed outside the router.

## 3. Preconditions and Rollback

Before installing a package, use the existing PC-to-router management path and one persistent SSH session. Confirm free space and produce a new `sysupgrade` backup; copy it with `scp -O` and match SHA-256 on the PC. Do not run `apk upgrade`.

If `vnstat` is not available, dependencies cannot be resolved, or the post-install free-space margin is unsuitable, stop without configuration changes. If it is installed but must be removed, retain the pre-change backup and use the package manager's normal removal command only after recording the database/service state. Package removal and restoring configuration are separate actions; neither is required merely to stop the daemon.

## 4. Execution Procedure

### 4.1 Read-only baseline

Run in this order and record the relevant redacted excerpt and exit status:

```sh
date -Iseconds
df -h /
command -v conntrack
apk info -e conntrack
apk info -e vnstat
conntrack -C
uptime
free
ip -s link show dev eth0
ip -s link show dev eth1
```

`apk info -e vnstat` exiting `1` means it is not yet installed; that is expected at this stage. The command must not be treated as an error in the baseline verdict.

### 4.2 Backup and package availability

Only after 4.1 is logged:

```sh
umask 077
sysupgrade -b /tmp/phase3-before-vnstat.tar.gz
sha256sum /tmp/phase3-before-vnstat.tar.gz
apk update
apk search vnstat
apk info vnstat
```

Copy the backup to the PC using `scp -O`, calculate its SHA-256 with `certutil -hashfile`, and require an exact match before `apk add vnstat`.

### 4.3 Install and verify vnStat

After the hash matches:

```sh
apk add vnstat
apk info -e vnstat
command -v vnstat
/etc/init.d/vnstat enabled; echo ENABLED_EXIT=$?
/etc/init.d/vnstat status; echo STATUS_EXIT=$?
vnstat --iflist
vnstat --oneline
df -h /
```

If the package's init script requires explicit enable/start on this OpenWrt build, record that fact and seek a separate decision before enabling it. Do not infer service behavior from package installation alone.

### 4.4 Post-install observation

Wait for normal traffic on the unchanged topology, then run `vnstat --oneline`, `conntrack -C`, `uptime`, and `ip -s link show dev eth0`/`eth1` again. Compare counter movement and resource state only; no throughput conclusion follows from these snapshots.

## 5. Execution Log

### 2026-09-23 — Phase 3A implementation (executed)

Topology remained unchanged: `ONU -> BUFFALO -> DS57U eth0`; the management/test PC was connected through the white `eth1` LAN cable. The router reported `2026-09-22T16:23:14+00:00` at the baseline (2026-09-23 JST). Phase 2 direct-ONU/MAP-E testing was not performed.

The following commands ran in one persistent SSH session, in this order. All listed commands exited `0` unless an explicit result is shown. No router network or firewall configuration was changed.

```sh
date -Iseconds
df -h /
command -v conntrack; echo CONNTRACK_PATH_EXIT=$?
apk info -e conntrack; echo CONNTRACK_PACKAGE_EXIT=$?
apk info -e vnstat; echo VNSTAT_PACKAGE_EXIT=$?
conntrack -C; echo CONNTRACK_COUNT_EXIT=$?
uptime
free
ip -s link show dev eth0
ip -s link show dev eth1
for d in eth0 eth1; do echo "[$d]"; for f in rx_bytes tx_bytes rx_packets tx_packets rx_errors tx_errors rx_dropped tx_dropped; do printf '%s=' "$f"; cat "/sys/class/net/$d/statistics/$f"; done; done
umask 077
sysupgrade -b /tmp/phase3-before-vnstat.tar.gz; echo BACKUP_EXIT=$?
sha256sum /tmp/phase3-before-vnstat.tar.gz
apk update; echo APK_UPDATE_EXIT=$?
apk search vnstat; echo APK_SEARCH_EXIT=$?
apk info vnstat; echo APK_INFO_EXIT=$?
apk add vnstat; echo APK_ADD_EXIT=$?
apk info -e vnstat; echo VNSTAT_PACKAGE_EXIT=$?
command -v vnstat; echo VNSTAT_PATH_EXIT=$?
ls -l /etc/init.d/vnstat /etc/config/vnstat
/etc/init.d/vnstat enabled; echo ENABLED_EXIT=$?
/etc/init.d/vnstat status; echo STATUS_EXIT=$?
vnstat --iflist; echo IFLIST_EXIT=$?
vnstat --oneline; echo ONELINE_EXIT=$?
df -h /
cat /etc/config/vnstat
ps w | grep '[v]nstat'
logread -e vnstat
ls -la /var/lib/vnstat /etc/vnstat.conf
sleep 20
vnstat --oneline; echo ONELINE_RECHECK_EXIT=$?
conntrack -C; echo CONNTRACK_RECHECK_EXIT=$?
uptime
for d in eth0 eth1; do echo "[$d]"; for f in rx_bytes tx_bytes rx_packets tx_packets rx_errors tx_errors rx_dropped tx_dropped; do printf '%s=' "$f"; cat "/sys/class/net/$d/statistics/$f"; done; done
df -h /
```

`ip -s link` failed because this BusyBox `ip` implementation does not support `-s`; its usage text was returned. This was corrected in the same session by reading the eight supported counters under `/sys/class/net/<interface>/statistics/`. That correction is the supported Phase 3A counter method for this router.

Baseline evidence: root had `71.5M` free (26% used); `conntrack` was `/usr/sbin/conntrack` and installed; `vnstat` was absent (`VNSTAT_PACKAGE_EXIT=1`); count was `42`; load average was `0.00, 0.00, 0.00`; memory available was `7902656 KiB`. Initial counters were `eth0` RX/TX `725584072`/`344441202` bytes and `eth1` RX/TX `350130935`/`718316389` bytes. Both interfaces had zero RX/TX errors; `eth0` had four TX drops and `eth1` had none.

The router backup succeeded (`BACKUP_EXIT=0`) with SHA-256 `f8ecb21c5bca456338cfe6f157183373964ed6782cc4e33141021030778b61c1`. It was copied before installation with:

```powershell
scp -O -i .local-ssh/id_ed25519_v2 -o IdentitiesOnly=yes -o BatchMode=yes root@192.168.1.1:/tmp/phase3-before-vnstat.tar.gz backups/
certutil -hashfile backups\phase3-before-vnstat.tar.gz SHA256
```

`certutil` produced the same SHA-256. `backups/phase3-before-vnstat.tar.gz` is ignored because it can contain credentials.

`apk update` completed with `11238 distinct packages available`. The available base package was `vnstat-1.18-r3`, with installed size `172 KiB`. `apk add vnstat` completed with `APK_ADD_EXIT=0` and left `71.3M` free (26% used). Its post-install hook emitted `can't open '/etc/uci-defaults/vnstat': No such file or directory`, but the resulting installed package, configuration, service, daemon, and databases all verified successfully; this warning is recorded as an observed package-hook anomaly, not ignored.

Post-install evidence:

```text
/usr/bin/vnstat
ENABLED_EXIT=0
running
STATUS_EXIT=0
config vnstat
        list interface 'br-lan'
        list interface 'eth0'
Info: vnStat daemon 1.18 started.
Info: Monitoring: br-lan (1000 Mbit) eth0 (1000 Mbit)
/var/lib/vnstat/br-lan  2792 bytes
/var/lib/vnstat/eth0    2792 bytes
```

`vnstat --oneline` returned `eth0: Not enough data available yet.` immediately after installation and after 20 seconds, with exit status `0`; this is expected for a newly created historical database and is not a traffic failure. During the 20-second observation, the raw counters advanced to `eth0` RX/TX `727709529`/`344518286` bytes and `eth1` RX/TX `350216337`/`718643718` bytes. Error/drop counts were unchanged; conntrack moved from `42` to `40`; load average remained `0.00, 0.00, 0.00`.

| Check | Observation | Exit status | Verdict |
|---|---|---:|---|
| 4.1 baseline | `conntrack` present; 42 entries; 71.5 MiB free; no interface errors | 0, except expected absent-vnstat result 1 | Pass |
| 4.2 backup and availability | Router/PC SHA-256 match; package found | 0 | Pass |
| 4.3 installation/service state | `vnstat-1.18-r3`; enabled/running; databases created | 0 | Pass, post-install warning recorded |
| 4.4 counter movement | Raw counters advanced without error/drop change; history not yet sufficient | 0 | Pass for live counters; historical report pending collection |

## 6. Checklist

- [x] Recorded read-only conntrack, resource, and interface-counter baseline
- [x] Created Phase 3 pre-change backup and verified its PC copy hash
- [x] Confirmed `vnstat` package availability and size
- [x] Installed and verified `vnstat`
- [x] Confirmed it is enabled/running; no manual service-state change was made
- [x] Recorded post-install counter movement and free space
- [x] Preserved Phase 2 as pending direct-ONU/MAP-E validation

## 7. Phase 3B — Read-only Rust Router-Agent

The canonical router-agent specification, deployment/rollback procedure, and
Phase 3B validation record now live in
[`router-agent/SPEC.md`](router-agent/SPEC.md). The retained material below is
the original in-plan execution record; keep future router-agent specification
changes in `router-agent/SPEC.md`.

### 7.1 Scope and Security Boundary

The first router-agent slice is a one-shot Rust CLI at `router-agent/`; it is not
a resident service. It exposes no TCP/UDP/Unix listener, MCP interface, web API,
UCI write, ubus call, shell command, packet capture, or forwarding control.
Each invocation reads only these kernel-provided files: hostname/kernel release,
`/proc/uptime`, `/proc/loadavg`, `/proc/meminfo`,
`/proc/sys/net/netfilter/nf_conntrack_count`, `/proc/net/fib_trie`, and interface
counters under `/sys/class/net/<name>/statistics/`.

The JSON schema version is `1`. It includes timestamp, system resource values,
local IPv4 addresses, conntrack count, and the eight byte/packet/error/drop
fields for requested interfaces. The default interfaces are `eth0` and `br-lan`. An optional repeated
`--interface NAME` accepts only `[A-Za-z0-9_.-]+` names up to 15 characters,
preventing path traversal outside the selected sysfs directory. Missing kernel
values are emitted as `null`, never guessed.

### 7.2 Build, Deployment, and Recovery

Build the static DS57U binary on the PC with Rust target
`x86_64-unknown-linux-musl` and the checked-in `rust-lld` configuration:

```powershell
cd router-agent
cargo fmt --check
cargo test
cargo build --release --target x86_64-unknown-linux-musl
```

Before deployment, make a new `sysupgrade` backup and match its router/PC
SHA-256. Copy the binary to `/tmp/router-agent`, verify its SHA-256 against the
PC artifact, then copy it to `/usr/sbin/router-agent` with mode `0755`. Do not
create an init script or enable a service in this slice. Rollback of the agent
deployment is simply removing `/usr/sbin/router-agent`; it has no configuration,
database, open port, or running process to clean up. The verified pre-deployment
backup remains the recovery artifact.

Verify on the router with a default and explicit-interface invocation, capture
their JSON, and use `jsonfilter` when available to check `schema_version=1`.
Record `ss -lnt` before/after or an equivalent listener listing to demonstrate
that no network endpoint was added. A source build and hash check do not prove
the router runtime; both are required.

### 7.3 Execution Log

#### 2026-09-23 — Implementation, deployment, and validation (executed)

Created `router-agent/` with no third-party dependencies. The agent does not
spawn a subprocess. `cargo fmt --check` initially reported only formatting
differences; `cargo fmt` corrected them, then `cargo fmt --check` and `cargo
test` passed. Both unit tests passed: JSON escaping and unsafe interface-name
rejection. The Windows host initially lacked the musl standard-library target;
after installing `x86_64-unknown-linux-musl`, the first release build failed
because linker `cc` was unavailable. Adding `.cargo/config.toml` to use
`rust-lld` with `link-self-contained=yes` corrected the build. The final static
Linux artifact is `target/x86_64-unknown-linux-musl/release/router-agent`,
`669648` bytes.

The router was inspected in a persistent SSH session at
`2026-09-22T16:46:57+00:00` (2026-09-23 JST), with the normal
`ONU -> BUFFALO -> DS57U eth0` topology unchanged. Root free space was
`117.7G`; `ss` was unavailable, so `netstat -lnt` and `/proc/net/tcp*` were used
as the supported listener observations. A fresh pre-deployment backup was made:

```sh
umask 077
sysupgrade -b /tmp/phase3b-before-agent.tar.gz; echo BACKUP_EXIT=$?
sha256sum /tmp/phase3b-before-agent.tar.gz
```

`BACKUP_EXIT=0`; the router SHA-256 was
`19471d481eb22157921c47875ef3cd4d4e330bcd84a2f8219863f06a16f1a573`. It was copied
to ignored `backups/phase3b-before-agent.tar.gz` with `scp -O`, and `certutil`
reported the same hash.

The PC release binary SHA-256 was
`c3c7bf1fb70bb5f2cc47b7a3276aa2b9434de6f7605bbe18dcb2092f81ac4524`. It was copied
to `/tmp/router-agent`; its router SHA-256 matched. Its default `scp` mode was
`0644`, so the initial direct `/tmp/router-agent` execution failed with
`Permission denied` and exit `126`. This was expected from the copied mode, but
is recorded as a failed pre-install attempt; it was not used as runtime proof.

The following deliberate deployment commands then succeeded:

```sh
cp /tmp/router-agent /usr/sbin/router-agent; echo COPY_EXIT=$?
chmod 0755 /usr/sbin/router-agent; echo CHMOD_EXIT=$?
sha256sum /usr/sbin/router-agent
/usr/sbin/router-agent --interface eth0 --interface br-lan > /tmp/router-agent.deployed.json; echo DEPLOYED_RUN_EXIT=$?
jsonfilter -i /tmp/router-agent.deployed.json -e '@.schema_version'; echo DEPLOYED_JSONFILTER_EXIT=$?
```

Both copy and mode changes exited `0`; the installed binary hash matched the PC
artifact. The explicit-interface invocation exited `0`, and `jsonfilter`
returned schema version `1` with exit `0`. Its observed JSON included hostname
`OpenWrt`, kernel `6.12.94`, `conntrack_entries: 41`, zero load averages, and
`br-lan`/`eth0` counters. Values are point-in-time observations only, not
throughput measurements.

The default invocation also exited `0`; `jsonfilter` confirmed ordered defaults
`br-lan` then `eth0`. An explicit traversal attempt
`--interface '../../etc/passwd'` exited `2` with
`router-agent: invalid interface name: ../../etc/passwd`.

`netstat -lnt` before and after deployment showed only the pre-existing HTTP,
HTTPS, SSH, and DNS listeners. There is no `/etc/init.d/router-agent`, `ps w |
grep '[r]outer-agent'` returned no process after each one-shot run, and `uci
changes` produced no output. Therefore Phase 3B adds no resident process,
listener, or UCI change.

#### 2026-09-23 — Local IPv4 address query (executed)

The initial 3B schema did not include an address field, so it could not satisfy
an address query. The agent was extended without changing its no-subprocess,
no-listener boundary: it parses only `/proc/net/fib_trie` and emits
`ipv4_local_addresses`. A unit-test fixture covers duplicate local records,
broadcast records, malformed text, and the special non-host `127.0.0.0` routing
trie entry. The latter initially appeared in live output; it was then filtered
before the corrected binary was accepted.

After the correction, `cargo fmt --check`, `cargo test` (three tests), and the
static musl release build passed. The final PC/router binary SHA-256 matched:
`2f5c17f2f73e569669de0b0ad15a0d246907fa3da3d9e482a540ffffb40386bf`.

```sh
/usr/sbin/router-agent > /tmp/router-agent.addresses-v3.json; echo AGENT_EXIT=$?
jsonfilter -i /tmp/router-agent.addresses-v3.json -e '@.ipv4_local_addresses[*]'; echo ADDRESSES_EXIT=$?
```

Both commands exited `0`. The final agent-sourced values were:

```text
127.0.0.1
192.168.1.1
192.168.11.108
```

`192.168.1.1` is the DS57U LAN address and `192.168.11.108` is its current
BUFFALO-side WAN address. `uci changes` remained empty. These values are a
point-in-time read; the agent intentionally does not yet associate IPv4 entries
with interfaces in its schema.

### 7.4 Phase 3B Checklist

- [x] Implemented a dependency-free Rust one-shot agent and unit-tested JSON escaping/interface validation
- [x] Built a static OpenWrt x86_64 binary and matched PC/router deployment hashes
- [x] Created and hash-verified a fresh pre-deployment router backup
- [x] Validated default and explicit-interface JSON snapshots on the router
- [x] Confirmed rejection of an unsafe interface name
- [x] Confirmed no service, running agent process, listener, or UCI change
- [x] Kept Phase 2 direct-ONU/MAP-E work pending
