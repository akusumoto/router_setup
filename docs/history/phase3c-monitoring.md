# Phase 3C - Execution History

Manual: [monitoring rebuild](../../phase3-monitoring.md).

Dated evidence, including superseded settings, failures, corrections and rollback plans. Original section numbers are retained. Use the manual and checked-in configuration for a rebuild.

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

The standalone [Phase 3C monitoring and visualization inventory](../../phase3c/monitoring-inventory.md)
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

### 2026-09-27 JST - Detailed OpenWrt metrics dashboard (executed)

The user requested that all monitorable router parameters be added to the
existing Prometheus/Grafana stack where possible. Before changing Grafana, the
installed loopback-only exporter was inspected. Its active collector families
are conntrack, CPU, entropy, file descriptors, load average, memory, network
class/state, network-device counters, OpenWrt identity, SELinux state, time,
and uname. It reports `eth0`, `eth1`, and `br-lan` carrier, negotiated speed,
traffic, packet, error, and drop counters; it reports CPU time, load, memory,
conntrack count/limit, process state, uptime, file descriptors, entropy, and
per-collector success. The exporter was confirmed running. Its endpoint remains
`127.0.0.1:9100` and was not exposed to the LAN or WAN.

Filesystem capacity, thermal/fan values, DHCP leases, firewall-rule counters,
routing/MAP-E state, Wi-Fi state, and active latency/loss/throughput probes are
not emitted by this exporter. The DS57U has `thermal_zone0`, `thermal_zone1`,
and `thermal_zone2`, but no temperature value was added without a separately
reviewed collector/probe design. No packet payload, DNS query, client identity,
or per-flow data was added.

A fresh pre-change configuration archive was created with
`sysupgrade -b /tmp/phase3c-before-detailed-dashboard.tar.gz`. The router SHA-256
and the ignored local copy `backups/phase3c-before-detailed-dashboard.tar.gz`
both were `3f4b6d4c245d9e695a59d1bad8d74ac7bf9197cbe585d99897a9a88c2ad4fc66`.

The new source dashboard is
`phase3c/grafana/provisioning/dashboards/openwrt-detailed.json`; it adds the
separate provisioned dashboard **OpenWrt Detailed Metrics**, preserving the
existing concise overview. The candidate was copied to `/tmp/openwrt-detailed.json`
and successfully parsed with `jsonfilter -i /tmp/openwrt-detailed.json -e @`.
It was installed as
`/etc/phase3c/grafana/provisioning/dashboards/openwrt-detailed.json` with mode
`0644`. The existing Compose file passed:

```sh
docker compose -f /etc/phase3c/compose.yml config --quiet
docker compose -f /etc/phase3c/compose.yml up -d --no-deps --force-recreate grafana
```

Both commands exited `0`; only `phase3c-grafana-1` was recreated. Prometheus
and the exporter were not restarted. The router-local Prometheus health endpoint
returned `Prometheus Server is Healthy.` and Grafana's LAN-address health
endpoint returned database `ok` for Grafana `13.2.1`. Recent Grafana logs
contained `starting to provision dashboards` followed by `finished to provision
dashboards`, with no dashboard parse or provisioning-read error. Grafana still
listens only at `192.168.1.1:3000`; browser inspection of the new dashboard is
the remaining user-interface check.

### 2026-09-27 JST - Link-speed display unit (executed)

The user requested a non-ambiguous link-speed display. The **Negotiated
interface speed** query originally displayed the exporter byte-rate metric in
`Bps`, which made gigabit links appear as `125 MB/s`. The dashboard now uses:

```promql
node_network_speed_bytes{device=~"eth0|eth1|br-lan"} * 8 / 1000000
```

with the Grafana unit `Mbps` and the title **Negotiated interface speed
(Mb/s)**. Therefore a physical port reports `1000 Mb/s` for 1000BASE-T and
`100 Mb/s` for 100BASE-TX. `eth0` and `eth1` are physical ports; `br-lan` is a
virtual bridge and is not a separate cable-negotiation result.

Before deployment, `sysupgrade -b /tmp/phase3c-before-link-speed-unit.tar.gz`
exited `0`. Its router and ignored local-copy SHA-256 values both were
`3f4b6d4c245d9e695a59d1bad8d74ac7bf9197cbe585d99897a9a88c2ad4fc66`.
The source JSON was copied to `/tmp/openwrt-detailed.json`, successfully parsed
with `jsonfilter`, placed in Grafana's provisioning directory at mode `0644`,
and applied with:

```sh
docker compose -f /etc/phase3c/compose.yml up -d --no-deps --force-recreate grafana
```

The command exited `0` and recreated only Grafana. The first immediate LAN
health request returned `Operation not permitted` while Grafana was still
starting; the retry returned database `ok` for Grafana `13.2.1`. Prometheus
remained healthy throughout. Browser rendering of the adjusted panel remains
the final user-interface check.

## 11. Hourly OpenWrt Internet-performance monitor

### 2026-09-27 JST - Router-only hourly performance monitoring (executed)

The user requested that the prior OpenWrt performance check run once per hour
and be shown in Grafana. The historical comparison used three 25 MB samples in
each direction. For a recurring monitor, this implementation runs one valid
25,000,000-byte download and one valid 25,000,000-byte upload each hour from
the DS57U itself: 50 MB/hour (approximately 1.2 GB/day). This limits data use
and avoids the prior multi-request Cloudflare rate-limit risk while retaining
the original endpoint and validity conditions.

`curl-8.22.0-r1` (plus `libcurl4` and `libnghttp2-14`) was simulated, then
installed successfully after `apk update`. The job is
`/usr/local/sbin/router-performance-hourly`, scheduled by the new root cron
entry `0 * * * * /usr/local/sbin/router-performance-hourly`. It uses a
non-blocking lock, calls the Cloudflare 25 MB downlink and synthetic-zero
uplink endpoints, and accepts each direction only when curl succeeds, HTTP is
`200`, and the transferred byte count is exactly `25000000`. Rates are
converted from curl bytes/sec to decimal Mb/s. Invalid directions produce a
validity gauge of `0` and no throughput value, preventing stale values from
being displayed as a new sample.

The existing loopback-only Lua exporter was extended with the local
`router_performance` collector. It reads the job's atomically replaced state at
`/opt/phase3c/performance/latest` and emits download/upload Mb/s, each
direction's validity, complete-run validity, and last-run time. It does not add
a listener. Prometheus continues to scrape `127.0.0.1:9100`; Grafana received
the provisioned **OpenWrt Performance** dashboard. The dashboard includes a
throughput time series and validity panels.

A fresh pre-change archive was created using
`sysupgrade -b /tmp/phase3c-before-hourly-performance.tar.gz`. The router and
ignored local copy `backups/phase3c-before-hourly-performance.tar.gz` both had
SHA-256 `3f4b6d4c245d9e695a59d1bad8d74ac7bf9197cbe585d99897a9a88c2ad4fc66`.
All staged shell and JSON files passed `sh -n` and `jsonfilter` validation.

The initial manually invoked run completed with both directions valid:

```text
download_mbps=356.846
upload_mbps=285.811
download_valid=1
upload_valid=1
run_success=1
```

After the collector was installed, it did not appear until the exporter was
restarted; this was corrected by restarting only
`prometheus-node-exporter-lua`. The loopback endpoint then emitted all six
`router_performance_*` metric families with collector success `1`. After the
next 30-second scrape, Prometheus returned `router_performance_run_success=1`
for job `openwrt`. Grafana health returned database `ok`; Prometheus reported
healthy. Cron reported `running`. The current topology is still
`ONU -> BUFFALO -> DS57U`, so this is an OpenWrt-originated performance
indicator through the upstream BUFFALO path, not a direct-ONU test, a
BUFFALO-path comparison, or a maximum-line-rate certification.

### 2026-09-27 JST - Three-parallel-flow performance update (executed)

At the user's request, the hourly monitor was changed from one download and one
upload to three concurrent 25 MB downloads followed by three concurrent 25 MB
uploads. Directions remain separate so that download and upload do not compete
with each other. A full hourly run therefore transfers 150 MB, approximately
3.6 GB/day.

For each direction, all three curl requests must succeed, return HTTP `200`,
and transfer exactly `25000000` bytes. **Internet performance** is the
aggregate rate calculated as the three valid transfer byte counts divided by
the longest individual completion time. **Internet performance (single)** is
the fastest individual flow. A direction with fewer than three valid samples
has validity `0` and no throughput metric. The local state and exporter now
also expose each direction's valid-sample count.

A fresh pre-change archive was created at
`/tmp/phase3c-before-parallel-performance.tar.gz`; its router and ignored
local-copy SHA-256 values both were
`225883de65da189405e8501f6d07c153f01502625b6c750e4f0dec3a83d6d01d`.
The changed script passed `sh -n`, and the Grafana JSON passed `jsonfilter`.
Only the local exporter was restarted and only Grafana was recreated.

The first three-parallel-flow run completed with all six transfers valid:

| Direction | Internet performance (aggregate) | Internet performance (single) | Valid samples |
|---|---:|---:|---:|
| Download | 504.354 Mb/s | 293.360 Mb/s | 3/3 |
| Upload | 318.311 Mb/s | 170.488 Mb/s | 3/3 |

The loopback exporter emitted the aggregate, fastest-single, validity, and
valid-sample-count metrics with collector success `1`; Grafana health returned
database `ok`. These are one current Cloudflare-path observation, not a
guaranteed Internet line rate.

The Grafana validity panel labels were then finalized as **3 x HTTP 200 / 25
MB** and Grafana alone was recreated once more. The first two immediate LAN
health probes returned `Operation not permitted` during Grafana startup. Router
logs then showed successful dashboard provisioning and the HTTP listener on
`192.168.1.1:3000`; the final retry returned database `ok` for Grafana `13.2.1`.

### 2026-09-27 JST - Performance-dashboard visual layout (executed)

At the user's request, the performance panel title was shortened from
**Hourly OpenWrt Internet performance (three parallel flows)** to **Internet
performance (three parallel flows)** and converted from a time-series panel to
a Grafana bar chart. The three latest-validity stat panels were removed. A
second panel, **Internet performance (three parallel flows) gauge**, now shows
the latest aggregate and fastest-single download/upload values as four gauges.

Before the layout change, `sysupgrade -b
/tmp/phase3c-before-performance-layout.tar.gz` completed. The router and
ignored local-copy SHA-256 values both were
`225883de65da189405e8501f6d07c153f01502625b6c750e4f0dec3a83d6d01d`. The
candidate JSON parsed successfully with `jsonfilter`, was installed at mode
`0644`, and only Grafana was recreated. The Grafana LAN health endpoint
returned database `ok` for version `13.2.1` after normal startup.

### 2026-09-27 JST - Measurement-time-only performance bars (executed)

The user requested that the **Internet performance (three parallel flows)** bar
chart show bars only at actual hourly measurement time, not every Prometheus
scrape while the last value is retained. Each of its four PromQL queries now
returns a value only when `router_performance_last_run_timestamp_seconds`
differs from the value at the preceding 30-second scrape. The gauge continues
to query the unfiltered metrics and therefore shows the current latest values.

Before this configuration-only update, `sysupgrade -b
/tmp/phase3c-before-measurement-bars.tar.gz` completed. The router and ignored
local-copy SHA-256 values both were
`225883de65da189405e8501f6d07c153f01502625b6c750e4f0dec3a83d6d01d`. The
JSON parsed successfully with `jsonfilter`, Grafana alone was recreated, and
its LAN health endpoint returned database `ok` for version `13.2.1`.

### 2026-09-27 JST - Performance-panel label simplification (executed)

The bar-chart title is now **Internet performance** and the companion gauge
title is **Internet performance gauge**. In both panels, the four series are
named **download**, **download (single)**, **upload**, and **upload (single)**.
The PromQL expressions, measurement-time-only filter on the bar chart, units,
and panel layout were not changed.

Before this label-only provisioning update, `sysupgrade -b
/tmp/phase3c-before-performance-labels.tar.gz` completed. The router and
ignored local-copy SHA-256 values both were
`225883de65da189405e8501f6d07c153f01502625b6c750e4f0dec3a83d6d01d`. The
JSON parsed successfully with `jsonfilter`, was installed at mode `0644`, and
only Grafana was recreated. Its LAN health endpoint returned database `ok` for
version `13.2.1`.

### 2026-09-27 JST - One bar per completed hourly run (executed)

The `10:00:20` and `10:00:40` bars were the same single hourly test result,
not two cron executions. The root cron entry remains `0 * * * *
/usr/local/sbin/router-performance-hourly`. The previous panel filter compared
the stored run timestamp with its value `offset 30s`. With the 20-second
Prometheus scrape cadence, that condition was true at both first and second
scrapes after the state file changed, producing two bars.

The four bar-chart queries now use the timestamp transition itself:

```promql
router_performance_download_aggregate_mbps and on (instance, job)
  (changes(router_performance_last_run_timestamp_seconds[30s]) > 0)
```

The corresponding upload and fastest-single queries use the same
`changes(...[30s]) > 0` predicate. A 30-second window includes the prior value
at the first post-run 20-second scrape but, at the next scrape, contains only
the new value; therefore it produces one sample per completed run. This changes
dashboard presentation only: it does not alter the hourly script, cron timing,
or measurement data.

Execution order and observed results:

```text
ssh ... sha256sum /etc/phase3c/grafana/provisioning/dashboards/openwrt-performance.json
c72f00c972f5d66ee8b56370c4c2409d095a66e50b2cb3720ee252d1ef128219  /etc/phase3c/grafana/provisioning/dashboards/openwrt-performance.json

ssh ... cp /etc/phase3c/grafana/provisioning/dashboards/openwrt-performance.json /tmp/openwrt-performance.before-single-bar.json
exit 0

scp ... phase3c/grafana/provisioning/dashboards/openwrt-performance.json root@192.168.1.1:/tmp/openwrt-performance.json
ash: /usr/libexec/sftp-server: not found
scp: Connection closed

scp -O ... phase3c/grafana/provisioning/dashboards/openwrt-performance.json root@192.168.1.1:/tmp/openwrt-performance.json
exit 0

ssh ... jsonfilter -i /tmp/openwrt-performance.json -e @
exit 0; output contained all four changes(router_performance_last_run_timestamp_seconds[30s]) > 0 expressions

ssh ... cp /tmp/openwrt-performance.json /etc/phase3c/grafana/provisioning/dashboards/openwrt-performance.json
exit 0

ssh ... docker compose -f /etc/phase3c/compose.yml up -d --no-deps --force-recreate grafana
Container phase3c-grafana-1 Recreated
Container phase3c-grafana-1 Started

ssh ... wget -qO- http://192.168.1.1:3000/api/health
{ "database": "ok", "version": "13.2.1", ... }

ssh ... curl -s http://127.0.0.1:9090/api/v1/query?query=changes%28router_performance_last_run_timestamp_seconds%5B30s%5D%29%20%3E%200
{ "status": "success", "data": { "resultType": "vector", "result": [] } }
```

Local JSON parsing with Node and `git diff --check` both passed. The initial
SCP attempt used SFTP and failed because this OpenWrt image has no
`/usr/libexec/sftp-server`; retrying with `scp -O` succeeded. The temporary
router backup remains at `/tmp/openwrt-performance.before-single-bar.json` for
this boot. Existing historical duplicate points are retained in Prometheus;
the next completed hourly run is the runtime confirmation that newly rendered
bars are singular. The live Prometheus API accepted the new predicate; its
empty immediate result is expected because no timestamp changed in that
30-second window.

### 2026-09-27 JST - Restore hourly chart data (executed)

The **Internet performance** chart subsequently displayed **No data** even
though the gauge showed current values. The collector and current measurements
were healthy: the live Prometheus query
`last_over_time(router_performance_download_aggregate_mbps[1h])` returned
`543.491`. The problem was the previous `changes(...[30s]) > 0` event filter.
Prometheus scrapes this target every 30 seconds, so its 30-second range often
contains only one sample; `changes` is then zero and Grafana receives no bars.

The bar chart now uses `last_over_time` for each throughput metric and a
per-target minimum interval of `1h`, for example:

```promql
last_over_time(router_performance_download_aggregate_mbps[1h])
```

This returns the latest value in each one-hour bucket and makes Grafana request
one point per hour. It restores the historical graph without duplicating each
retained Prometheus scrape. The gauge queries remain unchanged.

Execution order and observed results:

```text
ssh ... curl -s http://127.0.0.1:9090/api/v1/query?query=last_over_time%28router_performance_download_aggregate_mbps%5B1h%5D%29
{ "status": "success", ..., "value": [1790475583.726, "543.491"] }

local node JSON.parse(...openwrt-performance.json...)
JSON_OK
local git diff --check
exit 0

ssh ... cp /etc/phase3c/grafana/provisioning/dashboards/openwrt-performance.json /tmp/openwrt-performance.before-hourly-buckets.json
exit 0

scp -O ... openwrt-performance.json root@192.168.1.1:/tmp/openwrt-performance.json
exit 0

ssh ... jsonfilter -i /tmp/openwrt-performance.json -e @
exit 0; output contained the four last_over_time(...[1h]) expressions and interval "1h"

ssh ... cp /tmp/openwrt-performance.json /etc/phase3c/grafana/provisioning/dashboards/openwrt-performance.json
exit 0

ssh ... docker compose -f /etc/phase3c/compose.yml up -d --no-deps --force-recreate grafana
Container phase3c-grafana-1 Recreated
Container phase3c-grafana-1 Started

ssh ... wget -qO- http://192.168.1.1:3000/api/health
first probe: Failed to send request: Operation not permitted
retry: { "database": "ok", "version": "13.2.1", ... }
```

The initial health probe occurred during normal Grafana startup; the retry
passed. The temporary rollback copy remains at
`/tmp/openwrt-performance.before-hourly-buckets.json` for this boot.

### 2026-09-27 JST - Performance line chart with large points (executed)

At the user's request, the **Internet performance** panel was changed from a
bar chart to a Grafana `timeseries` line chart. The four hourly
`last_over_time(...[1h])` queries and their one-hour minimum interval were not
changed. Its lines use linear interpolation, width `1`, no fill or stacking,
and `showPoints: "always"` with `pointSize: 10`. The **Internet performance
gauge** panel was not changed.

The candidate JSON passed local Node parsing and `git diff --check`. A router
rollback copy was made at `/tmp/openwrt-performance.before-line-chart.json`.
The JSON then passed router-side `jsonfilter`, was installed at
`/etc/phase3c/grafana/provisioning/dashboards/openwrt-performance.json`, and
Grafana alone was recreated:

```text
docker compose -f /etc/phase3c/compose.yml up -d --no-deps --force-recreate grafana
Container phase3c-grafana-1 Recreated
Container phase3c-grafana-1 Started
```

The first immediate LAN health probe returned `Operation not permitted` during
startup; its retry returned `{ "database": "ok", "version": "13.2.1", ... }`.

### 2026-09-27 JST - Correct time-series point-size schema (executed)

The line chart still rendered Grafana's default 5-pixel points because the
prior `pointSize: 10` was incorrectly stored in the panel `options` object.
For a Grafana time-series panel, visual field settings are read from
`fieldConfig.defaults.custom`. The **Internet performance** panel now stores:

```json
"custom": {
  "showPoints": "always",
  "pointSize": 10
}
```

The existing line styling was moved to that same `custom` object, and the
provisioned dashboard `version` was incremented from `1` to `2` so Grafana
applies the changed dashboard definition. The hourly queries and the gauge
panel remain unchanged.

Local JSON parsing verified `pointSize === 10`, `showPoints === "always"`, and
dashboard version `2`; `git diff --check` passed. A backup was saved to
`/tmp/openwrt-performance.before-point-size-10.json`. Router-side `jsonfilter`
then showed the same `custom.pointSize: 10` structure. Grafana alone was
recreated successfully. Its first immediate LAN health probe returned
`Operation not permitted` during startup; retry returned
`{ "database": "ok", "version": "13.2.1", ... }`.

### 2026-09-27 JST - First-completion concurrent-download aggregate (executed)

The user requested that **download** represent total bytes transferred across
the three concurrent downloads when the first one completes, divided by the
elapsed time at that instant. For example, at 3 seconds, one complete 25 MB
file plus 5 MB and 1 MB currently received by the other two becomes
`(25 + 5 + 1) MB / 3 s`.

`router-performance-hourly` now writes each download to a temporary file under
`/tmp/router-performance.*`. As soon as the first curl writes its status file,
the script reads the three file sizes, records the elapsed monotonic
`/proc/uptime` time, and calculates the download aggregate from that snapshot.
It then waits for every curl and retains the existing validation: all three
must exit successfully, return HTTP `200`, and have a final size of exactly
`25000000` bytes. The temporary files are removed. Upload calculation remains
unchanged (total three upload bytes divided by the slowest completion time).

The router had 2,363,940 KiB free in `/tmp`, so its at-most-75 MB temporary
download footprint was safe. Execution order and observed results:

```text
ssh ... cp /usr/local/sbin/router-performance-hourly /tmp/router-performance-hourly.before-first-completion-snapshot
exit 0

scp -O ... phase3c/performance/router-performance-hourly.sh root@192.168.1.1:/tmp/router-performance-hourly.sh
exit 0

ssh ... sh -n /tmp/router-performance-hourly.sh
exit 0

ssh ... install -m 0755 /tmp/router-performance-hourly.sh /usr/local/sbin/router-performance-hourly
ash: install: not found

ssh ... cp /tmp/router-performance-hourly.sh /usr/local/sbin/router-performance-hourly
ssh ... chmod 0755 /usr/local/sbin/router-performance-hourly
both exit 0

ssh ... /usr/local/sbin/router-performance-hourly
exit 0

ssh ... cat /opt/phase3c/performance/latest
download_valid=1
upload_valid=1
download_valid_samples=3
upload_valid_samples=3
run_success=1
download_aggregate_mbps=675.131
download_single_mbps=292.496
upload_aggregate_mbps=362.696
upload_single_mbps=267.520

ssh ... find /tmp -maxdepth 1 -type d -name router-performance.*
no output; temporary directory was removed
```

The 675.131 Mb/s download snapshot aggregate exceeded the 292.496 Mb/s
fastest single flow in this verification. The rollback copy remains at
`/tmp/router-performance-hourly.before-first-completion-snapshot` for this
boot.

### 2026-09-27 JST - First-completion concurrent-upload aggregate (executed)

The user requested that upload use the same first-completion calculation as
download. The upload aggregate now equals the completed 25 MB flow plus the
bytes supplied to each still-running upload at that instant, divided by elapsed
time since the three uploads started. All three uploads still must complete
with curl success, HTTP `200`, and exactly `25000000` bytes before the result
is accepted.

Initial attempts to use `/proc/<curl-pid>/io` read and write counters did not
include the active upload payload on this OpenWrt kernel; both validation runs
were successful but undercounted the two unfinished flows. This was corrected
with one FIFO per upload. A `/dev/zero` producer writes 1 MB blocks into its
FIFO and atomically updates a progress file only after each block reaches curl.
At first completion, each active flow contributes that progress value. FIFO
backpressure bounds the approximation to at most 1 MB per active flow, and the
temporary directory is removed afterward.

Execution evidence:

```text
scp -O ... router-performance-hourly.sh root@192.168.1.1:/tmp/router-performance-hourly.sh
ssh ... sh -n /tmp/router-performance-hourly.sh
ssh ... cp /tmp/router-performance-hourly.sh /usr/local/sbin/router-performance-hourly
ssh ... chmod 0755 /usr/local/sbin/router-performance-hourly
all exit 0

ssh ... /usr/local/sbin/router-performance-hourly
exit 0

ssh ... cat /opt/phase3c/performance/latest
download_valid=1
upload_valid=1
download_valid_samples=3
upload_valid_samples=3
run_success=1
download_aggregate_mbps=519.481
download_single_mbps=273.461
upload_aggregate_mbps=454.545
upload_single_mbps=196.018

ssh ... find /tmp -maxdepth 1 -type d -name router-performance.*
no output; temporary directory was removed
```

The prior first-completion download change remains active. The original
pre-upload-change script is retained at
`/tmp/router-performance-hourly.before-upload-first-completion-snapshot` for
this boot.

### 2026-09-27 JST - DS57U connected-device count (executed)

Added the loopback-only Lua collector
`router_lan_connected_devices`. It runs `ip neigh show dev br-lan`, accepts
entries with an `lladdr` except `FAILED` and `INCOMPLETE`, and counts unique
MAC addresses. This deduplicates IPv4 and IPv6 neighbor rows for the same
device. It counts devices currently visible directly to the DS57U; it does not
count clients only visible to the upstream BUFFALO or Wi-Fi associations hosted
elsewhere.

The collector parsed successfully with the installed `lua` runtime (this image
does not include `luac`), was installed at
`/usr/lib/lua/prometheus-collectors/router_connected_devices.lua`, and only
`prometheus-node-exporter-lua` was restarted. Its loopback endpoint emitted:

```text
# TYPE router_lan_connected_devices gauge
router_lan_connected_devices 2
```

The **OpenWrt Performance** provisioned dashboard now includes the
**Connected devices on DS57U LAN** stat panel with PromQL
`router_lan_connected_devices`; its version was incremented to `3`. Grafana
alone was recreated to load the panel.

### 2026-09-27 JST - Move connected-device graph to Detailed Metrics (executed)

At the user's request, **Connected devices on DS57U LAN** was removed from
**OpenWrt Performance** and added to **OpenWrt Detailed Metrics** as a
time-series line chart. It retains the `router_lan_connected_devices` query,
linear line styling, and visible points; the collector and metric semantics are
unchanged. Provisioned dashboard versions were advanced to `4` for Performance
and `2` for Detailed Metrics.

Both JSON files passed local Node parsing and `git diff --check`. They were
copied to `/etc/phase3c/grafana/provisioning/dashboards/`, and Grafana alone
was recreated. The first health probe returned `Operation not permitted` during
startup; retry returned `{ "database": "ok", "version": "13.2.1", ... }`.

### 2026-09-27 JST - Active IPv4 DS57U LAN-device count (executed)

The previous `router_lan_connected_devices` value was a neighbor-cache count.
It treated `STALE` entries as connected, so it could remain nonzero after a PC
was powered down. It has been replaced by the distinct
`router_lan_active_devices` gauge. A new metric name prevents the old
cache-based history from being interpreted as active-presence history.

The updated collector gathers candidate IPv4 addresses from both `br-lan`
neighbor rows and `/tmp/dhcp.leases`. For each candidate it sends one
`arping -I br-lan -c 1 -w 1` probe, then counts the unique MAC addresses that
actually reply. The probe timeout is one second. This is an active,
Layer-2 presence measurement and does not retain an offline device merely
because its old neighbor entry still exists. It does not count IPv6-only
clients, nor IPv4 clients with neither a DHCP lease nor a remembered neighbor
address; the Grafana panel explicitly states those boundaries. It neither
records client identities nor packet payloads.

The exact command sequence and observed results were:

```text
ssh ... "which arping; which ping; which bridge; ip addr show dev br-lan; ip neigh show dev br-lan"
exit 0
output: /bin/ping only; br-lan is 192.168.1.1/24

ssh ... "apk add arping"
exit 1
output: arping (no such package)

ssh ... "apk search arping; apk search iputils; apk search ndisc"
exit 0
output: iputils-arping-20250605-r1

ssh ... "apk add iputils-arping"
exit 0
output: Installing iputils-arping (20250605-r1); OK: 273.8 MiB in 263 packages

scp -O ... router-connected-devices.lua root@192.168.1.1:/tmp/router_connected_devices.lua
scp -O ... openwrt-detailed.json root@192.168.1.1:/tmp/openwrt-detailed.json
exit 0

ssh ... "lua /tmp/router_connected_devices.lua; cp /usr/lib/lua/prometheus-collectors/router_connected_devices.lua /tmp/router_connected_devices.before-active-probe.lua; cp /tmp/router_connected_devices.lua /usr/lib/lua/prometheus-collectors/router_connected_devices.lua; /etc/init.d/prometheus-node-exporter-lua restart"
exit 0

ssh ... "wget -qO /tmp/router-active-device-metrics http://127.0.0.1:9100/metrics; grep router_lan /tmp/router-active-device-metrics; grep router_connected_devices /tmp/router-active-device-metrics"
exit 0
# TYPE router_lan_active_devices gauge
router_lan_active_devices 1
node_scrape_collector_duration_seconds{collector="router_connected_devices"} 1.0760779380798
node_scrape_collector_success{collector="router_connected_devices"} 1

ssh ... "wget -qO- http://127.0.0.1:9090/api/v1/query?query=router_lan_active_devices"
exit 0
output: success; value 1 for job=openwrt, instance=127.0.0.1:9100

ssh ... "cp /etc/phase3c/grafana/provisioning/dashboards/openwrt-detailed.json /tmp/openwrt-detailed.before-active-devices.json; cp /tmp/openwrt-detailed.json /etc/phase3c/grafana/provisioning/dashboards/openwrt-detailed.json; docker compose -f /etc/phase3c/compose.yml up -d --no-deps --force-recreate grafana"
exit 0
output: phase3c-grafana-1 recreated and started; dashboard provisioning finished

ssh ... "wget -qO- http://192.168.1.1:3000/api/health; grep router_lan_active_devices /etc/phase3c/grafana/provisioning/dashboards/openwrt-detailed.json; sha256sum /usr/lib/lua/prometheus-collectors/router_connected_devices.lua /etc/phase3c/grafana/provisioning/dashboards/openwrt-detailed.json"
exit 0
output: Grafana database ok (13.2.1); panel title "Active IPv4 devices on DS57U LAN"; collector df9ccf02d5495ead0323a9e7fba138171b0f9528fc60b2ac99453d31d4da2f06; dashboard 4416cfc5390a1583556f3999cd1bfcfae55f7a8d28d1dfa35bc9c96c6e9c2c7b
```

The router-side rollback copies are
`/tmp/router_connected_devices.before-active-probe.lua` and
`/tmp/openwrt-detailed.before-active-devices.json` for this boot. Restore the
respective file, restart `prometheus-node-exporter-lua` for the collector, and
recreate Grafana alone for the dashboard. Removing `iputils-arping` is a
separate rollback action only after the prior collector has been restored.

### 2026-09-28 JST - Link-speed state timeline (executed)

The **Negotiated interface speed (Mb/s)** panel in **OpenWrt Detailed Metrics**
is now a Grafana `state-timeline`. It uses the existing speed query and retains
one timeline row per `eth0`, `eth1`, and `br-lan` series. Exact mappings are
`1000` to green **1000Mbps** and `100` to red **100Mbps**. The field default is
fixed gray, so every other value is gray. The dashboard version advanced from
`3` to `4`.

```text
node -p "require('./phase3c/grafana/provisioning/dashboards/openwrt-detailed.json').version"
exit 0

git diff --check
exit 0

scp -O -i .local-ssh/id_ed25519_v2 phase3c/grafana/provisioning/dashboards/openwrt-detailed.json root@192.168.1.1:/tmp/openwrt-detailed.json
exit 0

ssh -i .local-ssh/id_ed25519_v2 -o BatchMode=yes -o ConnectTimeout=10 root@192.168.1.1 "cp /etc/phase3c/grafana/provisioning/dashboards/openwrt-detailed.json /tmp/openwrt-detailed.before-link-state-timeline.json; cp /tmp/openwrt-detailed.json /etc/phase3c/grafana/provisioning/dashboards/openwrt-detailed.json; docker compose -f /etc/phase3c/compose.yml up -d --no-deps --force-recreate grafana"
exit 0
output: phase3c-grafana-1 recreated and started; dashboard provisioning finished

ssh -i .local-ssh/id_ed25519_v2 -o BatchMode=yes -o ConnectTimeout=10 root@192.168.1.1 "wget -qO- http://192.168.1.1:3000/api/health; grep state-timeline /etc/phase3c/grafana/provisioning/dashboards/openwrt-detailed.json; grep 1000Mbps /etc/phase3c/grafana/provisioning/dashboards/openwrt-detailed.json; grep 100Mbps /etc/phase3c/grafana/provisioning/dashboards/openwrt-detailed.json; sha256sum /etc/phase3c/grafana/provisioning/dashboards/openwrt-detailed.json"
exit 0
output: Grafana database ok (13.2.1); panel type state-timeline; fixed gray default; 1000 green 1000Mbps; 100 red 100Mbps; SHA-256 e18b187cff91f98265bf0e79d3a4d73e659b4deafc7451f5ac8750a9d4b9ad12
```

The boot-local rollback file is
`/tmp/openwrt-detailed.before-link-state-timeline.json`. Restore it to
`/etc/phase3c/grafana/provisioning/dashboards/openwrt-detailed.json` and
recreate Grafana alone to revert this panel.

### 2026-09-28 JST - Rename link-speed panel (executed)

The state-timeline panel title was changed from **Negotiated interface speed
(Mb/s)** to **NIC link speed state**. Its query, value mappings, colors, and
timeline configuration are unchanged. The provisioned dashboard version
advanced from `4` to `5`.

```text
git diff --check
exit 0

scp -O -i .local-ssh/id_ed25519_v2 phase3c/grafana/provisioning/dashboards/openwrt-detailed.json root@192.168.1.1:/tmp/openwrt-detailed.json
exit 0

ssh -i .local-ssh/id_ed25519_v2 -o BatchMode=yes -o ConnectTimeout=10 root@192.168.1.1 "cp /etc/phase3c/grafana/provisioning/dashboards/openwrt-detailed.json /tmp/openwrt-detailed.before-nic-link-speed-title.json; cp /tmp/openwrt-detailed.json /etc/phase3c/grafana/provisioning/dashboards/openwrt-detailed.json; docker compose -f /etc/phase3c/compose.yml up -d --no-deps --force-recreate grafana"
exit 0
output: phase3c-grafana-1 recreated and started; provisioning completed

ssh ... "wget -qO- http://192.168.1.1:3000/api/health; grep \"NIC link speed state\" /etc/phase3c/grafana/provisioning/dashboards/openwrt-detailed.json; sha256sum /etc/phase3c/grafana/provisioning/dashboards/openwrt-detailed.json"
exit 0
output: Grafana database ok (13.2.1); the shell split the quoted grep argument, but the displayed dashboard row contained title "NIC link speed state"; SHA-256 e9b3293b14a1e49df563ccca39bb5538f2117b73dbc4a4c326a3deb305c210ae

ssh -i .local-ssh/id_ed25519_v2 -o BatchMode=yes -o ConnectTimeout=10 root@192.168.1.1 "grep NIC /etc/phase3c/grafana/provisioning/dashboards/openwrt-detailed.json"
exit 0
output: dashboard row contains title "NIC link speed state"
```

The boot-local rollback file is
`/tmp/openwrt-detailed.before-nic-link-speed-title.json`. Restore it to the
provisioned dashboard path and recreate Grafana alone to revert the title.

### 2026-09-28 JST - Active connections through router (executed)

Added the **Active connections through router** stat panel to **OpenWrt
Detailed Metrics**. It displays the latest `node_nf_conntrack_entries` value:
the number of currently tracked conntrack network flows on the DS57U. It is not
a count of distinct devices or application sessions. The pre-existing
**Conntrack table used** percentage panel remains unchanged. Dashboard version
advanced from `5` to `6`.

```text
ssh -i .local-ssh/id_ed25519_v2 -o BatchMode=yes -o ConnectTimeout=10 root@192.168.1.1 "wget -qO- http://127.0.0.1:9090/api/v1/query?query=node_nf_conntrack_entries"
exit 0
output: success; current value 91

git diff --check
exit 0

scp -O -i .local-ssh/id_ed25519_v2 phase3c/grafana/provisioning/dashboards/openwrt-detailed.json root@192.168.1.1:/tmp/openwrt-detailed.json
exit 0

ssh -i .local-ssh/id_ed25519_v2 -o BatchMode=yes -o ConnectTimeout=10 root@192.168.1.1 "cp /etc/phase3c/grafana/provisioning/dashboards/openwrt-detailed.json /tmp/openwrt-detailed.before-active-connections.json; cp /tmp/openwrt-detailed.json /etc/phase3c/grafana/provisioning/dashboards/openwrt-detailed.json; docker compose -f /etc/phase3c/compose.yml up -d --no-deps --force-recreate grafana"
exit 0
output: phase3c-grafana-1 recreated and started; provisioning completed

ssh -i .local-ssh/id_ed25519_v2 -o BatchMode=yes -o ConnectTimeout=10 root@192.168.1.1 "wget -qO- http://192.168.1.1:3000/api/health; grep node_nf_conntrack_entries /etc/phase3c/grafana/provisioning/dashboards/openwrt-detailed.json; wget -qO- http://127.0.0.1:9090/api/v1/query?query=node_nf_conntrack_entries; sha256sum /etc/phase3c/grafana/provisioning/dashboards/openwrt-detailed.json"
exit 0
output: Grafana database ok (13.2.1); panel query and description present; current value 99; SHA-256 8427f514bedcc0e5d201099ee6223300450f833c6efd8bed450a437c308b5072
```

The boot-local rollback file is
`/tmp/openwrt-detailed.before-active-connections.json`. Restore it to the
provisioned dashboard path and recreate Grafana alone to revert this panel.

### 2026-09-28 JST - Active-connections line chart and app boundary (executed)

The **Active connections through router** panel is now a line chart with
visible points and the `connections` legend, rather than a stat. It retains
the `node_nf_conntrack_entries` query and displays active conntrack flows over
time.

Per-application unique connection monitoring was not added. The existing
exporter supplies conntrack network-flow metadata, not reliable application
identity. Inferring applications from ports would be incorrect, and encrypted
traffic prevents accurate classification without a separately reviewed DPI
design. The panel and inventory explicitly state this boundary.

```text
git diff --check
exit 0

scp -O -i .local-ssh/id_ed25519_v2 phase3c/grafana/provisioning/dashboards/openwrt-detailed.json root@192.168.1.1:/tmp/openwrt-detailed.json
exit 0

ssh -i .local-ssh/id_ed25519_v2 -o BatchMode=yes -o ConnectTimeout=10 root@192.168.1.1 "cp /etc/phase3c/grafana/provisioning/dashboards/openwrt-detailed.json /tmp/openwrt-detailed.before-active-connections-line.json; cp /tmp/openwrt-detailed.json /etc/phase3c/grafana/provisioning/dashboards/openwrt-detailed.json; docker compose -f /etc/phase3c/compose.yml up -d --no-deps --force-recreate grafana"
exit 0
output: phase3c-grafana-1 recreated and started; provisioning completed

ssh -i .local-ssh/id_ed25519_v2 -o BatchMode=yes -o ConnectTimeout=10 root@192.168.1.1 "wget -qO- http://192.168.1.1:3000/api/health; grep app-specific /etc/phase3c/grafana/provisioning/dashboards/openwrt-detailed.json; wget -qO- http://127.0.0.1:9090/api/v1/query?query=node_nf_conntrack_entries; sha256sum /etc/phase3c/grafana/provisioning/dashboards/openwrt-detailed.json"
exit 0
output: Grafana database ok (13.2.1); panel is a timeseries with the app-specific boundary; current conntrack value 51; SHA-256 02a1f0e8ea6edf2a524f9b1ef3a3bb72e2b125b7ac942c1813273ed08ec06774
```

The boot-local rollback file is
`/tmp/openwrt-detailed.before-active-connections-line.json`. Restore it to the
provisioned dashboard path and recreate Grafana alone to restore the stat
panel.

### 2026-09-28 JST - WAN latency and packet-loss probe (executed)

To investigate congestion/path symptoms that cannot be inferred from interface
byte counters alone, added the loopback-only Lua collector
`router_wan_probe`. It sends exactly three ICMP echo requests with a one-second
timeout to the fixed public target `1.1.1.1` on every 30-second exporter scrape.
It emits `router_wan_probe_success` (one or more replies),
`router_wan_probe_packet_loss_ratio`, and, when replies provide an average,
`router_wan_probe_rtt_seconds`; all three carry only `target="1.1.1.1"`.
It does not inspect payloads, collect DNS data, identify clients, classify
applications, or measure available throughput. ICMP treatment can differ from
application traffic, so these metrics are a single-target reachability/path
indicator rather than a line-rate or user-experience certification.

Pre-change compatibility checks found `/bin/ping` and the Lua collector
directory. The DS57U has thermal-zone directories but no readable `temp` or
`type` files below them, so temperature was deliberately not exported. The
pre-change probe returned three replies, zero loss, and `4.095 ms` average RTT.

The exact command sequence and observed results were:

```text
ssh -i .local-ssh/id_ed25519_v2 -o BatchMode=yes root@192.168.1.1 "printf 'PING='; command -v ping; printf 'WGET='; command -v wget; printf 'THERMAL='; find /sys/class/thermal -maxdepth 2 -type f \( -name temp -o -name type \) -print -exec cat {} \;; printf 'COLLECTORS='; ls /usr/lib/lua/prometheus-collectors; printf 'METRICS='; wget -qO- http://127.0.0.1:9100/metrics | grep -E 'node_nf_conntrack_entries|node_network_(receive|transmit)_(errs|drop)_total|node_cpu_seconds_total' | head -20"
exit 0
output excerpt: PING=/bin/ping; WGET=/usr/bin/wget; collector directory includes router_connected_devices.lua and router_performance.lua; no thermal value files printed

ssh -i .local-ssh/id_ed25519_v2 -o BatchMode=yes root@192.168.1.1 "/bin/ping -n -c 3 -W 1 1.1.1.1"
exit 0
output: 3 packets transmitted, 3 packets received, 0% packet loss; round-trip min/avg/max = 3.863/4.095/4.408 ms

scp -O -i .local-ssh/id_ed25519_v2 -o BatchMode=yes phase3c/wan-probe/router-wan-probe.lua root@192.168.1.1:/tmp/router_wan_probe.lua
scp -O -i .local-ssh/id_ed25519_v2 -o BatchMode=yes phase3c/grafana/provisioning/dashboards/openwrt-detailed.json root@192.168.1.1:/tmp/openwrt-detailed.wan-probe.json
both exit 0

ssh -i .local-ssh/id_ed25519_v2 -o BatchMode=yes root@192.168.1.1 "lua /tmp/router_wan_probe.lua && cp /usr/lib/lua/prometheus-collectors/router_wan_probe.lua /tmp/router_wan_probe.before-20260928.lua 2>/dev/null || true; cp /tmp/router_wan_probe.lua /usr/lib/lua/prometheus-collectors/router_wan_probe.lua && /etc/init.d/prometheus-node-exporter-lua restart"
exit 0

ssh -i .local-ssh/id_ed25519_v2 -o BatchMode=yes root@192.168.1.1 "wget -qO /tmp/router-wan-probe-metrics http://127.0.0.1:9100/metrics && grep -E 'router_wan_probe|node_scrape_collector_(success|duration_seconds).*router_wan_probe' /tmp/router-wan-probe-metrics"
exit 0
output: success=1; packet_loss_ratio=0; rtt_seconds=0.004125; collector duration=2.006453037262; collector success=1

ssh -i .local-ssh/id_ed25519_v2 -o BatchMode=yes root@192.168.1.1 "cp /etc/phase3c/grafana/provisioning/dashboards/openwrt-detailed.json /tmp/openwrt-detailed.before-wan-probe.json && cp /tmp/openwrt-detailed.wan-probe.json /etc/phase3c/grafana/provisioning/dashboards/openwrt-detailed.json && docker compose -f /etc/phase3c/compose.yml up -d --no-deps --force-recreate grafana"
exit 0
output: phase3c-grafana-1 recreated and started

ssh -i .local-ssh/id_ed25519_v2 -o BatchMode=yes root@192.168.1.1 "wget -qO- 'http://127.0.0.1:9090/api/v1/query?query=router_wan_probe_success'"
exit 0
output: success; value 1 for job=openwrt, instance=127.0.0.1:9100, target=1.1.1.1

ssh -i .local-ssh/id_ed25519_v2 -o BatchMode=yes root@192.168.1.1 "wget -qO- http://192.168.1.1:3000/api/health"
first two immediate post-recreation attempts: Failed to send request: Operation not permitted
retry exit 0
output: database ok, version 13.2.1
```

The **OpenWrt Detailed Metrics** dashboard now has the **WAN probe latency**
and **WAN probe packet loss** time-series panels; its version advanced from 7
to 8. The installed collector SHA-256 is
`eee1e6a3ef6f875b9954ec68379b3ce0db3f736f1eae954a27479a6d493f5d45`;
the installed dashboard SHA-256 is
`c39aa268be8945ee43c06e2d54d53cb78dd3e19768f87e0a3539b77b3f608c4a`.

For this boot, collector rollback is
`cp /tmp/router_wan_probe.before-20260928.lua /usr/lib/lua/prometheus-collectors/router_wan_probe.lua && /etc/init.d/prometheus-node-exporter-lua restart`
when the backup exists; otherwise remove the installed collector and restart
only that exporter. Dashboard rollback is
`cp /tmp/openwrt-detailed.before-wan-probe.json /etc/phase3c/grafana/provisioning/dashboards/openwrt-detailed.json && docker compose -f /etc/phase3c/compose.yml up -d --no-deps --force-recreate grafana`.

### 2026-09-28 JST - Per-LAN-device top traffic and connection monitoring (executed)

At the user's explicit request, the dashboard now retains a LAN IPv4 address as
the `device` Prometheus label. It does not collect hostnames, MAC addresses,
payloads, DNS queries, remote destinations, ports, or application labels.

`router_device_usage` derives the current IPv4 prefix from `br-lan`, reads the
existing conntrack table with accounting enabled, and attributes a flow to its
original LAN IPv4 source. It emits:

- `router_lan_device_active_connections{device="..."}`: current tracked-flow count.
- `router_lan_device_traffic_bytes_total{device="..."}`: a counter accumulated
  from bidirectional conntrack-byte deltas for flows visible at each scrape.

The detailed dashboard version advanced from 8 to 9 and adds **Top 10 LAN IPv4
devices by sampled traffic (5 minutes)** using
`topk(10, sum by (device) (rate(router_lan_device_traffic_bytes_total[5m])))`,
and **Top 10 LAN IPv4 devices by active connections** using
`topk(10, router_lan_device_active_connections)`. Traffic is intentionally
described as sampled: a flow that begins and ends entirely between 30-second
scrapes cannot be represented. A connection remains a network flow, not an
application session.

The exact command sequence and observed results were:

```text
ssh -i .local-ssh/id_ed25519_v2 -o BatchMode=yes root@192.168.1.1 "printf 'ACCT='; sysctl -n net.netfilter.nf_conntrack_acct 2>/dev/null; printf 'CONNTRACK='; conntrack -L -o extended 2>/dev/null | head -8; printf 'NFT_VERSION='; nft --version; printf 'NFT_RULESET_MATCHES='; nft list ruleset | grep -E 'counter|meter|quota' | head -30; printf 'DHCP='; head -10 /tmp/dhcp.leases"
exit 0
output excerpt: ACCT=1; conntrack records include both directions' packets and bytes; nftables v1.1.6; DHCP lease has 192.168.1.157 (hostname deliberately not exported)

scp -O -i .local-ssh/id_ed25519_v2 -o BatchMode=yes phase3c/device-usage/router-device-usage.lua root@192.168.1.1:/tmp/router_device_usage.lua
exit 0

ssh -i .local-ssh/id_ed25519_v2 -o BatchMode=yes root@192.168.1.1 'lua -e "metric=function(name, kind) return function(labels, value) print(name .. \"{device=\" .. labels.device .. \"} \" .. value) end end; local collector=dofile(\"/tmp/router_device_usage.lua\"); collector.scrape()"'
failed before collector execution: ash: syntax error: unexpected "("
correction: validate with `lua /tmp/router_device_usage.lua`, then use the normal exporter collector API.

ssh -i .local-ssh/id_ed25519_v2 -o BatchMode=yes root@192.168.1.1 "lua /tmp/router_device_usage.lua; cp /usr/lib/lua/prometheus-collectors/router_device_usage.lua /tmp/router_device_usage.before-20260928.lua 2>/dev/null || true; cp /tmp/router_device_usage.lua /usr/lib/lua/prometheus-collectors/router_device_usage.lua; /etc/init.d/prometheus-node-exporter-lua restart"
exit 0

ssh -i .local-ssh/id_ed25519_v2 -o BatchMode=yes root@192.168.1.1 "wget -qO /tmp/router-device-usage-metrics http://127.0.0.1:9100/metrics && grep -E 'router_lan_device_(traffic_bytes_total|active_connections)|node_scrape_collector_(success|duration_seconds).*router_device_usage' /tmp/router-device-usage-metrics"
exit 0
output: device=192.168.1.157; traffic_bytes_total=0; active_connections=7; collector success=1; duration=0.019003868103027 seconds

scp -O -i .local-ssh/id_ed25519_v2 -o BatchMode=yes phase3c/grafana/provisioning/dashboards/openwrt-detailed.json root@192.168.1.1:/tmp/openwrt-detailed.device-usage.json
ssh -i .local-ssh/id_ed25519_v2 -o BatchMode=yes root@192.168.1.1 "cp /etc/phase3c/grafana/provisioning/dashboards/openwrt-detailed.json /tmp/openwrt-detailed.before-device-usage.json && cp /tmp/openwrt-detailed.device-usage.json /etc/phase3c/grafana/provisioning/dashboards/openwrt-detailed.json && docker compose -f /etc/phase3c/compose.yml up -d --no-deps --force-recreate grafana"
both exit 0
output: phase3c-grafana-1 recreated and started

ssh -i .local-ssh/id_ed25519_v2 -o BatchMode=yes root@192.168.1.1 "wget -qO /tmp/router-device-usage-metrics-second http://127.0.0.1:9100/metrics; grep -E 'router_lan_device_(traffic_bytes_total|active_connections)|node_scrape_collector_success.*router_device_usage' /tmp/router-device-usage-metrics-second; wget -qO- 'http://127.0.0.1:9090/api/v1/query?query=router_lan_device_active_connections'; wget -qO- http://192.168.1.1:3000/api/health"
exit 0
output: traffic_bytes_total=788; exporter active_connections=37; collector success=1; Prometheus active_connections=35; Grafana database ok (13.2.1)
```

The installed collector SHA-256 is
`8b65b7ad99404b05ad03f88c268ff5faadae8e91fec49300a3c83e4c3eb39b64`;
the installed dashboard SHA-256 is
`f0f6e50a774091f1cc26a32d35ce909f2a6b227a6d75ea347a5f0f2c7b68102b`.
The counter snapshot is `/tmp/router_device_usage.state` and is intentionally
lost on reboot; Prometheus recognizes the resulting counter reset. For this
boot, restore `/tmp/router_device_usage.before-20260928.lua` when it exists,
otherwise remove the collector; then restart only
`prometheus-node-exporter-lua`. Restore
`/tmp/openwrt-detailed.before-device-usage.json` and recreate only Grafana to
roll back the dashboard panels.

### 2026-10-04 JST - Direct-ONU WAN interface monitoring (executed)

Topology: ONU -> DS57U `eth0`; LAN remains `eth1` / `br-lan` at
`192.168.1.1`. No cable move or network/firewall setting change was made.
The initial claim that NIC names might have changed was corrected by live
evidence: physical devices remain `eth0`/`eth1`; the added IPv4 WAN path is
`map-mape_auto`, which the dashboard selectors omitted.

Read-only baseline at `2026-10-04T17:08:03+09:00`, in one persistent SSH
session opened with:

```text
rtk proxy cmd.exe /c "ssh -tt -i .local-ssh/id_ed25519_v2 -o BatchMode=yes -o ConnectTimeout=10 root@192.168.1.1"
for n in wan wan6 lan mape_auto; do printf '%s ' "$n"; ubus call network.interface.$n status | jsonfilter -e '@.up' -e '@.device' -e '@.l3_device'; done
ls /sys/class/net
uci show vnstat
docker compose -f /etc/phase3c/compose.yml ps
wget -qO /tmp/monitoring-nic-baseline.metrics http://127.0.0.1:9100/metrics
grep -E '^node_network_(receive_bytes_total|speed_bytes|carrier)\{' /tmp/monitoring-nic-baseline.metrics
ip route show default
wget -qO- 'http://127.0.0.1:9090/api/v1/query?query=node_network_receive_bytes_total' | jsonfilter -e '@.status' -e '@.data.result[*].metric.device'
```

Observed: `wan up=false, device=eth0`; `wan6 up=true, device/l3_device=eth0`;
`lan up=true, device/l3_device=br-lan`; `mape_auto up=true,
l3_device=map-mape_auto`. Default IPv4 route: `default dev map-mape_auto scope
link`. Both containers were Up for five days. vnStat monitors `br-lan` and
`eth0`, so its existing physical-uplink accounting needs no change.
Prometheus query returned `success` (pipeline exit `0`) and devices
`docker0`, `lo`, `br-lan`, `ip6tnl0`, `eth0`, `eth1`, `map-mape_auto`.
Exporter evidence:

```text
node_network_receive_bytes_total{device="map-mape_auto"} 8554503130
node_network_receive_bytes_total{device="eth0"} 21072980552
node_network_speed_bytes{device="eth0"} 125000000
node_network_speed_bytes{device="eth1"} 125000000
node_network_carrier{device="map-mape_auto"} 1
router_wan_probe_success{target="1.1.1.1"} 1
```

All 16 exporter collector-success values were `1` (grep exit `0`). No
collector restart was needed. The DHCP `wan` being pending is distinct from
the working native IPv6 and MAP-E logical interfaces.

Failures and corrections: PowerShell/rtk parsing rejected initial regex
alternation and ambiguous `-e` / `-i` arguments; `rtk --%` worked for rg,
and `rtk proxy cmd.exe /c "ssh ..."` worked for SSH. The sandbox initially
denied SSH network access; authorized escalated execution connected.
Router `stty` was unavailable, BusyBox `ip -br` was unsupported, and ash did
not expand `{overview,detailed}`; corrected checks used focused jsonfilter,
`ls /sys/class/net`, and explicit paths. An overlong interactive command was
truncated, leaving a grep filename ending in `.metr`; the focused retry
read the actual `.metrics` file successfully. Local `python.exe` was
inaccessible; temporary Node helpers generated and validated the JSON.
These helpers are removed after verification.

Backup and deployment, commands in execution order:

```sh
mkdir -p /tmp/monitoring-nic-before-20261004
cp /etc/phase3c/grafana/provisioning/dashboards/openwrt-overview.json /tmp/monitoring-nic-before-20261004/
cp /etc/phase3c/grafana/provisioning/dashboards/openwrt-detailed.json /tmp/monitoring-nic-before-20261004/
sha256sum /tmp/monitoring-nic-before-20261004/*.json
```

Both copies exited `0`. Backup hashes: Overview
`eb482dca7b812fd668bc7a20ebc200bd74846d28004d64e7fb2bbc1c1f57e484`,
Detailed `f0f6e50a774091f1cc26a32d35ce909f2a6b227a6d75ea347a5f0f2c7b68102b`.
The directory was copied to ignored `backups/monitoring-nic-before-20261004/`
using `rtk proxy cmd.exe /c "scp -O -r -i .local-ssh/id_ed25519_v2 -o BatchMode=yes root@192.168.1.1:/tmp/monitoring-nic-before-20261004 backups/"`, exit `0`.

Local JSON validation passed: Overview version `2`, Detailed version `10`.
The configuration diff adds `map-mape_auto` to Overview traffic and Detailed
traffic/packets/errors/drops/carrier. Physical speed and carrier-down events
select `eth0|eth1`. Exact-name display overrides label WAN / ONU, WAN IPv4 /
MAP-E, LAN port, and LAN bridge; descriptions warn against adding overlapping
paths. Metric names, collector scope, and performance calculation are unchanged.

```text
rtk proxy cmd.exe /c "scp -O -i .local-ssh/id_ed25519_v2 -o BatchMode=yes phase3c/grafana/provisioning/dashboards/openwrt-overview.json phase3c/grafana/provisioning/dashboards/openwrt-detailed.json root@192.168.1.1:/tmp/"
```

Upload exited `0`; persistent-session install and reload:

```sh
cp /tmp/openwrt-overview.json /etc/phase3c/grafana/provisioning/dashboards/openwrt-overview.json && cp /tmp/openwrt-detailed.json /etc/phase3c/grafana/provisioning/dashboards/openwrt-detailed.json
docker compose -f /etc/phase3c/compose.yml config --quiet
docker compose -f /etc/phase3c/compose.yml up -d --no-deps --force-recreate grafana
```

Install, Compose validation, and Grafana recreate each exited `0`; output
confirmed `phase3c-grafana-1 Started`. Prometheus/exporter were not restarted.
Post-install verification results follow below.

Verification commands, in execution order:

```text
rtk proxy node tools/verify-monitoring-nics.mjs
rtk proxy cmd.exe /c "scp -O -i .local-ssh/id_ed25519_v2 -o BatchMode=yes backups/monitoring-nic-20261004/query.sh root@192.168.1.1:/tmp/monitoring-nic-query.sh"
```

Both exited `0`. The temporary Node helper generated all 13 exact interface
expressions from the two dashboards. Persistent-session checks:

```sh
sh /tmp/monitoring-nic-query.sh
sha256sum /etc/phase3c/grafana/provisioning/dashboards/openwrt-overview.json /etc/phase3c/grafana/provisioning/dashboards/openwrt-detailed.json
curl -fsS http://192.168.1.1:3000/api/health
docker logs --since 5m phase3c-grafana-1 2>&1 | grep -E 'provisioning.dashboard|level=error'
netstat -lnt | grep -E ':3000|:9090|:9100'
```

The query script executes `curl -fsSG --data-urlencode 'query=<exact dashboard
expression>' http://127.0.0.1:9090/api/v1/query -o
/tmp/monitoring-nic-results-20261004/<dashboard>-<panel>-<refId>.json` for each
expression and prints each curl exit status; all 13 were `0`. Exact commands
are retained in ignored `backups/monitoring-nic-20261004/query.sh` (SHA-256
`1df640d1d5be4fbe1c45216c221e3496b4dbe24dc7e0b9ead77ea91b5f151ccf`),
with expressions in `queries.json` (SHA-256
`4de9e1c7d0e435be958e0804b046dc1606d25f4139db7a9f507efe3b798b4b15`).

Installed SHA-256 values match local files:

```text
Overview d2e0379f6e7965b045441cf9feb974e7089688c6feb3aaba8e8c9a35cff7826c
Detailed 90e7efc9f48ae31167a93c97d66e2d1ce7777a731bd602aa40fff9f1f6e3b599
```

Grafana health curl exit `0`, response `database=ok`, `version=13.2.1`.
Dashboard logs: `starting to provision dashboards`, then `finished to
provision dashboards`; log filter exit `0`. Logs also report absent optional
`/etc/grafana/provisioning/plugins` and `alerting` directories, separate from
successful dashboard provisioning; those unrelated categories were not changed.
Listener filter exit `0`:

```text
127.0.0.1:9090 LISTEN
127.0.0.1:9100 LISTEN
192.168.1.1:3000 LISTEN
```

Local retrieval and validation:

```text
rtk proxy cmd.exe /c "scp -O -r -i .local-ssh/id_ed25519_v2 -o BatchMode=yes root@192.168.1.1:/tmp/monitoring-nic-results-20261004 backups/monitoring-nic-20261004/results"
rtk proxy node tools/verify-monitoring-nics.mjs --check
rtk proxy cmd.exe /c "curl.exe -fsS --max-time 10 http://192.168.1.1:3000/api/health"
```

All exited `0`. Verification checks each response's success, exact expected
device set, and finite sample values. Relevant verbatim output:

```text
overview-3-A: PASS br-lan=33425.27407407408, eth0=1946508.5185185187, map-mape_auto=1427146.0555555555
overview-3-B: PASS br-lan=1466433.6074074074, eth0=51349.57037037037, map-mape_auto=33370.65185185185
detailed-11-A: PASS eth1=1000, eth0=1000
detailed-12-A: PASS eth1=1, eth0=1, br-lan=1, map-mape_auto=1
detailed-13-A: PASS eth0=1.0003473428273706, eth1=0
PASS: all 13 changed interface queries return expected devices and finite values
```

Detailed byte/packet rates returned all four selected devices; every selected
RX/TX error/drop rate was `0`. The carrier-down count is a rolling 24-hour
`increase`, not evidence of a new event during this dashboard change.
Complete validation output is ignored
`backups/monitoring-nic-20261004/validation.log`, SHA-256
`36ed25b8dfe76d30aa51def27916ff9bcde3105489a2b91f3a45c646d5f80f91`.
The temporary Node helpers are retained in the same ignored directory for
reproducibility. PC-side Grafana health also returned `database=ok`.

Verdict: PASS for deployed JSON, successful provisioning, all changed query
results, physical NIC speeds, LAN health access, and loopback monitoring
listeners. Browser rendering and behavior across a future reconnect/reboot
were not checked. Manuals/inventories now describe the observed direct-ONU
device mapping. Final local `rtk git diff --check` exited `0` (only Git
LF-to-CRLF warnings).

Rollback was not run. Restore the two saved JSON files from
`/tmp/monitoring-nic-before-20261004/` into
`/etc/phase3c/grafana/provisioning/dashboards/` and run
`docker compose -f /etc/phase3c/compose.yml up -d --no-deps --force-recreate grafana`.
After reboot, recover the backups from local
`backups/monitoring-nic-before-20261004/` with `scp -O`. No router network,
firewall, exporter, Prometheus, or vnStat rollback is needed for this change.

### 2026-10-04 JST - Rename WAN / ONU legend to WAN (executed)

Topology remains direct ONU -> DS57U `eth0`, LAN `eth1` / `br-lan`.
User requested the display-label substitution `WAN / ONU` -> `WAN`.
Both dashboard JSON files now show `WAN (eth0)` with the existing RX/TX,
error/drop suffixes. Versions increased to Overview `3`, Detailed `11`.
JSON parsing and comparison confirmed all query targets were preserved.

Commands in execution order (local commands use RTK; router commands were
run through one persistent SSH session):

```text
rtk git status --short
rtk proxy cmd.exe /c "ssh -tt -i .local-ssh/id_ed25519_v2 -o BatchMode=yes -o ConnectTimeout=10 root@192.168.1.1"
rtk proxy node backups/rename-wan-label-20261004.mjs
```

The ignored Node helper replaces the exact label, increments each version,
parses JSON, and compares old/new panel query targets. It exited `0`.

```sh
mkdir -p /tmp/monitoring-wan-label-before-20261004
cp /etc/phase3c/grafana/provisioning/dashboards/openwrt-overview.json /tmp/monitoring-wan-label-before-20261004/ && cp /etc/phase3c/grafana/provisioning/dashboards/openwrt-detailed.json /tmp/monitoring-wan-label-before-20261004/
sha256sum /tmp/monitoring-wan-label-before-20261004/*.json
```

Backup copy exit `0`; Overview hash
`d2e0379f6e7965b045441cf9feb974e7089688c6feb3aaba8e8c9a35cff7826c`, Detailed
`90e7efc9f48ae31167a93c97d66e2d1ce7777a731bd602aa40fff9f1f6e3b599`.

```text
rtk proxy cmd.exe /c "scp -O -i .local-ssh/id_ed25519_v2 -o BatchMode=yes phase3c/grafana/provisioning/dashboards/openwrt-overview.json phase3c/grafana/provisioning/dashboards/openwrt-detailed.json root@192.168.1.1:/tmp/"
```

Upload exit `0`; persistent-session deployment:

```sh
cp /tmp/openwrt-overview.json /etc/phase3c/grafana/provisioning/dashboards/openwrt-overview.json && cp /tmp/openwrt-detailed.json /etc/phase3c/grafana/provisioning/dashboards/openwrt-detailed.json
docker compose -f /etc/phase3c/compose.yml up -d --no-deps --force-recreate grafana
sha256sum /etc/phase3c/grafana/provisioning/dashboards/openwrt-overview.json /etc/phase3c/grafana/provisioning/dashboards/openwrt-detailed.json
```

Install and recreate each exited `0`, with `phase3c-grafana-1 Started`.
Installed hashes match local JSON:

```text
Overview 9bf4c8c5e865c3af4e7a82fe6f20b676f61b4833da932a3d8cd7a8e751cbc31b
Detailed 032caa3fda301e0f447919e7bd00aa6661346eaea5d49d63bf4b73e09c5e0f68
```

```text
rtk proxy cmd.exe /c "scp -O -r -i .local-ssh/id_ed25519_v2 -o BatchMode=yes root@192.168.1.1:/tmp/monitoring-wan-label-before-20261004 backups/"
rtk proxy cmd.exe /c "curl.exe -fsS --max-time 10 http://192.168.1.1:3000/api/health"
```

Both exited `0`; health response `database=ok`, `version=13.2.1`.
`docker logs --since 2m phase3c-grafana-1 2>&1 | grep 'provisioning.dashboard'`
returned `starting to provision dashboards` and `finished to provision
dashboards`, filter exit `0`. Final `rtk git diff --check` exited `0`.
No failed deployment or rollback occurred. Browser rendering was not checked.
Rollback, if needed: restore both JSON files from
`/tmp/monitoring-wan-label-before-20261004/` (or the matching local `backups/`
directory after reboot) and recreate only Grafana using the same command.

### 2026-10-04 JST - CPU/memory line graphs and traffic Mb/s (executed)

Topology remains ONU -> DS57U `eth0`, LAN `eth1` / `br-lan`, BUFFALO WAN
`192.168.1.2`. Only the Detailed Metrics dashboard and its inventory documents
changed. Baseline local `rtk git status --short` was clean.

Configuration diff: panel 1 title `CPU busy (5 minutes)` -> `CPU used`;
panels 1 and 3 changed from `stat` to `timeseries`, with `drawStyle=line`,
linear interpolation, line width 1, no fill, no points, no stacking, and
percentage scale 0–100. CPU retains its five-minute rate expression;
memory retains `100 * (1 - available / total)`. Interface traffic (panel 8)
and top-ten sampled traffic (panel 21) now use Grafana `unit=Mbps` and multiply
the byte-per-second expressions by `8 / 1000000`. Panel 21 retains its bar
style. Dashboard version increased from `11` to `12`.

Commands in execution order:

```text
rtk git status --short
rtk proxy cmd.exe /c "ssh -tt -i .local-ssh/id_ed25519_v2 -o BatchMode=yes -o ConnectTimeout=10 root@192.168.1.1"
rtk proxy node backups/update-graph-style-20261004.mjs
```

The ignored local helper updates only the four panels and version, parses
the resulting JSON, and generates the five exact Prometheus query checks.
Exit `0`: valid JSON, version `12`, local SHA-256
`6166f3c0355712f1c06d1ee9fec94d093fca580465e935a37318866f0458bc81`.
In the persistent router session:

```sh
cp /etc/phase3c/grafana/provisioning/dashboards/openwrt-detailed.json /tmp/openwrt-detailed.before-graph-style-20261004.json
sha256sum /tmp/openwrt-detailed.before-graph-style-20261004.json
```

Backup exit `0`, SHA-256
`032caa3fda301e0f447919e7bd00aa6661346eaea5d49d63bf4b73e09c5e0f68`.
Local staging, exit `0`:

```text
rtk proxy cmd.exe /c "scp -O -i .local-ssh/id_ed25519_v2 -o BatchMode=yes phase3c/grafana/provisioning/dashboards/openwrt-detailed.json backups/graph-style-query-20261004.sh root@192.168.1.1:/tmp/"
```

Persistent-session deployment and query checks:

```sh
cp /tmp/openwrt-detailed.json /etc/phase3c/grafana/provisioning/dashboards/openwrt-detailed.json
docker compose -f /etc/phase3c/compose.yml up -d --no-deps --force-recreate grafana
sh /tmp/graph-style-query-20261004.sh
sha256sum /etc/phase3c/grafana/provisioning/dashboards/openwrt-detailed.json
```

Copy and recreate each exited `0`, output `phase3c-grafana-1 Started`.
Installed SHA-256 matches the local hash above. The query script runs
`curl -fsSG --data-urlencode 'query=<exact panel expression>'
http://127.0.0.1:9090/api/v1/query -o
/tmp/graph-style-results-20261004/<panel>-<refId>.json`, then `jsonfilter`
for status, device labels, and values. Exact commands are retained in
ignored `backups/graph-style-query-20261004.sh`, SHA-256
`097cce473d0b989c5326c9c2b51375f976d67220388d8ed4fe417fcf405a3a1f`.
All five curl exits were `0`, all responses `success` and nonempty:

```text
1-A: CPU used = 2.785185185181305 percent
3-A: Memory used = 5.312115188950772 percent
8-A: RX Mb/s
  br-lan=0.14342394074074075
  eth0=8.938867585185186
  eth1=0.17302325925925927
  map-mape_auto=8.433317777777779
8-B: TX Mb/s
  br-lan=8.664169422222223
  eth0=0.2281302222222222
  eth1=8.691879644444445
  map-mape_auto=0.14299997037037038
21-A: sampled traffic Mb/s
  192.168.1.2=4.692720888888889
  192.168.1.157=0.047071822222222226
  192.168.1.1=0
```

Backup retrieval and PC-side health:

```text
rtk proxy cmd.exe /c "scp -O -i .local-ssh/id_ed25519_v2 -o BatchMode=yes root@192.168.1.1:/tmp/openwrt-detailed.before-graph-style-20261004.json backups/"
rtk proxy cmd.exe /c "curl.exe -fsS --max-time 10 http://192.168.1.1:3000/api/health"
```

Both exited `0`; health returned `database=ok`, `version=13.2.1`.
In the same router session,
`docker logs --since 3m phase3c-grafana-1 2>&1 | grep 'provisioning.dashboard'`
returned `starting to provision dashboards` followed by `finished to
provision dashboards`, filter exit `0`. SSH was then closed normally.
Local `rtk git diff --check` exited `0` (only LF-to-CRLF warnings).

Verdict: PASS for source JSON, deployment hash, five query responses,
dashboard provisioning, and Grafana health. Browser rendering was not checked.
No failed attempt or rollback occurred. Rollback, if needed: copy
`/tmp/openwrt-detailed.before-graph-style-20261004.json` over the installed
Detailed dashboard and recreate only Grafana with the same command. The
matching backup is also retained locally under ignored `backups/`.

### 2026-10-04 JST - Dedicated CPU and memory row (executed)

Topology remains direct ONU -> DS57U `eth0`, LAN `eth1` / `br-lan`.
User requested that only CPU used and Memory used share a row. Detailed
dashboard version `13` puts CPU at `{h:7,w:12,x:0,y:0}` and Memory at
`{h:7,w:12,x:12,y:0}`. Load and Available memory each occupy half the next
row (`y:7`); remaining panels moved down seven grid units. Panel queries,
styles, and units are preserved.

Commands in execution order:

```text
rtk git status --short
rtk proxy node backups/update-cpu-memory-row-20261004.mjs
rtk proxy cmd.exe /c "ssh -tt -i .local-ssh/id_ed25519_v2 -o BatchMode=yes -o ConnectTimeout=10 root@192.168.1.1"
```

Existing modifications from the previous graph-style update were preserved.
Ignored helper exit `0`: valid JSON, no panel overlap, only layout/version
changed. Router commands ran through one persistent session:

```sh
cp /etc/phase3c/grafana/provisioning/dashboards/openwrt-detailed.json /tmp/openwrt-detailed.before-cpu-memory-row-20261004.json
sha256sum /tmp/openwrt-detailed.before-cpu-memory-row-20261004.json
```

Backup exit `0`, SHA-256
`6166f3c0355712f1c06d1ee9fec94d093fca580465e935a37318866f0458bc81`.
Upload exit `0`:

```text
rtk proxy cmd.exe /c "scp -O -i .local-ssh/id_ed25519_v2 -o BatchMode=yes phase3c/grafana/provisioning/dashboards/openwrt-detailed.json root@192.168.1.1:/tmp/"
```

Persistent-session deployment:

```sh
cp /tmp/openwrt-detailed.json /etc/phase3c/grafana/provisioning/dashboards/openwrt-detailed.json
docker compose -f /etc/phase3c/compose.yml up -d --no-deps --force-recreate grafana
sha256sum /etc/phase3c/grafana/provisioning/dashboards/openwrt-detailed.json
```

Install and recreate exits `0`; `phase3c-grafana-1 Started`.
Installed/local SHA-256 match:
`ac8f2404c5f0c39efc066ec8426d31e797192b7c7ebd35c21e126d95e8aa51f6`.

```text
rtk proxy cmd.exe /c "curl.exe -fsS --max-time 10 http://192.168.1.1:3000/api/health"
rtk proxy cmd.exe /c "scp -O -i .local-ssh/id_ed25519_v2 -o BatchMode=yes root@192.168.1.1:/tmp/openwrt-detailed.before-cpu-memory-row-20261004.json backups/"
```

Both exit `0`; Grafana health `database=ok`, `version=13.2.1`.
`docker logs --since 2m phase3c-grafana-1 2>&1 | grep 'provisioning.dashboard'`
returned `starting to provision dashboards` and `finished to provision
dashboards`, filter exit `0`; SSH closed normally. Local
`rtk git diff --check` exited `0`. Inventory describes the dedicated row.

Verdict: PASS for layout validation, deployed hash, provisioning, and health.
Browser rendering was not checked; unchanged PromQL was not rerun.
No failures or rollback. Rollback if needed: restore the saved JSON from
`/tmp/openwrt-detailed.before-cpu-memory-row-20261004.json` (also copied to
local ignored `backups/`) and recreate only Grafana with the same command.

### 2026-10-12 JST - Current DHCP device inventory (read-only)

Topology and cable state: no cable changes. Observed `br-lan` is UP with
`192.168.1.1/24`. BUFFALO WAN is a reachable LAN neighbor; upstream cabling
and BUFFALO's downstream DHCP server were not inspected.
Baseline: current leases only; no configuration changes or backup required.

Connection: `rtk proxy cmd.exe /c "ssh -tt -i .local-ssh/id_ed25519_v2 -o BatchMode=yes -o ConnectTimeout=10 root@192.168.1.1"`.
The sandbox attempt exited `1` (`Permission denied`). The permitted retry
connected, but stdin was closed without `tty=true`; reconnected with
`tty=true` and reused that session for all router commands below.

Commands in execution order and observed results:

```text
date -u '+%Y-%m-%dT%H:%M:%SZ'; echo date_exit=$?
2026-10-11T16:49:18Z
date_exit=0

cat /tmp/dhcp.leases; echo leases_exit=$?
1791764890 68:e1:dc:37:1d:10 192.168.1.2 buffalo-wan 01:68:e1:dc:37:1d:10
leases_exit=0

ip -4 addr show br-lan; echo lan_exit=$?
5: br-lan: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP qlen 1000
    inet 192.168.1.1/24 brd 192.168.1.255 scope global br-lan
       valid_lft forever preferred_lft forever
lan_exit=0

ip neigh show dev br-lan; echo neighbors_exit=$?
Relevant IPv4 excerpt:
192.168.1.2 lladdr 68:e1:dc:37:1d:10 ref 1 used 0/0/0 probes 1 REACHABLE
192.168.1.239 used 0/0/0 probes 6 FAILED
192.168.1.157 used 0/0/0 probes 6 FAILED
neighbors_exit=0

uci show dhcp.buffalo_wan; echo reservation_exit=$?
dhcp.buffalo_wan=host
dhcp.buffalo_wan.name='buffalo-wan'
dhcp.buffalo_wan.mac='68:E1:DC:37:1D:10'
dhcp.buffalo_wan.ip='192.168.1.2'
reservation_exit=0

ubus -v list dhcp; echo dhcp_methods_exit=$?
Available methods: ipv6leases, ipv6ra, add_lease
dhcp_methods_exit=0

cat /tmp/hosts/odhcpd; echo ipv6_hosts_exit=$?
cat: can't open '/tmp/hosts/odhcpd': No such file or directory
ipv6_hosts_exit=1

ubus call dhcp ipv6leases; echo ipv6leases_exit=$?
ipv6leases_exit=0
```

The successful IPv6 response contained two bound/static entries on `br-lan`
for `buffalo-wan`, both with DUID `0003000168e1dc371d10`, IAID `-600367856`,
`accept-reconf=true`, and valid lifetime `5034` seconds:

| Assignment | Value | Assigned ID | Preferred lifetime | Valid lifetime |
|---|---|---|---|---|
| Address | `fd57:3a20:c1d6::2` | 2 | 2334 seconds | 5034 seconds |
| Delegated prefix | `fd57:3a20:c1d6:4::/62` | 4 | 2334 seconds | 5034 seconds |

Local expiry conversion (exit `0`):

```text
rtk proxy powershell -NoProfile -Command "[DateTimeOffset]::FromUnixTimeSeconds(1791764890).ToOffset([TimeSpan]::FromHours(9)).ToString('yyyy-MM-dd HH:mm:ss zzz')"
2026-10-12 09:28:10 +09:00
```

Verdict: one IPv4 DHCP lease at 2026-10-12 01:49:18 JST, with 7h 38m 52s
remaining at that snapshot. The configured reservation matches the lease,
and neighbor state was REACHABLE. The two IPv6 assignments belong to the
same device, not two additional devices. Failed neighbor entries are not
current DHCP leases. BUFFALO downstream clients and IPv6 SLAAC clients
cannot be enumerated from this DHCP lease snapshot.
No router settings changed; rollback not required. `exit` closed SSH with
exit `0`. Local `rtk git diff --check` passed with exit `0`.

### 2026-10-13 JST - Intermittent smartphone Internet investigation (read-only)

The user confirmed the incident window as **2026-10-12 09:00-09:30 JST**.
Router time at first capture was `2026-10-13T00:19:47+09:00`; the session
clock independently returned `2026-10-12 15:20:18 UTC`. No clock correction
was made. Diagnostics ran approximately 00:19-00:27 JST.

Topology and cable state: current IPv4 default is `map-mape_auto` on DS57U;
physical WAN `eth0` and LAN `eth1` have carrier 1 and speed 1000 Mbps.
BUFFALO WAN has the expected lease `192.168.1.2` /
`68:e1:dc:37:1d:10`; downstream route is
`192.168.11.0/24 via 192.168.1.2 dev br-lan`.
SSH was observed from `192.168.1.2`, consistent with access through BUFFALO.
No cables moved. Phone Wi-Fi association, model, settings, and simultaneous
impact on other clients were not confirmed.

Baseline/rollback: clean worktree at start. No UCI changes, service restarts,
firewall reloads, or reboots performed. No configuration backup was needed
for these read-only checks. Rollback not required or run.

#### Commands and collection failures

Local commands used `rtk`. Initial local heading search containing a pipe
failed because the wrapper passed it to a shell (`'history' is not recognized`,
exit 1); corrected with `rtk read docs/history/README.md`.
Another combined regex search failed with `'###' is not recognized`, exit 1;
corrected with `rtk proxy rg -n 2026-10 docs/history/phase3c-monitoring.md`.

Initial `rtk proxy ssh -tt -i ...` failed before SSH because `-i` was an
ambiguous PowerShell shim parameter. Corrected command:
`rtk proxy cmd.exe /c "ssh -tt -i .local-ssh/id_ed25519_v2 -o BatchMode=yes -o ConnectTimeout=10 root@192.168.1.1"`.
The sandbox attempt failed with `Permission denied`, exit 1; the same
read-only command succeeded with approved elevated network access.
One persistent SSH session was then used throughout.

Initial router commands, in order:

```sh
date -Iseconds; uptime; ubus call system board; ubus call network.interface.wan status; ubus call network.interface.wan6 status; ubus call network.interface.mape_auto status; ip -4 route; ip -6 route; cat /tmp/dhcp.leases; free; cat /proc/sys/net/netfilter/nf_conntrack_count /proc/sys/net/netfilter/nf_conntrack_max; ip -s link show eth0; ip -s link show eth1; logread | tail -n 180
```

The MAP-E status included a very large firewall array, so returned output was
truncated; it is not a complete baseline export. Subsequent queries were
bounded. An overlong submitted shell line was truncated inside a quoted
argument and left the continuation prompt; Ctrl-C cancelled it, and commands
were resubmitted individually below. `stty` is unavailable; `ip -s link` is
unsupported by this BusyBox build. Kernel sysfs counters replaced that check.

Executed follow-up command batches, in order (the `run` helper reports the
last command's exit status in a group; it does not prove every earlier
command in that group succeeded):



```sh
stty cols 240
run() { printf '\n$ %s\n' "$*"; sh -c "$*"; printf 'exit=%s\n' "$?"; }
run 'date -Iseconds; uptime; for n in wan wan6 mape_auto lan; do echo "$n"; ubus call network.interface.$n status | jsonfilter -e @.up -e @.uptime -e @.l3_device; done'
run 'ip -4 route; ip -6 route | head -n 12; free; cat /proc/sys/net/netfilter/nf_conntrack_count /proc/sys/net/netfilter/nf_conntrack_max'
run 'ip -s link show eth0; ip -s link show eth1; ip -s link show map-mape_auto; cat /tmp/dhcp.leases'
run 'logread | head -n 3; logread | grep -v "ra_lifetime to 0" | tail -n 45'
run 'dmesg | grep -Ei "oom|out of memory|watchdog|link is|reset|conntrack|error" | tail -n 25; uci show dhcp.lan; uci changes'
run 'curl -s --max-time 5 http://127.0.0.1:9090/api/v1/status/flags; ls -l /tmp/router* /opt/phase3c/performance /usr/local/sbin/router* 2>/dev/null'
run 'for n in eth0 eth1 map-mape_auto; do echo "$n"; for f in carrier speed statistics/rx_errors statistics/tx_errors statistics/rx_dropped statistics/tx_dropped; do printf "%s=" "$f"; cat /sys/class/net/$n/$f; done; done'
run 'ping -c 5 -W 2 192.168.1.2; ping -c 5 -W 2 192.168.11.1; ping -c 5 -W 2 1.1.1.1'
run 'nslookup example.com 127.0.0.1; curl -4 -I -sS --max-time 15 https://example.com; curl -6 -I -sS --max-time 15 https://example.com'
run 'cat /opt/phase3c/performance/latest; cat /etc/resolv.conf; cat /tmp/resolv.conf.d/resolv.conf.auto; ps | grep -E "dnsmasq|odhcp|ntpd"'
run 'logread | grep "Oct 12 09:"; logread | grep -Ei "netifd|oom|failed|timeout|dnsmasq.*(start|exit)|link.*down" | tail -n 20'
run 'curl -s --max-time 5 http://127.0.0.1:9100/metrics | grep -E "router_wan|node_network_carrier|node_nf_conntrack"'
run 'curl -s --max-time 5 http://127.0.0.1:9100/metrics | grep -E "probe|performance"'
```

Then these historical queries, each returning API `status=success` and curl
`rc=0`. The endpoint time is 09:30 JST; a 30-minute range selects samples
after 09:00 through 09:30.

```sh
curl -sS --max-time 8 -G http://127.0.0.1:9090/api/v1/query --data-urlencode 'query=min_over_time(router_wan_probe_success[30m])' --data-urlencode 'time=2026-10-12T00:30:00Z'; echo rc=$?
curl -sS --max-time 8 -G http://127.0.0.1:9090/api/v1/query --data-urlencode 'query=count_over_time(router_wan_probe_success[30m])' --data-urlencode 'time=2026-10-12T00:30:00Z'; echo rc=$?
curl -sS --max-time 8 -G http://127.0.0.1:9090/api/v1/query --data-urlencode 'query=max_over_time(router_wan_probe_packet_loss_ratio[30m])' --data-urlencode 'time=2026-10-12T00:30:00Z'; echo rc=$?
curl -sS --max-time 8 -G http://127.0.0.1:9090/api/v1/query --data-urlencode 'query=max_over_time(router_wan_probe_rtt_seconds[30m])' --data-urlencode 'time=2026-10-12T00:30:00Z'; echo rc=$?
curl -sS --max-time 8 -G http://127.0.0.1:9090/api/v1/query --data-urlencode 'query=min_over_time(up[30m])' --data-urlencode 'time=2026-10-12T00:30:00Z'; echo rc=$?
curl -sS --max-time 8 -G http://127.0.0.1:9090/api/v1/query --data-urlencode 'query=count_over_time(up[30m])' --data-urlencode 'time=2026-10-12T00:30:00Z'; echo rc=$?
curl -sS --max-time 8 -G http://127.0.0.1:9090/api/v1/query --data-urlencode 'query=changes(node_network_carrier_changes_total[30m])' --data-urlencode 'time=2026-10-12T00:30:00Z'; echo rc=$?
curl -sS --max-time 8 -G http://127.0.0.1:9090/api/v1/query --data-urlencode 'query=increase(node_network_transmit_errs_total[30m])' --data-urlencode 'time=2026-10-12T00:30:00Z'; echo rc=$?
curl -sS --max-time 8 -G http://127.0.0.1:9090/api/v1/query --data-urlencode 'query=max_over_time(node_nf_conntrack_entries[30m])' --data-urlencode 'time=2026-10-12T00:30:00Z'; echo rc=$?
curl -sS --max-time 8 -G http://127.0.0.1:9090/api/v1/query --data-urlencode 'query=max_over_time(node_load1[30m])' --data-urlencode 'time=2026-10-12T00:30:00Z'; echo rc=$?
curl -sS --max-time 8 -G http://127.0.0.1:9090/api/v1/query --data-urlencode 'query=min_over_time(node_memory_MemAvailable_bytes[30m])' --data-urlencode 'time=2026-10-12T00:30:00Z'; echo rc=$?
curl -sS --max-time 8 -G http://127.0.0.1:9090/api/v1/query --data-urlencode 'query={__name__=~"router_performance.*"}' --data-urlencode 'time=2026-10-12T00:30:00Z'; echo rc=$?
```

Then:

```sh
run 'curl -sS -I --max-time 5 http://192.168.11.1/; curl -sS -I --max-time 5 http://192.168.1.2/'
curl -sS --max-time 8 -G http://127.0.0.1:9090/api/v1/query --data-urlencode 'query=changes(node_boot_time_seconds[30m])' --data-urlencode 'time=2026-10-12T00:30:00Z'; echo rc=$?
curl -sS --max-time 8 -G http://127.0.0.1:9090/api/v1/query --data-urlencode 'query=increase(node_network_transmit_drop_total[30m])' --data-urlencode 'time=2026-10-12T00:30:00Z'; echo rc=$?
run 'fw4 check; cat /etc/crontabs/root; sha256sum /usr/local/sbin/router-performance-hourly; ubus call network.interface.wan6 status | jsonfilter -e @.ipv6-prefix; ubus call dhcp ipv6leases'
run 'fw4 check 2>&1 | tail -n 2; nft list chain inet fw4 mape_auto_icmp_snat; cat /etc/nftables.d/mape-auto-icmp.nft'
ubus call network.interface.wan6 status | jsonfilter -e '@["ipv6-prefix"]'; echo rc=$?
sha256sum /usr/local/sbin/router-performance-hourly
run 'nft list ruleset | grep -E "icmp|mape" | head -n 20; find /etc /usr/share/nftables.d -name "*mape*" 2>/dev/null'
exit
```

Other corrected failures: the initially assumed
`phase3c/wan-probe/router-wan-probe.sh` does not exist; inspected the actual
Lua collector instead. `jsonfilter -e @.ipv6-prefix` failed parsing the hyphen;
the quoted expression `@["ipv6-prefix"]` succeeded and returned `[ ]`.
Guessed chain `mape_auto_icmp_snat` and path
`/etc/nftables.d/mape-auto-icmp.nft` were absent (group exit 1).
The subsequent ruleset/path discovery found the installed ICMP SNAT rule
and `/etc/mape-auto-icmp.nft`; these failed guesses are not evidence of an
absent working rule.

#### Historical results: October 12, 09:00-09:30 JST

All historical vectors carried `instance=127.0.0.1:9100`, `job=openwrt`,
evaluation timestamp `1791765000`. Relevant returned values:

| Query | Observed value |
|---|---|
| min_over_time(router_wan_probe_success[30m]) | 1 |
| count_over_time(router_wan_probe_success[30m]) | 60 |
| max_over_time(router_wan_probe_packet_loss_ratio[30m]) | 0 |
| max_over_time(router_wan_probe_rtt_seconds[30m]) | 0.006553 seconds |
| min_over_time(up[30m]) | 1 |
| count_over_time(up[30m]) | 60 |
| changes(node_network_carrier_changes_total[30m]) | 0 for eth0, eth1, br-lan, map-mape_auto and lo |
| increase(node_network_transmit_errs_total[30m]) | 0 for all returned devices, including map-mape_auto |
| increase(node_network_transmit_drop_total[30m]) | 0 for all returned devices |
| changes(node_boot_time_seconds[30m]) | 0 |
| max_over_time(node_nf_conntrack_entries[30m]) | 425 |
| max_over_time(node_load1[30m]) | 0.2 |
| min_over_time(node_memory_MemAvailable_bytes[30m]) | 7702056960 bytes |

The repository collector confirms each WAN sample is a router-originated
three-packet ping to `1.1.1.1`; success means at least one reply.
The separate packet-loss metric was zero for every observed sample.
These 30-second samples do not establish continuous coverage between probes,
historical DNS/HTTPS success, or connectivity from the phone.

Historical performance values at 09:30:

```text
router_performance_last_run_timestamp_seconds 1791763200  # 09:00 JST
router_performance_run_success 1
router_performance_download_valid 1
router_performance_upload_valid 1
router_performance_download_valid_samples 3
router_performance_upload_valid_samples 3
router_performance_download_aggregate_mbps 674.157
router_performance_upload_aggregate_mbps 560.748
router_performance_download_single_mbps 227.384
router_performance_upload_single_mbps 253.389
```

Cron is `0 * * * * /usr/local/sbin/router-performance-hourly`.
The installed script SHA-256 matches the repository file:
`4c028561a0bda923bcb84c07ed7c70df57a20affa96f7a3270a42a34251ec6d6`.
It performs three parallel 25 MB downloads followed by three parallel 25 MB
uploads. A traffic burst at 09:00 is confirmed; interference with the phone
is a hypothesis, not an observed cause. The `cron.err ... USER root ... cmd`
line itself contains no job failure result; the saved metrics show this run
succeeded.

Retained syslog begins October 10 at 00:07:52. Relevant verbatim lines
(line wrapping removed for readability):

```text
Mon Oct 12 08:38:13 2026 daemon.info dnsmasq-dhcp[1]: DHCPREQUEST(br-lan) 192.168.1.2 68:e1:dc:37:1d:10
Mon Oct 12 08:38:13 2026 daemon.info dnsmasq-dhcp[1]: DHCPACK(br-lan) 192.168.1.2 68:e1:dc:37:1d:10 buffalo-wan
Mon Oct 12 09:00:00 2026 cron.err crond[2220]: USER root pid 19667 cmd /usr/local/sbin/router-performance-hourly
Mon Oct 12 09:02:48 2026 daemon.warn odhcpd[2156]: A default route is present but there is no public prefix on lan thus we announce no default route by setting ra_lifetime to 0!
Mon Oct 12 09:10:45 2026 daemon.warn odhcpd[2156]: A default route is present but there is no public prefix on lan thus we announce no default route by setting ra_lifetime to 0!
Mon Oct 12 09:18:08 2026 daemon.warn odhcpd[2156]: A default route is present but there is no public prefix on lan thus we announce no default route by setting ra_lifetime to 0!
Mon Oct 12 09:24:51 2026 daemon.warn odhcpd[2156]: A default route is present but there is no public prefix on lan thus we announce no default route by setting ra_lifetime to 0!
```

Warnings recur throughout the retained days, including after the reported
recovery. No retained netifd down event, timeout, DNS process restart,
out-of-memory event, or failed lease acquisition matched the bounded searches.
Kernel link changes exist earlier in the boot; the latest retained WAN
link-up was at uptime 434340.538419 seconds, much earlier than the incident
(current uptime about 1206322 seconds).

#### Current results and verification limits

- Router uptime approximately 13 days 23 hours. `wan` DHCP is pending/down;
  `wan6` and `mape_auto` are up, with roughly 8.9 days uptime. IPv4 uses
  MAP-E, so the raw DHCP `wan` status alone does not demonstrate an outage.
- Memory available: 7570832 KiB. Conntrack 302 of 262144 in the baseline.
- Physical eth0/eth1 RX/TX errors zero; eth0 cumulative TX drops 13,
  eth1 drops zero. MAP-E cumulative TX errors/drops 494 each, but no
  increments occurred in the incident window. Virtual tunnel speed
  is unsupported (`Invalid argument`), not a physical link-speed failure.
- Pings to BUFFALO WAN, BUFFALO LAN gateway, and 1.1.1.1 each returned 5/5,
  zero loss. Internet average RTT 5.029 ms.
- `nslookup example.com 127.0.0.1` returned A and AAAA records.
  IPv4 and IPv6 router-originated HTTPS HEAD each returned HTTP/2 200;
  the group exit was 0. This proves current router DNS and both WAN families,
  not historical DNS or downstream-phone IPv6.
- Upstream `wan6` has no delegated public IPv6 prefix. LAN DHCPv6/RA are
  configured as servers. BUFFALO has bound ULA address `fd57:3a20:c1d6::2`
  and ULA delegated prefix `fd57:3a20:c1d6:4::/62`, with valid lifetime 4889
  seconds at capture. The LAN IPv6 warning explicitly reports withholding
  an IPv6 default route; it does not establish a transient IPv4 outage.
  Public IPv6 from BUFFALO clients remains unverified.
- `fw4 check` printed `Ruleset passes nftables check.` It also warned that
  generated MAP ICMP entries specifying ports without UDP/TCP were ignored.
  A live custom ICMP echo-request SNAT rule was observed with nonzero counter,
  comment `mape-auto ICMP identifiers`. Router IPv4 ping works.
  The grouped check does not preserve the individual fw4 exit code.
- HTTP HEAD to both BUFFALO addresses timed out (curl 28 each, group exit 28).
  Both addresses answered ping. This does not prove BUFFALO administration
  or forwarding failed; no authenticated BUFFALO logs or Wi-Fi client data
  were accessible in this investigation.
- `uci changes` returned no pending changes. SSH `exit` closed the session.

Verdict: no observed OpenWrt WAN outage, link flap, reboot, resource exhaustion,
or growing tunnel TX errors during the confirmed 30-minute window.
IPv6 LAN limitations and the 09:00 scheduled traffic burst are recorded
findings, neither established as the smartphone's cause. Root cause remains
unresolved without BUFFALO/phone evidence. During a recurrence, identify the
phone's IP/gateway and test BUFFALO gateway reachability, public IPv4, and DNS;
obtain BUFFALO Wi-Fi/system logs for the exact incident time. These follow-up
checks are planned and were not run.

Ignored captured transcript (PTY artifacts retained; some returned outputs
were truncated, not a complete log export):
`backups/2026-10-13-phone-outage/captured-transcript.txt`,
SHA-256 `c6f522d33e5270d7edcf359fff412607ef7d5b029c0bb75a65b7c1e2676428fe`.
Live MAP/WAN identifiers and SSH fingerprint were redacted in the saved
transcript. Relevant bounded results are recorded above.

Local documentation validation: initial `rtk git diff --check` found a new
blank line at EOF (exit 1). The trailing blank line was removed; the retest
passed with exit 0 (only the repository's LF-to-CRLF warning).
No rebuild procedure changed.
