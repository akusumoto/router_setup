# Phase 3C Monitoring and Visualization Inventory

This document defines the implemented Phase 3C monitoring scope. It separates
the metrics retained by Prometheus from the panels currently configured in
Grafana. It does not imply packet, DNS, client-identity, or per-flow
collection.

| Prometheus monitoring item | Source and sampling | Grafana visualization |
|---|---|---|
| One-minute router load average (`node_load1`) | OpenWrt exporter at `127.0.0.1:9100`; Prometheus scrape every 30 seconds | **Load (1 minute)** stat panel |
| Available RAM (`node_memory_MemAvailable_bytes`) | Same exporter and 30-second scrape | **Available memory** stat panel, displayed in bytes |
| Cumulative received bytes for WAN `eth0` and LAN bridge `br-lan` (`node_network_receive_bytes_total`) | Same exporter and 30-second scrape | **WAN and LAN traffic** time series: 5-minute receive-rate (`RX`) in bytes/sec for both interfaces |
| Cumulative transmitted bytes for WAN `eth0` and LAN bridge `br-lan` (`node_network_transmit_bytes_total`) | Same exporter and 30-second scrape | **WAN and LAN traffic** time series: 5-minute transmit-rate (`TX`) in bytes/sec for both interfaces |

Prometheus retains this time-series data for up to 15 days or 2 GiB, whichever
limit is reached first. The `OpenWrt Overview` dashboard contains exactly the
three panels named above; Grafana does not currently visualize any additional
exporter metrics.
