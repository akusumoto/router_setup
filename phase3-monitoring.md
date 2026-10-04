# Phase 3 - Monitoring Rebuild Manual

Execution evidence: [Phase 3A/3B](docs/history/phase3-monitoring.md),
[router-agent](docs/history/router-agent.md), [Phase 3C](docs/history/phase3c-monitoring.md).

## 1. Policy and prerequisites

Install in slices: local counters/vnStat, the one-shot router-agent, then the
Lua exporter and Prometheus/Grafana. Monitoring can be prepared behind BUFFALO.
Record the actual topology; monitoring does not establish MAP-E acceptance.
Keep LAN management at `192.168.1.1` and use one persistent SSH session.

Before changes, create a fresh sysupgrade backup, copy it with `scp -O`, and
match router/PC SHA-256 as in [Phase 2 preparation](phase2-setup.md#32-backups-free-space-packages).
Complete [storage expansion](storage-expansion.md) before the container stack.
Check free storage, RAM, listeners, and WAN input policy. Do not run `apk upgrade`.

Exporter and Prometheus bind only to `127.0.0.1:9100` and `127.0.0.1:9090`.
Grafana alone binds to LAN `192.168.1.1:3000`. Retain WAN input rejection.
See [inventory](phase3c/monitoring-inventory.md) and
[detailed metrics](phase3c/detailed-monitoring-inventory.md) for scope, units,
privacy limits, and unsupported categories.

## 2. Phase 3A - Local counters and vnStat

```sh
date -Iseconds
df -h /
conntrack -C
uptime
free
for n in eth0 eth1; do
  for k in rx_bytes tx_bytes rx_errors tx_errors rx_dropped tx_dropped; do
    printf '%s %s=' "$n" "$k"
    cat "/sys/class/net/$n/statistics/$k"
  done
done
apk info -e vnstat
```

An absent vnStat package exits `1`. BusyBox `ip` on this build lacks `ip -s`;
use sysfs above. After the verified backup:

```sh
apk update
apk search vnstat
apk add vnstat
/etc/init.d/vnstat enable
/etc/init.d/vnstat start
/etc/init.d/vnstat enabled; echo ENABLED_EXIT=$?
/etc/init.d/vnstat status
vnstat --iflist
vnstat --oneline
```

Require a running service and intended interfaces. After normal traffic and a
database update interval, repeat `vnstat --oneline` and check counter movement.
These snapshots do not certify throughput. To stop collection, disable and
stop vnStat; retain its database before package removal.

## 3. Phase 3B - Router-agent

Follow the [canonical specification](router-agent/SPEC.md) for static musl
build, deployment, runtime checks, and rollback. The agent remains a one-shot,
read-only JSON CLI with no listener, daemon, MCP, shell execution, or forwarding
control. Match PC/router binary hashes and apply `chmod 0755` after SCP.

## 4. Phase 3C - Exporter and container stack

Use [compose.yml](phase3c/compose.yml), [daemon.json](phase3c/daemon.json),
[prometheus.yml](phase3c/prometheus.yml), and `phase3c/grafana/provisioning/`.
The checked-in stack pins Prometheus `v3.14.0` and Grafana `13.2.1`, with
30-second scrapes and retention limited to 15 days or 2 GiB.
Recheck compatibility for a different OS release.

### 4.1 Packages and configuration

After backup and capacity checks, on the router:

```sh
apk update
apk add --simulate dockerd docker docker-compose prometheus-node-exporter-lua prometheus-node-exporter-lua-openwrt
apk add dockerd docker docker-compose prometheus-node-exporter-lua prometheus-node-exporter-lua-openwrt
mkdir -p /opt/docker /opt/phase3c/prometheus /opt/phase3c/grafana /etc/phase3c /etc/docker
```

From the repository root on the PC:

```powershell
rtk proxy scp -O -r -i .local-ssh/id_ed25519_v2 -o BatchMode=yes phase3c root@192.168.1.1:/etc/
```

On the router:

```sh
dockerd --validate --config-file=/etc/phase3c/daemon.json
cp /etc/phase3c/daemon.json /etc/docker/daemon.json
uci set dockerd.globals.alt_config_file='/etc/docker/daemon.json'
uci commit dockerd
/etc/init.d/dockerd enable
/etc/init.d/dockerd restart
docker info --format '{{.DockerRootDir}} {{.Driver}}'
uci show prometheus-node-exporter-lua
```

Require Docker `/opt/docker overlay2`. Alternate Docker configuration replaces
generated UCI settings; retain both physical `data-root=/opt/docker` and the
checked-in classic image-store setting. The recorded `/var -> /tmp` layout
caused runc's `invalid rootfs` failure with `/var/lib/docker`.
Require exporter `main.listen_interface='loopback'` and `main.listen_port='9100'`;
if different, set/commit those options before restarting:

```sh
/etc/init.d/prometheus-node-exporter-lua enable
/etc/init.d/prometheus-node-exporter-lua restart
wget -qO /tmp/phase3c-metrics http://127.0.0.1:9100/metrics
netstat -lnt
```

Require metrics and loopback 9100. Endpoint reachability alone does not prove
collector success; inspect `node_scrape_collector_success` too.

### 4.2 Secret, ownership, and provisioning

For a new empty Grafana database, create its secret only on the router:

```sh
umask 077
test ! -e /etc/phase3c/grafana.env || exit 1
printf 'GF_SECURITY_ADMIN_PASSWORD=%s\n' "$(head -c 32 /dev/urandom | md5sum | cut -d ' ' -f 1)" > /etc/phase3c/grafana.env
chmod 0600 /etc/phase3c/grafana.env
chmod 0755 /etc/phase3c/grafana /etc/phase3c/grafana/provisioning /etc/phase3c/grafana/provisioning/dashboards /etc/phase3c/grafana/provisioning/datasources
chmod 0644 /etc/phase3c/grafana/provisioning/dashboards/* /etc/phase3c/grafana/provisioning/datasources/*
docker compose -f /etc/phase3c/compose.yml config --quiet
docker compose -f /etc/phase3c/compose.yml pull
```

Never print or commit the credential. This environment value initializes a new
database; it does not reset a restored admin account. Provisioning directories
must be traversable by Grafana's non-root user. Inspect the pinned containers'
runtime UID/GID and make each `/opt/phase3c` data directory writable by its
service user before startup; record actual ownership commands in history.
Ownership verification is a rebuild prerequisite, not an already recorded test.

### 4.3 Start and acceptance

```sh
docker compose -f /etc/phase3c/compose.yml up -d --pull=never
docker compose -f /etc/phase3c/compose.yml ps
netstat -lnt
wget -qO- http://127.0.0.1:9090/api/v1/targets
wget -qO- http://192.168.1.1:3000/api/health
```

After a scrape interval, require target `openwrt` health `up`, no scrape error,
and Grafana database `ok`. Monitoring binds must be loopback 9100/9090 and LAN
3000 only. Log in from a LAN browser at `http://192.168.1.1:3000` and verify
all three provisioned dashboards, the data source, and panel data. Service
health does not establish authenticated browser or smartphone use.

### 4.4 Custom collectors and hourly performance

```sh
cp /etc/phase3c/connected-devices/router-connected-devices.lua /usr/lib/lua/prometheus-collectors/router_connected_devices.lua
cp /etc/phase3c/device-usage/router-device-usage.lua /usr/lib/lua/prometheus-collectors/router_device_usage.lua
cp /etc/phase3c/wan-probe/router-wan-probe.lua /usr/lib/lua/prometheus-collectors/router_wan_probe.lua
cp /etc/phase3c/performance/router-performance.lua /usr/lib/lua/prometheus-collectors/router_performance.lua
command -v arping
sysctl -n net.netfilter.nf_conntrack_acct
```

Require `arping` for active-device probes and accounting `1` for per-device
bytes; resolve missing prerequisites and record changes before claiming success.
Enabling accounting does not add byte counters retroactively to existing flows.
Restart the exporter and verify each custom family and collector success.
Device state `/tmp/router_device_usage.state` is lost on reboot. Sampling misses
flows entirely between scrapes. Downstream BUFFALO clients appear as its WAN
IPv4 through NAT, not as separate directly connected DS57U devices.

Install the active hourly test:

```sh
mkdir -p /usr/local/sbin /opt/phase3c/performance
cp /etc/phase3c/performance/router-performance-hourly.sh /usr/local/sbin/router-performance-hourly
chmod 0755 /usr/local/sbin/router-performance-hourly
grep -Fqx '0 * * * * /usr/local/sbin/router-performance-hourly' /etc/crontabs/root || cat /etc/phase3c/performance/root.crontab >> /etc/crontabs/root
/etc/init.d/cron enable
/etc/init.d/cron restart
/etc/init.d/prometheus-node-exporter-lua restart
```

Preserve other cron entries and ensure the existing file ends with a newline
before appending. The [monitor contract](phase3c/performance/README.md) documents
150 MB/run, calculation, validity, and rollback. Run the script once to validate
installation, then inspect `/opt/phase3c/performance/latest`, metrics, and panels.
Copying source does not establish that a scheduled run completes.

## 5. Rollback and migration

Record each rebuild's acceptance checklist in history: backup, vnStat movement,
router-agent runtime, Docker root, listeners, collector success, scrape health,
authenticated dashboards, hourly completion, and routing. Verify recovery after
reboot separately; historical installation checks do not replace it.

Stop containers with `docker compose -f /etc/phase3c/compose.yml down`; retain
`/opt/phase3c` data if needed. Restore saved configs/collectors and restart
affected services. Remove the hourly cron entry before removing its script.
Package removal, Docker networking, credentials, and data deletion are separate
recovery actions; review backups/diffs before restoring router settings.

Migration data is `/etc/phase3c` configuration plus `/opt/phase3c` time series
and Grafana data; `/opt/docker` is disposable cache. Provision the destination
credential, validate scrape/dashboard and binds, then stop the old stack.
