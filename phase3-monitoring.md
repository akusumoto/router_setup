# Phase 3 — Incremental Monitoring

Last updated: 2026-09-26
Status: **Phase 3A and the bounded Phase 3B CLI implementation completed on 2026-09-23 JST. `vnstat` is enabled locally; the deployed Rust router-agent is a one-shot JSON CLI with no listener or service.**

## 1. Objective and Boundary

Add monitoring in small, reversible slices while preserving the existing DS57U routing path. The current topology remains `ONU -> BUFFALO -> DS57U eth0`, with the test PC attached through the white `eth1` LAN cable. Phase 2 direct-ONU/MAP-E testing remains incomplete and is not implied by this work.

| Slice | Scope | Completion condition | State |
|---|---|---|---|
| 3A | Local connection and traffic counters | Current conntrack/interface/resource baseline is recorded; `vnstat` is installed and its local database/service are verified | Implemented; history accumulating |
| 3B | Router-agent | A separately reviewed agent exposes bounded local measurements without changing forwarding | Implemented as a one-shot local CLI |
| 3C | Metrics export and visualization | Prometheus-compatible endpoint and Grafana use are separately sized, secured, and verified | In progress; loopback exporter verified, Prometheus/Grafana blocked by Docker runtime |
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

## 8. Phase 3C — Metrics Export and Visualization

### 8.1 Selected deployment and migration boundary

Phase 3C is separate from the one-shot Phase 3B CLI because it introduces a
long-running metrics endpoint and a metrics store/dashboard. The initial
assessment proposed an exporter bound only to router loopback, an SSH
local-forward from the management PC, and Prometheus plus Grafana on that PC.
A LAN-bound exporter is a different security decision because the current LAN
firewall zone accepts input from every LAN client.

On 2026-09-24 JST, the operator selected an interim router-local deployment:
the OpenWrt exporter, Prometheus, and Grafana run on the DS57U. The exposure
constraint remains loopback-only: exporter `127.0.0.1:9100`, Prometheus
`127.0.0.1:9090`, and Grafana `127.0.0.1:3000`. Browser access, when Grafana
is running, is through an SSH local forward rather than a LAN/WAN firewall
opening. Grafana's administrator password is generated on the router in a
root-only file and is never committed or copied to project documentation.

The intended migration boundary is version-controlled configuration under
`phase3c/` (deployed to `/etc/phase3c`) plus persistent Prometheus/Grafana data
under `/opt/phase3c`. A future server/AWS move must export/copy those two
paths, provision a new Grafana admin credential, bring up the new stack, verify
the new scrape/dashboard, then stop the router-local stack. Docker image cache
under `/opt/docker` is disposable and is not migration data.

### 8.2 Read-only sizing and exposure assessment

#### 2026-09-23 — Assessment (executed; no router change)

Topology remained `ONU -> BUFFALO -> DS57U eth0`; management remained via the
white `eth1` LAN cable. A persistent interactive SSH attempt connected, but the
local execution wrapper did not retain its session handle. The following
read-only SSH invocations were therefore made separately; no UCI, package, or
service state was modified:

```text
ssh -i .local-ssh\id_ed25519_v2 -o BatchMode=yes root@192.168.1.1 "date '+%F %T %Z'; df -h /overlay; free; uci show firewall; netstat -lnt; apk search prometheus; apk search collectd; apk info vnstat; /etc/init.d/vnstat status"
```

Relevant observations: at `2026-09-23 14:30:16 GMT`, `/dev/root` had `117.7G`
free of `117.7G`; memory had `7904744 KiB` available and no swap. Firewall
defaults were input `REJECT`, forward `REJECT`; the `lan` zone input was
`ACCEPT`, and the `wan` zone input was `REJECT`. Existing TCP listeners were
HTTP `80`, HTTPS `443`, SSH `22`, and DNS `53`; no metrics listener was
observed. `vnstat` was still `running`.

Exporter discovery did not yield a candidate, because every configured OpenWrt
repository reported `WARNING: opening from cache ... packages.adb: No such file
or directory`. This is an incomplete local APK metadata cache, not evidence
that a Prometheus exporter is unavailable upstream. No `apk update` was run,
so the assessment has zero package/configuration writes. Exit status was `0`
for the sizing/firewall/listener query; `apk search` emitted the described
cache warnings.

#### 2026-09-24 JST — Router-local installation and blocked container startup (executed)

The topology remained `ONU -> BUFFALO -> DS57U eth0`, with management through
the white `eth1` LAN cable. Before the change, a fresh recovery artifact was
created and copied with `scp -O` to ignored
`backups/phase3c-before-prometheus-grafana.tar.gz`. The router and PC SHA-256
both were `19471d481eb22157921c47875ef3cd4d4e330bcd84a2f8219863f06a16f1a573`.
The remote status text was malformed by the local PowerShell wrapper's
expansion of `$?`, but `sysupgrade -b` completed, produced the archive, and
the `scp`/`certutil` hash match is the retained success evidence.

Commands were issued in this order (the private-key path is project-local):

```text
ssh -i .local-ssh\id_ed25519_v2 -o BatchMode=yes root@192.168.1.1 "umask 077; sysupgrade -b /tmp/phase3c-before-prometheus-grafana.tar.gz; printf 'BACKUP_EXIT=%s\n' $?; sha256sum /tmp/phase3c-before-prometheus-grafana.tar.gz"
scp -O -i .local-ssh\id_ed25519_v2 -o BatchMode=yes root@192.168.1.1:/tmp/phase3c-before-prometheus-grafana.tar.gz backups/phase3c-before-prometheus-grafana.tar.gz
certutil -hashfile backups\phase3c-before-prometheus-grafana.tar.gz SHA256
ssh -i .local-ssh\id_ed25519_v2 -o BatchMode=yes root@192.168.1.1 "apk update"
ssh -i .local-ssh\id_ed25519_v2 -o BatchMode=yes root@192.168.1.1 "apk add --simulate dockerd docker docker-compose prometheus-node-exporter-lua prometheus-node-exporter-lua-openwrt"
ssh -i .local-ssh\id_ed25519_v2 -o BatchMode=yes root@192.168.1.1 "apk add dockerd docker docker-compose prometheus-node-exporter-lua prometheus-node-exporter-lua-openwrt"
```

`apk update` completed with `OK: 11234 distinct packages available`. The exact
install was simulated first, then executed:

```sh
apk add --simulate dockerd docker docker-compose prometheus-node-exporter-lua prometheus-node-exporter-lua-openwrt
apk add dockerd docker docker-compose prometheus-node-exporter-lua prometheus-node-exporter-lua-openwrt
```

The simulation selected 48 packages and reported `OK: 273.0 MiB in 259
packages`, including `dockerd-29.6.1-r1`, `docker-29.6.1-r1`,
`docker-compose-5.1.4-r1`, `prometheus-node-exporter-lua-2026.06.05-r1`, and
`prometheus-node-exporter-lua-openwrt-2026.06.05-r1`. Post-install root use was
`2.9G`, leaving `114.8G`; the Grafana image cache is large (about `1.39GB` on
disk). Docker is a material networking change: its init log recorded
`Drop traffic from eth0 to docker0`. No external port was published by Phase
3C.

The exporter package's default configuration was retained:

```text
config prometheus-node-exporter-lua 'main'
    option listen_interface 'loopback'
    option listen_port '9100'
```

Its service was `running`; `netstat -lnt` showed only
`127.0.0.1:9100`, and a local metrics read returned `node_load1`,
`node_memory_MemAvailable_bytes`, and byte counters for `eth0`/`br-lan`.
This verifies the Prometheus-compatible endpoint and its no-LAN/no-WAN bind.

The checked-in `phase3c/compose.yml` pins `prom/prometheus:v3.14.0` and
`grafana/grafana:13.2.1`, uses host networking solely to let both containers
reach loopback services, binds Prometheus/Grafana themselves to loopback, and
sets Prometheus retention to 15 days and 2 GiB. `phase3c/prometheus.yml`
scrapes only `127.0.0.1:9100` every 30 seconds. Grafana provisioning adds that
data source and an `OpenWrt Overview` dashboard with load, available-memory,
and `eth0`/`br-lan` traffic panels. `docker compose ... config --quiet` exited
0 without rendering the secret.

#### 8.1.1 Current Prometheus collection and Grafana visualization inventory

The standalone [Phase 3C monitoring and visualization inventory](phase3c/monitoring-inventory.md)
defines the collected metrics, scrape/retention limits, and current Grafana
panels.

Two setup corrections are retained as failures rather than silently omitted.
The first random-secret command tried `base64`, which is absent on this image,
and left a 28-byte incomplete environment file; the next `hexdump` format was
also rejected. The final local-only command derived a 32-hex-character value
from `/dev/urandom` using `md5sum` and yielded a 61-byte root-only file; the
value was never printed. An inline attempt to write `daemon.json` was
malformed by PowerShell quoting and failed `dockerd --validate`. It was
replaced by the checked-in `phase3c/daemon.json`, copied with `scp -O`, then
validated successfully before it was activated.

The first image-store attempt pulled `prom/prometheus:v3.14.0` but failed when
Docker 29.6.1 validated an image signature with `expected image index
descriptor, got application/vnd.docker.distribution.manifest.list.v2+json`.
The documented classic-store fallback was configured in
`/etc/docker/daemon.json` and validated with
`dockerd --validate --config-file=/etc/docker/daemon.json`:

```json
{
  "features": {
    "containerd-snapshotter": false
  }
}
```

`dockerd.globals.alt_config_file` was committed to that path and Docker was
restarted. `docker info` then reported `overlay2`. The pinned images were
successfully cached, but `docker compose ... up -d --pull=never` still failed
before creating either container:

```text
failed to create task for container: failed to create shim task: OCI runtime create failed: runc create failed: invalid rootfs: not an absolute path, or a symlink
```

`docker compose ps -a` and `docker ps -a` were empty afterward; neither port
9090 nor 3000 listens. This is a Docker/runc compatibility failure on the
current router image, not a successful Prometheus or Grafana deployment. Do
not open ports, relax the firewall, or report a Grafana dashboard until a
container runtime remedy is verified. The pre-change backup remains available;
current rollback planning must account for the installed Docker packages and
the committed `dockerd` configuration, not just containers.

#### 2026-09-24 JST — Approved reboot retest (executed; failure reproduced)

The operator explicitly approved a DS57U reboot to test whether the Docker/runc
failure was transient. Immediately before it, `dockerd` and
`prometheus-node-exporter-lua` were `running`; only `127.0.0.1:9100` listened.
Prometheus and Grafana were in Docker `Created` state but were not running.
The approved command was:

```text
ssh -i .local-ssh\id_ed25519_v2 -o BatchMode=yes root@192.168.1.1 "sync; reboot"
```

After reconnecting, the router reported uptime 5 minutes, both host services
were `running`, Docker reported `overlay2`, and only the exporter loopback port
listened. The reboot cleared the classic-store image cache, so the exact pinned
images were fetched again before the retest:

```text
docker pull prom/prometheus:v3.14.0
docker pull grafana/grafana:13.2.1
docker compose -f /etc/phase3c/compose.yml up -d --pull=never
```

Both pulls completed, including Prometheus digest
`sha256:5ce7540c3c00ef4ab0c9d2c995c6a5b9c421f44b4a115d97a2c7af3b1c21cbb0`
and Grafana digest
`sha256:f772d434e8fab0049deb2b1b30abd43342bcfca1537614aa8d36080232cf4283`.
The final startup attempt created the two containers but failed at the same
point with the same `runc create failed: invalid rootfs: not an absolute path,
or a symlink` error. `docker compose ps` was empty afterward. Therefore the
reboot did not remedy the Docker/runc incompatibility; Prometheus and Grafana
remain unstarted, and 9090/3000 remain closed.

A subsequent post-restart observation confirmed the router was still up (8
minutes uptime; load `0.41, 0.30, 0.11`), `dockerd` and the exporter service
were both `running`, and only `127.0.0.1:9100` listened. The Grafana and
Prometheus containers were again present only as `Created`, not running. This
does not change the failed-runtime verdict or expose new monitoring ports.

#### 2026-09-26 JST — Docker data-root remedy and successful stack startup (executed)

The topology remained `ONU -> BUFFALO -> DS57U eth0`, with management through
the white `eth1` LAN cable. A fresh recovery artifact was made before changing
the Docker configuration. `sysupgrade -b /tmp/phase3c-before-docker-rootfix.tar.gz`
exited `0`; its router SHA-256 was
`3f4b6d4c245d9e695a59d1bad8d74ac7bf9197cbe585d99897a9a88c2ad4fc66`.
It was copied with `scp -O` to ignored
`backups/phase3c-before-docker-rootfix.tar.gz`; `certutil` reported the same
SHA-256.

Read-only diagnosis found that `dockerd` was running from the alternate
configuration file `/etc/docker/daemon.json`. On this OpenWrt init script, an
`alt_config_file` replaces (rather than merges with) the generated UCI Docker
configuration. The alternate file enabled the classic image store but omitted
`data-root`; consequently Docker used `/var/lib/docker`. On this image,
`/var` resolves to `/tmp`, so each overlay `MergedDir` began with the symlinked
path `/var/lib/docker/...`. runc 1.3.6 rejects a rootfs which is a symlink or
contains one, explaining the reproducible `invalid rootfs` error. The physical
and intended persistent path `/opt/docker` was present, but had not been active.

The checked-in `phase3c/daemon.json` was changed to retain the classic-store
workaround and explicitly set the physical data root:

```json
{
  "data-root": "/opt/docker",
  "features": {
    "containerd-snapshotter": false
  }
}
```

The candidate was copied to `/tmp/phase3c-daemon.json`; both
`dockerd --validate --config-file=/tmp/phase3c-daemon.json` and the validation
after copying it to `/etc/docker/daemon.json` returned `configuration OK` and
exit `0`. `/etc/init.d/dockerd restart` then exited `0`, and `docker info`
reported `/opt/docker overlay2`. Since the former cache was under the
RAM-backed default root, the pinned images were deliberately pulled again:

```sh
docker pull prom/prometheus:v3.14.0
docker pull grafana/grafana:13.2.1
docker compose -f /etc/phase3c/compose.yml up -d --pull=never
```

Both pulls completed with the previously recorded pinned digests. Compose
created and started both services; its exit status was `0`. After one 30-second
scrape interval, `docker compose ... ps` showed both containers `Up`.
`netstat -lnt` showed only `127.0.0.1:9100`, `127.0.0.1:9090`, and
`127.0.0.1:3000` for the monitoring stack. Prometheus
`/api/v1/targets` returned the `openwrt` target at `127.0.0.1:9100` with
`"health":"up"` and no scrape error. Grafana `/api/health` returned
database `ok`, version `13.2.1`; the provisioned `OpenWrt Overview` dashboard
file remains present. Root storage was `4.5G` used with `113.2G` free.

Grafana's root-only environment file contains a 32-character administrator
password, but a BusyBox `wget` Basic-auth API probe returned HTTP `401`.
`grafana cli admin reset-admin-password` was run inside the running container
with that value unprinted and reported success; the same probe after a Grafana
restart still returned `401`. This does not affect the healthy service,
loopback listener, provisioning files, or Prometheus scrape. It is retained as
an uncompleted authenticated-browser login/dashboard check rather than being
claimed as verified. No LAN/WAN monitoring ports were opened.

#### 2026-09-26 JST — LAN-only Grafana browser access (executed)

The operator requested access from the management PC and smartphones on the
same `192.168.1.0/24` LAN. The exposure decision is intentionally limited to
Grafana: Prometheus stays on `127.0.0.1:9090` and the exporter stays on
`127.0.0.1:9100`; neither raw metrics endpoint is reachable by LAN clients.
Grafana is bound specifically to the current router LAN address
`192.168.1.1:3000`, rather than to all interfaces. This is not a WAN exposure:
the observed firewall keeps WAN input `REJECT`, while the existing LAN zone
input is `ACCEPT`. No firewall or UCI configuration was changed.

Before the change, a new backup was made with
`sysupgrade -b /tmp/phase3c-before-lan-grafana.tar.gz`; it exited `0`. Its
router and copied-PC SHA-256 values both were
`3f4b6d4c245d9e695a59d1bad8d74ac7bf9197cbe585d99897a9a88c2ad4fc66`.
The copy is ignored at `backups/phase3c-before-lan-grafana.tar.gz`.

`phase3c/compose.yml` now sets
`GF_SERVER_HTTP_ADDR: 192.168.1.1`. The candidate copied to
`/tmp/phase3c-compose.yml` passed `docker compose ... config --quiet` with exit
`0`; the deployed `/etc/phase3c/compose.yml` passed the same validation. The
following targeted recreation exited `0` and did not restart Prometheus:

```sh
docker compose -f /etc/phase3c/compose.yml up -d --no-deps --force-recreate grafana
```

After startup, `netstat -lnt` showed `192.168.1.1:3000` for Grafana, while
Prometheus and the exporter remained `127.0.0.1:9090` and `127.0.0.1:9100`.
The router's LAN-address Grafana health request returned exit `0` and database
`ok`; a PC-side request to
`http://192.168.1.1:3000/api/health` returned HTTP `200`. Smartphone browser
access is expected on the same LAN but remains a physical-device check. Use
`http://192.168.1.1:3000` (not HTTPS) and the Grafana administrator credential;
never place that credential in project documentation.

#### 2026-09-26 JST — Grafana administrator credential reset and login verification (executed)

At the operator's explicit request, the existing Grafana `admin` account was
reset to an operator-supplied password. The value was passed directly to
`grafana cli admin reset-admin-password` inside the running container and was
redirected away from terminal output; it is deliberately not recorded here or
in any checked-in file. The command exited `0`.

The first two router-local form probes used URL-encoded POST data and returned
HTTP `400`; Grafana 13's `/login` endpoint requires JSON. The corrected probe
sent JSON with `user` and `password` fields to
`http://192.168.1.1:3000/login`; it exited `0` and returned
`{"message":"Logged in","redirectUrl":"/"}`. This verifies the actual
Grafana login endpoint over the LAN listener without printing the credential.

#### 2026-09-26 JST — Restore Grafana provisioning visibility (executed)

The operator reported that the `OpenWrt Overview` dashboard was absent. The
running Grafana logs identified the cause directly: the bind-mounted
`/etc/grafana/provisioning/dashboards` and `datasources` directories could not
be read (`permission denied`). Router inspection showed every parent directory
from `/etc/phase3c/grafana` through both provisioning directories was
`drwx------ root root`; the JSON and YAML files themselves were already
root-readable. Grafana runs as a non-root user, so it could not traverse the
directories and skipped both dashboard and datasource provisioning.

Before the correction, `sysupgrade -b
/tmp/phase3c-before-provisioning-perms.tar.gz` exited `0`. The router and
ignored PC copy `backups/phase3c-before-provisioning-perms.tar.gz` both had
SHA-256 `3f4b6d4c245d9e695a59d1bad8d74ac7bf9197cbe585d99897a9a88c2ad4fc66`.

The four configuration-only directories were changed from `0700` to `0755`:

```sh
chmod 0755 /etc/phase3c/grafana \
  /etc/phase3c/grafana/provisioning \
  /etc/phase3c/grafana/provisioning/dashboards \
  /etc/phase3c/grafana/provisioning/datasources
docker compose -f /etc/phase3c/compose.yml up -d --no-deps --force-recreate grafana
```

Both `chmod` and the targeted Grafana recreation exited `0`; Prometheus was
not restarted. The new Grafana log contains `starting to provision dashboards`
and `finished to provision dashboards`, with no provisioning read error; it
also records `inserting datasource from configuration name=Prometheus`.
Grafana remains listening at `192.168.1.1:3000`, and its health endpoint again
returned database `ok`. If this configuration tree is copied to the router
again, preserve or reapply these directory execute/read permissions before
recreating Grafana.

### 8.3 Phase 3C checklist

- [x] Recorded router storage/RAM capacity, existing listeners, firewall exposure, and package-index limitation
- [x] Select router-local, loopback-only exporter/Prometheus/Grafana model and migration boundary
- [x] Create and hash-verify a fresh pre-change backup
- [x] Refresh package metadata, simulate, and install the selected exporter/Docker footprint
- [x] Verify exporter binding at `127.0.0.1:9100` and no LAN/WAN metrics listener
- [x] Record retention, secret handling, migration paths, image versions, and Docker/runc failure evidence
- [x] Perform the approved router reboot retest; failure reproduced with freshly pulled pinned images
- [x] Resolve the Docker/runc rootfs failure by selecting the physical `/opt/docker` data root in the complete alternate Docker configuration
- [x] Start Prometheus and validate its `up` target at `127.0.0.1:9090`
- [ ] Validate authenticated Grafana browser login/dashboard at `192.168.1.1:3000` (service health, LAN binding, and provisioning are verified; login probe remains pending)
- [x] Expose Grafana only at `192.168.1.1:3000` and verify PC-side HTTP access; keep Prometheus/exporter loopback-only
- [x] Reset the Grafana `admin` credential at the operator's request and verify authenticated login through the LAN listener
- [x] Restore readable dashboard/datasource provisioning directories and verify Grafana provisioning logs
- [ ] Confirm authenticated Grafana dashboard use from a smartphone on the same LAN
- [ ] Perform a finalized package/configuration rollback procedure or restore test

## 9. PC-to-router LAN Cable Comparison

### 2026-09-24 JST — Current Cat6 baseline (executed)

Topology was unchanged: this PC's ASIX AX88179 USB 3.0-to-Gigabit adapter
(`Ethernet 2`, IPv4 `192.168.1.157`) was connected by the current Cat6 cable to
the DS57U `eth1` LAN port (`192.168.1.1`). This was a read-only test; no router
configuration, package, or service state was changed.

The local adapter-management APIs (`Get-NetAdapter` and
`Get-CimInstance Win32_NetworkAdapter`) were denied by the current Windows
session, so the authoritative negotiated-speed and error-counter observations
come from the router port. `ethtool` is not installed on this OpenWrt image
(`ash: ethtool: not found`); the supported sysfs values were used instead.

Commands, in execution order:

```text
ipconfig /all
ssh -i .local-ssh/id_ed25519_v2 -o IdentitiesOnly=yes -o BatchMode=yes root@192.168.1.1 "date -Iseconds; cat /sys/class/net/eth1/{carrier,speed,duplex}; cat /sys/class/net/eth1/statistics/{rx_bytes,tx_bytes,rx_packets,tx_packets,rx_errors,tx_errors,rx_dropped,tx_dropped}"
ping.exe -n 10 -w 100 192.168.1.1
ssh -i .local-ssh/id_ed25519_v2 -o IdentitiesOnly=yes -o BatchMode=yes root@192.168.1.1 "date -Iseconds; cat /sys/class/net/eth1/{carrier,speed,duplex}; cat /sys/class/net/eth1/statistics/{rx_bytes,tx_bytes,rx_packets,tx_packets,rx_errors,tx_errors,rx_dropped,tx_dropped}"
```

The router baseline at `2026-09-24T08:04:29+00:00` was carrier `1`,
`1000` Mb/s, `full` duplex, RX/TX bytes `35951742`/`387788768`, RX/TX packets
`107194`/`292900`, and zero RX/TX errors and drops. After the local test, at
`2026-09-24T08:07:07+00:00`, carrier and negotiated link remained `1`,
`1000` Mb/s, and `full`; RX/TX errors and drops remained zero. The final
RX/TX bytes were `37513390`/`390193808` and packets `110288`/`297264`.

`ping.exe` returned `Sent = 10, Received = 10, Lost = 0 (0% loss)` with
minimum/maximum/average round-trip time `0` ms (Windows displays the replies
as `<1ms`). The larger preceding 100-request local ping run also showed only
`<1ms` or `1ms` replies in its captured excerpt, but its summary was not
retained; it is not used as the pass criterion.

Verdict: the current Cat6 path negotiated gigabit full duplex and showed no
router-observed errors, drops, or loss during this short local test. This does
not rule out an intermittent, load-dependent, PC-adapter, or connector fault.
The Cat6A comparison remains pending the physical replacement and must repeat
the same checks before a cable-quality conclusion is made.

### 2026-09-24 JST — Replacement Cat6A comparison (executed)

The user replaced the PC-to-router cable. The topology for this retest was this
PC's ASIX AX88179 USB 3.0-to-Gigabit adapter (`Ethernet 2`,
`192.168.1.157`) -- Cat6A -- DS57U `eth1` (`192.168.1.1`). No router
configuration, package, or service state was changed.

The same read-only command sequence was used: a router sysfs snapshot, then
`ping.exe -n 10 -w 100 192.168.1.1`, then a second router snapshot. At
`2026-09-24T08:09:17+00:00`, `eth1` carrier was `1`, speed `1000` Mb/s, and
duplex `full`; RX/TX byte counters were `38627074`/`392162767`, packet counters
were `113005`/`300934`, and RX/TX errors and drops were all zero. At
`2026-09-24T08:09:44+00:00`, carrier/speed/duplex were unchanged; bytes were
`39323889`/`392418394`, packets were `113929`/`301856`, and all four
error/drop counters remained zero.

The ping returned `Sent = 10, Received = 10, Lost = 0 (0% loss)` and
minimum/maximum/average `0` ms (each reply displayed as `<1ms`).

Comparison verdict: both the old Cat6 and replacement Cat6A cables negotiated
gigabit full duplex, returned the short local ping test without loss, and kept
the router's observed `eth1` error/drop counters at zero. The replacement does
not show an observable improvement in this short test, so the old cable is not
confirmed defective. Intermittent/load-dependent faults and PC-side adapter or
connector issues remain outside what this test can exclude.
