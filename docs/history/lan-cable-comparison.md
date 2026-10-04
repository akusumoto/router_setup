# PC-to-router LAN Cable Comparison - Execution History

Test procedure: [performance test plan](../../network-performance-test-plan.md).

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

## 10. Detailed exporter dashboard
