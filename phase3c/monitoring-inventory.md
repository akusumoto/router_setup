# Phase 3C Monitoring and Visualization Inventory

This document defines the implemented Phase 3C monitoring scope. Prometheus
scrapes the OpenWrt exporter at `127.0.0.1:9100` every 30 seconds and retains
the resulting time series for up to 15 days or 2 GiB, whichever limit is
reached first. The exporter and Prometheus remain loopback-only; Grafana is
available only at `192.168.1.1:3000` on the LAN.

## Grafana dashboards

| Dashboard | Scope |
|---|---|
| **OpenWrt Overview** | Original concise view: one-minute load, available memory, and WAN/LAN bridge receive/transmit traffic rates. |
| **OpenWrt Detailed Metrics** | Full operational view of every useful metric family currently emitted by the installed Lua exporter. |
| **OpenWrt Performance** | Hourly OpenWrt-originated aggregate and fastest-single download/upload results; the bar chart shows only measurement-time samples, while the gauge shows the latest values. |

## Retained metrics and detailed visualization

| Area | Prometheus metric families | Detailed dashboard visualization |
|---|---|---|
| CPU and scheduler | `node_cpu_seconds_total`, `node_load1`, `node_load5`, `node_load15`, `node_procs_running_total`, `node_procs_blocked_total` | Five-minute CPU busy, load averages, running and blocked process counts |
| Memory | `node_memory_MemTotal_bytes`, `node_memory_MemAvailable_bytes`, and detailed `/proc/meminfo` values | Used-memory percentage and available memory |
| Connection tracking | `node_nf_conntrack_entries`, `node_nf_conntrack_entries_limit` | Conntrack-table utilization percentage |
| Router lifetime and resources | `node_boot_time_seconds`, `node_filefd_allocated`, `node_filefd_maximum`, `node_entropy_available_bits` | Uptime, file-descriptor utilization, and available entropy |
| Link state | `node_network_carrier`, `node_network_speed_bytes`, `node_network_carrier_down_changes_total` | Carrier state, negotiated interface speed in Mb/s, and 24-hour carrier-down events |
| Interface traffic | `node_network_receive_bytes_total`, `node_network_transmit_bytes_total`, `node_network_receive_packets_total`, `node_network_transmit_packets_total` | Five-minute RX/TX byte and packet rates |
| Interface quality | `node_network_receive_errs_total`, `node_network_transmit_errs_total`, `node_network_receive_drop_total`, `node_network_transmit_drop_total` | Five-minute error and drop rates |
| Monitoring health | `node_scrape_collector_success`, Prometheus `up{job="openwrt"}` | Minimum collector-success value and Prometheus scrape health (1 = healthy) |
| Hourly Internet performance | Aggregate and fastest-single `router_performance_*_mbps`, per-direction valid-sample counts, validity, and last-run gauges | Three concurrent 25 MB downloads, then three concurrent 25 MB uploads each hour; aggregate rate is total valid bytes divided by the longest flow time, and a direction requires three curl-success/HTTP-200/exact-byte transfers |
| Router identity and clock | `node_openwrt_info`, `node_os_info`, `node_uname_info`, `node_time_seconds` | Retained for query/debugging; static identity values do not have a primary panel |

The monitored interfaces are WAN `eth0`, LAN port `eth1`, and LAN bridge
`br-lan`. `br-lan` and `eth1` describe overlapping paths, so their traffic
must not be added together as a total.

## Deliberately not collected

The installed exporter does not emit filesystem capacity, thermal/fan values,
DHCP leases, firewall-rule counters, routing/MAP-E state, Wi-Fi state, or active
latency/loss/throughput probes. The DS57U has thermal zones, but their values
are not yet exported. These categories require a separately reviewed collector
or probe design that defines labels/privacy, probe targets and rate, resource
impact, failure semantics, retention, and rollback.

No Phase 3C dashboard or metric collection includes packet payloads, DNS
queries, client identities, or per-flow logs.
