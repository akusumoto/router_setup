# Detailed Prometheus and Grafana Metrics

The `OpenWrt Detailed Metrics` dashboard displays every operational metric
family emitted by the currently installed OpenWrt Lua exporter: CPU busy and
load, memory usage/availability, conntrack utilization, process state, uptime,
RX/TX bytes and packet rates, interface errors/drops, carrier, link speed in
Mb/s,
carrier-down events, file-descriptor utilization, entropy, exporter collector
success, Prometheus scrape health, the count of active IPv4 LAN devices, and
the current number of active conntrack entries (tracked network flows through
the router, not distinct devices or application sessions). It does not emit
per-application connection counts: conntrack has network-flow metadata rather
than reliable application identities, and encrypted traffic prevents safe,
accurate application classification without a separately reviewed DPI design.
The active-device collector sends one bounded ARP probe to each DHCP lease and
current or remembered IPv4 neighbor address, then counts unique MAC addresses
that reply. It measures direct, responsive IPv4 LAN presence; it intentionally
excludes IPv6-only devices and clients with neither a DHCP lease nor a
remembered IPv4 neighbor address. The monitored interfaces are `eth0`,
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
