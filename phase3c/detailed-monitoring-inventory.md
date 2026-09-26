# Detailed Prometheus and Grafana Metrics

The `OpenWrt Detailed Metrics` dashboard displays every operational metric
family emitted by the currently installed OpenWrt Lua exporter: CPU busy and
load, memory usage/availability, conntrack utilization, process state, uptime,
RX/TX bytes and packet rates, interface errors/drops, carrier, link speed in
Mb/s,
carrier-down events, file-descriptor utilization, entropy, exporter collector
success, and Prometheus scrape health. The monitored interfaces are `eth0`,
`eth1`, and `br-lan`; bridge and member traffic may overlap and must not be
added together.

The separate `OpenWrt Performance` dashboard displays hourly three-parallel-flow
aggregate and fastest-single download/upload results (`router_performance_*`)
and their HTTP-200/exact-byte-count validity. Its active measurement consumes
about 150 MB per hour and is documented in `phase3c/performance/README.md`.

The exporter does not emit filesystem capacity, thermal/fan, DHCP lease,
firewall-rule, routing/MAP-E, Wi-Fi, or active latency/loss/throughput metrics.
The DS57U has thermal zones, but their readings are not currently exported.
Those categories require a separately reviewed collector/probe design covering
privacy, labels, probe rate/targets, package/storage impact, failure semantics,
and rollback. This dashboard does not collect packet payloads, DNS queries,
client identities, or per-flow logs.
