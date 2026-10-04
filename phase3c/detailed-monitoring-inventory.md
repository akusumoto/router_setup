# Detailed Prometheus and Grafana Metrics

The `OpenWrt Detailed Metrics` dashboard displays every operational metric
family emitted by the currently installed OpenWrt Lua exporter: CPU busy and
load, memory usage/availability, conntrack utilization, process state, uptime,
RX/TX bytes and packet rates, interface errors/drops, carrier, link speed in
Mb/s,
carrier-down events, file-descriptor utilization, entropy, exporter collector
success, Prometheus scrape health, the count of active IPv4 LAN devices, and
the current number of active conntrack entries (tracked network flows through
the router, not distinct devices or application sessions). It also displays the
top ten LAN IPv4 addresses by sampled traffic rate and active conntrack-flow
count. Per-application connection counts are not emitted: conntrack has
network-flow metadata rather than reliable application identities, and encrypted
traffic prevents safe, accurate application classification without a separately
reviewed DPI design.
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
about 150 MB per hour and is documented in the
[performance monitor contract](performance/README.md).

The detailed dashboard also plots router-originated ICMP average RTT and packet
loss to the fixed public target `1.1.1.1`. The Lua collector sends three packets
with a one-second timeout during each 30-second scrape. `router_wan_probe_success`
is `1` when at least one reply arrives, packet-loss ratio is `0` through `1`,
and RTT is absent when no reply supplies an average. This distinguishes a
complete probe failure from a zero-millisecond measurement. It is evidence of
reachability and latency to that one target only; it does not identify an
application, a client, a Wi-Fi condition, or certified available bandwidth.

The exporter does not emit filesystem capacity, thermal/fan, DHCP lease,
firewall-rule, routing/MAP-E, Wi-Fi, or active throughput metrics. The DS57U
has thermal-zone directories, but no readable temperature files were present
during the 2026-09-28 compatibility check. Those categories require separately
reviewed collector/probe designs covering privacy, labels, probe rate/targets,
package/storage impact, failure semantics, and rollback. At the user's explicit
request, the per-device metrics retain the LAN IPv4 address as a Prometheus
label; they do not collect names, MAC addresses, packet payloads, DNS queries,
remote destinations, ports, application labels, or per-flow logs.
