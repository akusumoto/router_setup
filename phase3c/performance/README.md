# Hourly OpenWrt Performance Monitor

The router runs `/usr/local/sbin/router-performance-hourly` at minute zero of
every hour through `/etc/crontabs/root`. It performs three concurrent
25,000,000-byte Cloudflare downloads, then three concurrent 25,000,000-byte
synthetic-zero uploads from the OpenWrt router itself. This is 150 MB per run,
approximately 3.6 GB per day.

A direction is valid only when `curl` exits successfully, the HTTP status is
`200`, and the transferred byte count is exactly `25,000,000`. A direction is
valid only if all three transfers pass. For downloads, **Internet performance**
is the total bytes received by all three flows at the instant the first flow
completes, divided by elapsed time since the three downloads started. It writes
the three response bodies temporarily under `/tmp` (at most 75 MB) solely to
sample the two incomplete flows, then removes them. Upload uses the same
first-completion snapshot: a completed flow contributes its exact 25 MB, while
each still-running flow contributes completed 1 MB blocks from its FIFO-fed
upload stream. A block is counted only after it has passed from the `/dev/zero`
producer into curl, so the snapshot is accurate within 1 MB per active flow.
**Internet performance (single)** is
the fastest individual flow. Both
are stored in decimal Mb/s at `/opt/phase3c/performance/latest`.
The job uses a non-blocking lock, so an hourly run is skipped if a prior run is
still active. Failed directions emit a validity value of `0` and no throughput
value; Grafana therefore shows both the failure state and a gap rather than
stale throughput.

`router-performance.lua` is loaded by the existing loopback-only Lua exporter.
It adds `router_performance_*` gauges without adding a listener. Prometheus
scrapes them through the existing `127.0.0.1:9100` target, and the **OpenWrt
Performance** Grafana dashboard displays throughput and validity.

The provisioned dashboard uses a time-series line with points and a latest-value
gauge. Read the checked-in dashboard JSON for the exact query/reduction and
display settings; previous bar-chart experiments are retained in the
[Phase 3C execution history](../../docs/history/phase3c-monitoring.md).

This measures the actual OpenWrt-to-Internet path at execution time. Record
whether it traverses BUFFALO or direct ONU. It is an hourly indicator, not a line-rate certification or
a comparison with the BUFFALO route. Roll back by removing the cron line, the
script, collector, state directory, and provisioned dashboard, then restarting
cron, the exporter, and Grafana as applicable.
