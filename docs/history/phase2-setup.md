# phase2-setup - Execution History

Manual: [rebuild procedure](../../phase2-setup.md).

These are dated records, including failures, corrections, retests, and unrun plans retained as historical context. Addresses, hashes, checklists, and statements of current state apply to the recorded session only. Use the manual for a new rebuild; append new execution evidence here. Original section numbers are retained for references within the records.

## 9. Implementation Log Template

Phase 2 is unexecuted. As each phase is run, append **executed commands, output, file contents, wiring, time, verdict, and recovery results** to the daily section. Do not log estimated values as actual measurements.

| Item | What to log |
|---|---|
| Date/Time | JST and router's `date -Iseconds` |
| Wiring | Blue/white cable destinations, BUFFALO/ONU status |
| Config Diffs | `uci changes`, `uci show network/firewall/dhcp` |
| Git Baseline | Sanitized `router-config/` diff, commit ID, secret-review result, and any applied UCI commands |
| IPv6 | `ubus`, addresses, prefixes, routes, connectivity |
| MAP-E | Rule source, full `mapcalc` output, BR, derived IPv4, PSID, port ranges |
| IPv4 / NAT | PC source, routes, HTTPS, tunnels, `nft`, `conntrack`, external logs |
| Artifacts | Backups, pcaps, hashes, PC save locations |
| Verdict | 2A/2B/2C/2D completion conditions and unverified points |

### Checklist

- [x] Saved pre-Phase 2 backup to PC and verified hash
- [ ] Captured and reviewed sanitized Git configuration baseline
- [ ] Logged current BUFFALO IPv4/IPv6 and port ranges
- [x] Confirmed `map` package and free space
- [ ] Connected blue WAN cable to ONU, maintained white LAN path
- [ ] 2A: Confirmed OpenWrt's IPv6 address, route, and external connectivity
- [ ] 2B: Logged MAP-E parameter sources and `mapcalc` results
- [ ] 2C: Confirmed IPv4 over IPv6 traffic and WAN encapsulation
- [ ] 2D: Confirmed setup and actual use of multiple port ranges
- [ ] On failure, reverted to BUFFALO routing and re-confirmed IPv4/DNS/management access

### 2026-09-23 — Automatic MAP-E Preparation (Executed)

Topology remained unchanged throughout this entry: `ONU -> BUFFALO -> DS57U eth0`; the white `eth1` management LAN remained connected. The router clock reported `2026-09-22T15:51:34+00:00` at inspection and `2026-09-22T15:53:07+00:00` after configuration (2026-09-23 JST). No ONU-direct cable move was made.

Initial read-only checks found `network.wan6.device='eth0'`, `network.wan6.proto='dhcpv6'`, firewall zone `wan` containing `wan` and `wan6`, and LAN unchanged as `br-lan`/`eth1`/`192.168.1.1/24`. At this point, `apk info -e map` and `test -f /lib/netifd/proto/map.sh` both exited `1`; `network.wan6.iface_map` was unset. `wan6` was up through BUFFALO with one `/64` address, no delegated prefix, and external IPv6 connectivity. Those upstream values are not evidence for direct ONU behavior and are intentionally not reproduced here.

The following commands were executed in this order in one persistent SSH session; each command completed with exit status `0` except where noted below:

```sh
df -h /
mkdir -p /root/phase2-prep
cp -p /etc/config/network /root/phase2-prep/network
cp -p /etc/config/firewall /root/phase2-prep/firewall
cp -p /etc/config/dhcp /root/phase2-prep/dhcp
sysupgrade -b /tmp/phase2-before-wan.tar.gz
sha256sum /tmp/phase2-before-wan.tar.gz
apk update
apk search map
apk add map
apk info -e map
test -f /lib/netifd/proto/map.sh
uci set network.wan6.iface_map='1'
uci changes
uci commit network
ubus call network reload
uci show network.wan6
ubus call network.interface.wan6 status
ubus call network.interface.wan6_4 status
ping -6 -c 2 2606:4700:4700::1111
```

Before package installation, `/` had 72.1 MiB free. `apk update` reported `OK: 11238 distinct packages available`; `apk search map` found `map-7`; and `apk add map` installed `map-7` plus ten dependencies. Afterwards, `/` had 71.5 MiB free, `apk info map` described MAP-E/MAP-T/LW4o6 support, and `/lib/netifd/proto/map.sh` existed.

The pre-change archive was copied with `scp -O` to `backups/phase2-before-wan.tar.gz`. Router and PC SHA-256 values both were `dce1e58a40a79eb93c53b1500b616bfd6007987f8992fc04076fee28e715e7bf`.

The only committed UCI change was:

```text
network.wan6.iface_map='1'
```

`uci changes` was empty after the commit. `wan6` remained up, and `ping -6 -c 2 2606:4700:4700::1111` returned 2/2 replies (minimum/average/maximum `6.078/6.156/6.234 ms`). `ubus call network.interface.wan6_4 status` returned `Command failed: Not found`, which is expected while the BUFFALO upstream supplies no MAP-E DHCPv6 option to DS57U.

Result: **Passed only for pre-switch preparation.** On a future direct ONU connection, `wan6.iface_map='1'` permits DHCPv6-provided MAP-E data to create the dynamic MAP interface automatically. It does not synthesize a MAP-E rule if OCN does not provide one; in that case direct IPv6 and `wan6_4` state must be inspected before any manual MAP-E rule is considered. No Phase 2A/2B/2C/2D completion condition is met by this entry.

### 2026-10-02 — Static MAP-E Staging Feasibility Check (Read-only)

Topology remained the established path `ONU -> BUFFALO WAN -> BUFFALO LAN ->
DS57U eth0`; no cable, UCI, package, service, or route was changed. The
following one-off read-only SSH command exited `0` at
`2026-10-02T23:35:11+09:00`:

```powershell
ssh -i .local-ssh/id_ed25519_v2 -o BatchMode=yes -o ConnectTimeout=10 root@192.168.1.1 "date -Iseconds; uci -q get network.map; uci show network.wan6; ubus call network.interface.wan6 status; ip -4 route; ubus call network.interface.wan6_4 status"
```

`network.map` was absent and `wan6_4` returned `Command failed: Not found`.
However, `wan6` was up on `eth0` with
`2400:4050:c340:1600:82ee:73ff:feab:4af0/64`, which matches the local
calculator's `2400:4050:8000::/33` snapshot. The active IPv4 default route
remained `default via 192.168.11.1 dev eth0 src 192.168.11.108`.

Conclusion: a static MAP interface using that rule can be configured, but
activating it now is an operational IPv4 route change, not harmless staging:
it can replace the BUFFALO IPv4 default route with the MAP-E route. Do not
apply or reload it until a verified backup and a maintenance window are in
place. If the rule is accepted by the upstream BR, IPv4-over-IPv6 should then
work without access to an external calculation site; `mapcalc`, IPv4/IPv6
probes, and an `ip6 proto 4` capture remain required proof.

### 2026-10-02 — Guarded Router-Side MAP-E Automation (Installed)

The user requested router-side calculation and MAP-E activation when the ONU
is connected, without requiring access to an external calculator. The deployed
source is tracked as `tools/router/mape-auto-reconcile.sh` and
`tools/router/99-mape-auto`; the installed copies are
`/usr/sbin/mape-auto-reconcile` and `/etc/hotplug.d/iface/99-mape-auto`.

On `wan` or `wan6` `ifup`, the hotplug hook starts the reconciler in the
background. It waits 10 seconds for DHCP to settle, then follows this guarded
decision:

1. If `wan` has an IPv4 DHCP address, it removes any previously generated
   `network.mape_auto` interface and its WAN-zone membership. This preserves
   the normal BUFFALO IPv4 route. If DHCPv6 later supplies a working dynamic
   `wan6_4`, it likewise removes the static interface and defers to that
   provider-supplied MAP-E configuration.
2. If `wan` has no IPv4 address, it reads the current global `wan6` address.
   Only the locally verified `2400:4050:8000::/33` OCN rule is accepted.
3. It derives the observed address's `/64`, appends it as `pd=<prefix>,pdlen=64`
   to the static MAP rule, and uses the installed `mapcalc` as a fail-closed
   RFC 7597 calculation gate. This explicit `/64` is required because this
   line's DHCPv6 diagnostic returned `NoPrefixAvail`; standard `mapcalc wan6`
   has no delegated prefix to use by itself.
4. Only when `mapcalc` reports `RULE_BMR=1` does it commit `network.mape_auto`,
   add it to firewall zone `wan`, and run `ifup mape_auto`.

The router-side pre-install calculation used the currently observed `/64` and
returned `RULE_BMR=1`, derived IPv4 `153.243.13.0`, PSID length `6`, and BR
`2001:380:a120::9`. Its calculated tunnel source was
`2400:4050:c340:1600:0:99f3:d00:16`; this is a calculation result, not proof
that the BR accepts the rule.

Before installation, the following backup was created and copied to ignored
local storage. Both router and PC SHA-256 values were
`b7e2b194d5e1a39b88f5aab4f82112724403eaad03bf4295790db6d8d23229a3`:

```powershell
ssh -i .local-ssh/id_ed25519_v2 -o BatchMode=yes -o ConnectTimeout=10 root@192.168.1.1 'sysupgrade -b /tmp/mape-auto-before-20261002.tar.gz && sha256sum /tmp/mape-auto-before-20261002.tar.gz'
scp -O -i .local-ssh/id_ed25519_v2 -o BatchMode=yes -o ConnectTimeout=10 root@192.168.1.1:/tmp/mape-auto-before-20261002.tar.gz backups/mape-auto-before-20261002.tar.gz
certutil -hashfile backups/mape-auto-before-20261002.tar.gz SHA256
```

The uploaded files passed `sh -n`. Their final SHA-256 values were
`001b30601b24e3e24d9afbbbfd6a7032c3c53768a98658453d7ac68897db79dd`
for the reconciler and
`b9320f7cf10a94322c240620c3062ca6371854b3e9fcc0fd983998f94e261c2c`
for the hook. OpenWrt does not provide `install`, so the first placement attempt
failed before changing either target; it was corrected with `cp` followed by
`chmod 0755`. The reconciler was then updated after an additional guarded
BUFFALO dry run to defer to any future DHCPv6-provided `wan6_4`.

The guarded dry run and manual `wan ifup` hook invocation both found the
BUFFALO IPv4 lease and left `network.mape_auto` absent (exit `1`). Final
read-only verification showed the unchanged route
`default via 192.168.11.1 dev eth0 src 192.168.11.108`; `wan6_4` remained
absent (exit `4`). This proves the fallback guard only. It does **not** prove
direct-ONU activation, BR acceptance, IPv4 connectivity, or encapsulation.

### 2026-10-04 — Replacement trial readiness recheck (executed; no cable move)

At `2026-10-04T01:25:44+09:00`, live state still showed the BUFFALO-main-router
path: DS57U `eth0` had `192.168.11.108`, with the IPv4 default gateway
`192.168.11.1`; management remained `br-lan`, `192.168.1.1/24`.
No cable, UCI, route, or service setting was changed. The user requested
readiness for a replacement trial. This check proves preparation only;
direct-ONU MAP-E activation and BR acceptance remain untested.

The first local attempts encountered the RTK PowerShell shim's ambiguous
`-e`/`-i` binding and its handling of quoted pipe characters. These failed
before router execution. Commands were corrected using `--regexp` for local
searches and `rtk proxy cmd.exe /c "ssh ..."` for SSH. The sandbox SSH attempt
returned `Permission denied` (exit 1); the network-enabled retry connected.
One persistent SSH session was then used for the following commands, in order:

```sh
date -Iseconds
uci show network.wan
uci show network.wan6
uci show network.lan
uci show dhcp.buffalo_wan
uci show firewall.@zone[1]
uci changes
apk info -e map; echo MAP_PACKAGE_EXIT=$?
ls -l /usr/sbin/mape-auto-reconcile /etc/hotplug.d/iface/99-mape-auto
sha256sum /usr/sbin/mape-auto-reconcile /etc/hotplug.d/iface/99-mape-auto
sh -n /usr/sbin/mape-auto-reconcile; echo RECONCILE_SYNTAX_EXIT=$?
sh -n /etc/hotplug.d/iface/99-mape-auto; echo HOOK_SYNTAX_EXIT=$?
uci -q get network.mape_auto; echo STATIC_MAP_EXIT=$?
ip -4 route
ubus call network.interface.wan6 status
ping -4 -c 2 -W 3 1.1.1.1; echo IPV4_PING_EXIT=$?
for n in eth0 eth1; do echo LINK=$n; cat /sys/class/net/$n/carrier /sys/class/net/$n/speed /sys/class/net/$n/duplex; done
sysupgrade -b /tmp/mape-trial-before-20261004.tar.gz; echo BACKUP_EXIT=$?
sha256sum /tmp/mape-trial-before-20261004.tar.gz
uci show dhcp.lan
grep 192.168.1.2 /tmp/dhcp.leases; echo RESERVED_LEASE_MATCH_EXIT=$?
```

Relevant observed output:

```text
network.wan.device='eth0'
network.wan.proto='dhcp'
network.wan6.device='eth0'
network.wan6.proto='dhcpv6'
network.wan6.iface_map='1'
network.lan.device='br-lan'
network.lan.ipaddr='192.168.1.1/24'
dhcp.buffalo_wan.mac='68:E1:DC:37:1D:10'
dhcp.buffalo_wan.ip='192.168.1.2'
firewall.cfg03dc81.name='wan'
firewall.cfg03dc81.network='wan' 'wan6'
firewall.cfg03dc81.masq='1'
MAP_PACKAGE_EXIT=0
RECONCILE_SYNTAX_EXIT=0
HOOK_SYNTAX_EXIT=0
STATIC_MAP_EXIT=1
default via 192.168.11.1 dev eth0  src 192.168.11.108
2 packets transmitted, 2 packets received, 0% packet loss
IPV4_PING_EXIT=0
LINK=eth0: carrier=1, speed=1000, duplex=full
LINK=eth1: carrier=1, speed=1000, duplex=full
BACKUP_EXIT=0
dhcp.lan.start='100'
dhcp.lan.limit='150'
RESERVED_LEASE_MATCH_EXIT=1
```

`uci changes` produced no output. Both installed scripts were executable
(`0755`) and their SHA-256 hashes matched the local source hashes and the
October 2 installation record above. `wan6` was up with
`2400:4050:c340:1600:82ee:73ff:feab:4af0/64`, no delegated prefix, and an IPv6
default next hop `fe80::6ae1:dcff:fe37:1d10`. IPv6 end-to-end connectivity was
not retested. The lease search returned no match; the reserved `.2` is outside
the dynamic `.100`–`.249` pool. Individual exit statuses for unlabelled
read-only commands were not separately captured; their output is the evidence.

The fresh backup was copied to the PC (exit 0) and hashed (exit 0):

```powershell
rtk proxy cmd.exe /c "scp -O -i .local-ssh/id_ed25519_v2 -o BatchMode=yes -o ConnectTimeout=10 root@192.168.1.1:/tmp/mape-trial-before-20261004.tar.gz backups/mape-trial-before-20261004.tar.gz"
rtk proxy powershell -NoProfile -Command "Get-FileHash backups/mape-trial-before-20261004.tar.gz -Algorithm SHA256"
```

Router and PC SHA-256:
`b7e2b194d5e1a39b88f5aab4f82112724403eaad03bf4295790db6d8d23229a3`.

Verdict: installed MAP-E automation and current BUFFALO IPv4 baseline PASS;
fresh backup verified. Ready for a bounded isolated direct-ONU trial, with
the PC retained on DS57U LAN and the original BUFFALO wiring available for
rollback. This is not replacement acceptance. No cable move, direct-ONU
activation, encapsulation, downstream BUFFALO test, or rollback was performed
in this recheck.

### 2026-10-04 — Direct-ONU live trial (executed; IPv4 failed)

The user reported DS57U connected to the ONU, and subsequently confirmed that
BUFFALO was completely disconnected from the ONU-side network. The PC retained
router management access and used smartphone Wi-Fi tethering for this chat.
The existing persistent SSH session remained usable. No router/ONU reboot or
physical rollback was performed during these checks.

At `2026-10-04T02:02:08+09:00`, `wan` was pending DHCP with no IPv4 lease;
`wan6` was up with `2400:4050:c340:1600:82ee:73ff:feab:4af0/64`, no PD,
and default next hop `fe80::212:e2ff:fe70:5250`. The hook had logged activation
at `01:54:33`. `mape_auto` was up as `map-mape_auto`, IPv4 `153.243.13.0/32`,
with `default dev map-mape_auto scope link`; dynamic `wan6_4` was absent.
The first full `ifstatus mape_auto` output was unexpectedly large because of
the generated SNAT port sets. A complete final status snapshot was saved
instead; see the ignored logs and hashes below.

Executed observation/probe commands, in order, in the persistent router shell:

```sh
date -Iseconds; ubus call network.interface.wan status; ubus call network.interface.wan6 status; ifstatus mape_auto; ifstatus wan6_4; ip -4 route; ip -6 route
ping -4 -c 3 -W 3 1.1.1.1; echo IPV4_EXIT=$?
ping -6 -c 3 -W 3 2606:4700:4700::1111; echo IPV6_EXIT=$?
nslookup example.com 127.0.0.1; echo DNS_EXIT=$?
command -v curl; command -v tcpdump
ip -d link show map-mape_auto
uci show network.mape_auto
logread -e mape-auto | tail -n 12
ip -6 route get 2001:380:a120::9
tcpdump -ni eth0 -c 12 'ip6 proto 4' > /tmp/mape-trial-20261004-tunnel.log 2>&1 &
curl -4 --connect-timeout 5 --max-time 12 -sS -o /dev/null -w 'HTTP=%{http_code}\n' https://1.1.1.1/cdn-cgi/trace; echo HTTPS4_EXIT=$?
kill %1; cat /tmp/mape-trial-20261004-tunnel.log
ip link show map-mape_auto
cat /sys/class/net/map-mape_auto/statistics/tx_packets /sys/class/net/map-mape_auto/statistics/rx_packets
ip -6 route get 2001:380:a120::9 from 2400:4050:c340:1600:0:99f3:d00:16
grep -n -e legacy -e draft -e RULE_ -e ip6addr /lib/netifd/proto/map.sh | head -n 65
mapcalc --help 2>&1 | head -n 20
LEGACY=1 mapcalc wan6 "$(uci -q get network.mape_auto.rule)" | grep -e RULE_BMR -e IPV6ADDR -e IPV4ADDR -e PSID
```

Initial results: IPv4 ping `3/3` lost, exit `1`; native IPv6 ping `3/3`
received, exit `0`, average `5.525 ms`; DNS returned A/AAAA records, exit `0`.
IPv4 HTTPS timed out, exit `28`, `HTTP=000`. BusyBox does not support `ip -d`.
The unsourced BR route lookup returned `Network unreachable`, but the lookup
with the actual tunnel source succeeded through the IPv6 next hop above.
Thus the unsourced lookup alone was not evidence of a missing BR route.

Initial tunnel TX/RX packets were `3638/0`. Capture showed outbound source
`2400:4050:c340:1600:0:99f3:d00:16`, but incoming BR traffic addressed
`2400:4050:c340:1600:99:f30d:0:1600`. `LEGACY=1 mapcalc` returned
`RULE_BMR=1`, the same IPv4 and PSID length `6`, and exactly that latter IPv6.
Installed `/lib/netifd/proto/map.sh` explicitly reads `legacymap` and passes it
to mapcalc via `LEGACY`. The following reversible live trials were applied:

```sh
uci set network.mape_auto.legacymap='1'; uci commit network; ifdown mape_auto; ifup mape_auto; echo LEGACY_APPLY_EXIT=$?
ping -4 -c 3 -W 3 1.1.1.1; echo IPV4_RETEST_EXIT=$?
curl -4 --connect-timeout 5 --max-time 12 -sS https://1.1.1.1/cdn-cgi/trace; echo HTTPS4_RETEST_EXIT=$?
ip link show map-mape_auto
sed -n '75,91p' /lib/netifd/proto/map.sh
cat /sys/class/net/map-mape_auto/statistics/rx_packets
ip -6 addr show dev eth0
nft list chain inet fw4 srcnat_mape_auto 2>&1 | head -n 8
uci set network.mape_auto.encaplimit='ignore'; uci commit network; ifdown mape_auto; ifup mape_auto; echo ENCAP_APPLY_EXIT=$?
curl -4 --connect-timeout 5 --max-time 12 -sS https://1.1.1.1/cdn-cgi/trace; echo ENCAP_HTTPS_EXIT=$?
ip -4 route
curl -4 --connect-timeout 5 --max-time 12 -sS https://1.1.1.1/cdn-cgi/trace; echo ENCAP_HTTPS_RETEST_EXIT=$?
ping -4 -c 2 -W 3 1.1.1.1; echo ENCAP_PING_EXIT=$?
tcpdump -ni eth0 -c 10 -vv 'ip6 proto 4 and host 2001:380:a120::9' > /tmp/mape-trial-20261004-legacy.log 2>&1 &
curl -4 --connect-timeout 5 --max-time 8 -sS -o /dev/null https://1.1.1.1/cdn-cgi/trace; echo CAPTURE_HTTPS_EXIT=$?
kill %1 2>/dev/null; head -n 24 /tmp/mape-trial-20261004-legacy.log
cat /sys/class/net/map-mape_auto/statistics/rx_packets
sed -n '155,190p' /lib/netifd/proto/map.sh
nft list chain inet fw4 input_wan; nft list chain inet fw4 prerouting
nft insert rule inet fw4 input_wan ip6 saddr 2001:380:a120::9 ip6 daddr 2400:4050:c340:1600:99:f30d:0:1600 meta l4proto 4 counter accept; echo BR_INPUT_TEST_EXIT=$?
curl -4 --connect-timeout 5 --max-time 12 -sS https://1.1.1.1/cdn-cgi/trace; echo FIREWALL_HTTPS_EXIT=$?
nft list chain inet fw4 input_wan | head -n 7
nft list ruleset | grep -n -e drop -e reject -e fib -e rpfilter | head -n 30
cat /sys/class/net/eth0/statistics/rx_dropped
cat /sys/class/net/map-mape_auto/statistics/rx_packets /sys/class/net/map-mape_auto/statistics/rx_errors
cat /proc/net/dev | grep map-
mapcalc wan6 "$(uci -q get network.mape_auto.rule)" | grep -e FMR -e PD6IFACE
cat /proc/sys/net/ipv6/conf/eth0/disable_ipv6
nft list chain inet fw4 input
ip -6 route show table local | head -n 12
ubus call network.device status '{"name":"map-mape_auto"}'
cat /proc/net/snmp6 | grep -e InDiscards -e InNoRoutes -e InAddrErrors -e InUnknownProtos
tcpdump -eni eth0 -c 6 'ip6 proto 4 and host 2001:380:a120::9' > /tmp/mape-trial-20261004-l2.log 2>&1 &
curl -4 --connect-timeout 4 --max-time 6 -sS -o /dev/null https://1.1.1.1/cdn-cgi/trace; echo L2_HTTPS_EXIT=$?
kill %1 2>/dev/null; cat /tmp/mape-trial-20261004-l2.log
cat /sys/class/net/eth0/address; ip -6 neigh show dev eth0
command -v ndsend; command -v ndisc6; command -v python3; command -v ping6
cat /proc/sys/net/ipv6/conf/eth0/dad_transmits
ls /usr/bin/*nd* /usr/sbin/*nd* 2>/dev/null | head -n 15
nft -a list chain inet fw4 input_wan | head -n 6
nft delete rule inet fw4 input_wan handle 1381; echo REMOVE_FIREWALL_TEST_EXIT=$?
ip -6 neigh del fe80::212:e2ff:fe70:5250 dev eth0; echo NEIGH_REFRESH_EXIT=$?
ping -6 -I 2400:4050:c340:1600:99:f30d:0:1600 -c 2 -W 3 2606:4700:4700::1111; echo TUNNEL_SOURCE_PING_EXIT=$?
```

Both UCI trial applications exited `0`. Legacy alone still failed ping (exit
`1`) and HTTPS (exit `28`). The first probe immediately after the second
`ifup` failed with exit `7`; once the IPv4 default route was present, it still
timed out with exit `28`, and ping lost `2/2` (exit `1`). Later captures proved
HTTPS SYN-ACKs returning from the BR to the legacy tunnel IPv6. The temporary
nft input rule applied with exit `0`, but had `0` packets/bytes and did not
restore HTTPS (exit `28`). It was removed with exit `0`; no permanent firewall
rule was added. `srcnat_mape_auto` was not an existing chain; that lookup
reported an error and did not establish an SNAT defect. `mapcalc` reported
`RULE_1_FMR=0`, `RULE_1_PD6IFACE=wan6`. Tunnel RX remained zero.

The decisive Ethernet capture excerpt (02:10:31 JST):

```text
80:ee:73:ab:4a:f0 > 00:12:e2:70:52:50 ...
2400:4050:c340:1600:99:f30d:0:1600 > 2001:380:a120::9:
153.243.13.0.1390 > 1.1.1.1.443: Flags [S]
00:12:e2:70:52:50 > 68:e1:dc:37:1d:10 ...
2001:380:a120::9 > 2400:4050:c340:1600:99:f30d:0:1600:
1.1.1.1.443 > 153.243.13.0.1390: Flags [S.]
```

DS57U `eth0` is `80:ee:73:ab:4a:f0`; return frames target BUFFALO's recorded
WAN MAC `68:e1:dc:37:1d:10`. Observed: the BR returns replies, but the link-layer
destination is the old router. Inference: stale upstream neighbor mapping is
the immediate blocker after correcting the tunnel address format. This is
not evidence of a local firewall drop or of successful IPv4 service.

BusyBox rejected `ip -6 neigh del` (`invalid argument 'del'`, exit `1`), so no
neighbor was deleted. Native IPv6 ping sourced from the legacy tunnel address
lost `2/2` (exit `1`). `ndsend`, `ndisc6`, and Python were unavailable; `ping6`
was present. A proposed `ndisc_notify=1` plus setting eth0 to its **existing**
MAC was blocked by automatic approval review before execution due to possible
connectivity disruption/address conflict. Neither mutation nor its following
HTTPS test ran; explicit approval is pending. No workaround was attempted.

Current trial configuration retains `legacymap='1'` and
`encaplimit='ignore'` on `network.mape_auto`; local source files are unchanged.
Legacy matches observed BR traffic; the independent benefit of `encaplimit`
has not been established. On return to BUFFALO, the installed guard is
expected to delete `mape_auto` when WAN DHCP returns; this rollback has not
been executed or verified in this trial. To restore just these trial options
while still direct-ONU (planned, not executed):

```sh
uci -q delete network.mape_auto.legacymap
uci -q delete network.mape_auto.encaplimit
uci commit network
ifdown mape_auto
ifup mape_auto
```

Evidence preservation executed in the same SSH session:

```sh
{ date -Iseconds; ifstatus wan; ifstatus wan6; ifstatus mape_auto; ip -4 route; ip -6 route; uci show network.mape_auto; logread -e mape-auto; } > /tmp/mape-trial-20261004-status.log 2>&1
sha256sum /tmp/mape-trial-20261004-*.log
```

PC copy and verification (both exited `0`):

```powershell
rtk proxy cmd.exe /c "scp -O -i .local-ssh/id_ed25519_v2 -o BatchMode=yes -o ConnectTimeout=10 root@192.168.1.1:/tmp/mape-trial-20261004-*.log backups/"
rtk proxy powershell -NoProfile -Command "Get-FileHash backups/mape-trial-20261004-*.log -Algorithm SHA256 | Format-List Path,Hash"
```

Complete ignored local logs (router and PC hashes match):

| File under `backups/` | SHA-256 |
| --- | --- |
| `mape-trial-20261004-l2.log` | `639717ab838fd2ac628d7db6d793c80f4ee1d7784d4f67ddc324d43a9e2758e8` |
| `mape-trial-20261004-legacy.log` | `eb55e0f4c62d75ea6d1e2ae7311fec748eecf4b997b553a590504aaa90cd60fe` |
| `mape-trial-20261004-status.log` | `9af12fadff31c38a4da9b63e854bb9fc44d94977be9d524e5945a06cc2e76cb8` |
| `mape-trial-20261004-tunnel.log` | `e52c82c39e62074bdc19dff109f9a6ba0649566f65907eb50df67b88bdc9d3d5` |

Captures used no payload dump option. Individual exit statuses for commands
without explicit labels were not separately captured; observed output is
the evidence. Successful capture completion is recorded in each log.

Verdict: native IPv6 and DNS PASS; automatic tunnel creation PASS; usable
IPv4/MAP-E FAIL. Replacement acceptance remains incomplete. Next work is to
refresh upstream neighbor ownership with explicit authorization, then retest
IPv4 and make only proven settings persistent in the automation. Kernel
receive-path source was consulted during investigation, without treating its
current upstream version as proof of this router's installed kernel behavior:
[Linux ip6_tunnel.c](https://github.com/torvalds/linux/blob/master/net/ipv6/ip6_tunnel.c).

### 2026-10-04 — Direct-ONU status recheck (IPv4 HTTPS now passes)

The user again reported DS57U connected to the ONU and requested status.
At `2026-10-04T02:16:25+09:00`, the same persistent SSH session was used;
no UCI, kernel, firewall, service, or cable changes were made in this recheck.
In particular, the previously rejected neighbor-announcement command was not
executed or bypassed. Prior live trial settings `legacymap=1` and
`encaplimit=ignore` remain committed on `network.mape_auto`; source automation
has not yet been updated to recreate these options.

Commands in execution order:

```sh
date -Iseconds
ifstatus wan | jsonfilter -e '@.up'
ifstatus wan6 | jsonfilter -e '@.up' -e '@["ipv6-address"][0].address'
ifstatus mape_auto | jsonfilter -e '@.up' -e '@["ipv4-address"][0].address'
ip -4 route
ping -4 -c 2 -W 3 1.1.1.1; echo IPV4_CHECK_EXIT=$?
ping -6 -c 2 -W 3 2606:4700:4700::1111; echo IPV6_CHECK_EXIT=$?
tcpdump -eni eth0 -c 4 'ip6 proto 4 and host 2001:380:a120::9' > /tmp/mape-recheck-20261004-l2.log 2>&1 &
curl -4 --connect-timeout 4 --max-time 6 -sS -o /dev/null -w 'HTTP=%{http_code}\n' https://1.1.1.1/cdn-cgi/trace; echo IPV4_HTTPS_CHECK_EXIT=$?
kill %1 2>/dev/null; cat /tmp/mape-recheck-20261004-l2.log
cat /sys/class/net/map-mape_auto/statistics/rx_packets
nslookup example.com 127.0.0.1; echo DNS_RECHECK_EXIT=$?
curl -4 --connect-timeout 5 --max-time 10 -sS https://1.1.1.1/cdn-cgi/trace; echo TRACE_RECHECK_EXIT=$?
ping -4 -c 2 -W 3 1.1.1.1; echo IPV4_FINAL_EXIT=$?
sha256sum /tmp/mape-recheck-20261004-l2.log
uci -q get network.mape_auto.legacymap
uci -q get network.mape_auto.encaplimit
```

Observed output excerpts:

```text
wan up: false
wan6 up: true
2400:4050:c340:1600:82ee:73ff:feab:4af0
mape_auto up: true
153.243.13.0
default dev map-mape_auto scope link
IPV4_CHECK_EXIT=1 (2 sent, 0 received)
IPV6_CHECK_EXIT=0 (2 sent, 2 received; average 7.971 ms)
HTTP=200
IPV4_HTTPS_CHECK_EXIT=0
map-mape_auto rx_packets: 6283
DNS_RECHECK_EXIT=0
ip=153.243.13.0
colo=NRT
http=http/2
loc=JP
tls=TLSv1.3
warp=off
TRACE_RECHECK_EXIT=0
IPV4_FINAL_EXIT=1 (2 sent, 0 received)
legacymap: 1
encaplimit: ignore
```

DNS returned A/AAAA records for `example.com`. The capture at `02:16:47` now
shows the upstream MAC `00:12:e2:70:52:50` sending encapsulated IPv4 HTTPS
traffic to DS57U `80:ee:73:ab:4a:f0`, and DS57U returning TCP ACKs. IPv6 tunnel
endpoints are the legacy CE address and BR documented above. The capture
completed at 4 packets, with 0 kernel drops. Return MAC ownership changed
between the preceding failed test and this successful check; the exact
refresh time and mechanism were not observed. Do not attribute recovery to
the blocked neighbor command or assert that an ONU reboot occurred.

The complete capture was copied locally (exit 0) and hash-verified (exit 0):

```powershell
rtk proxy cmd.exe /c "scp -O -i .local-ssh/id_ed25519_v2 -o BatchMode=yes -o ConnectTimeout=10 root@192.168.1.1:/tmp/mape-recheck-20261004-l2.log backups/mape-recheck-20261004-l2.log"
rtk proxy powershell -NoProfile -Command "Get-FileHash backups/mape-recheck-20261004-l2.log -Algorithm SHA256"
```

Ignored local file `backups/mape-recheck-20261004-l2.log`, router/PC SHA-256:
`5b4d545442c81e6163227a7998c9f80bbbd3846bc411f33597a0bfb04e747a10`.
Exit statuses for unlabelled observations were not individually captured.

Verdict: router-originated IPv4 HTTPS over MAP-E PASS, native IPv6 PASS, DNS
PASS. IPv4 ICMP FAIL, cause not established. The zero WAN DHCP IPv4 state is
not itself a MAP-E failure: the usable IPv4 route is the MAP tunnel.
PC/LAN client forwarding, BUFFALO downstream operation, reboot/reconnect
persistence, and recreating the live trial options in the source hook remain
unverified/incomplete. No physical rollback was performed.

### 2026-10-04 — ICMP diagnosis and persistent MAP-E automation (executed)

The user requested investigation of IPv4 ping and installation of the MAP-E
automation settings. Direct-ONU topology and the persistent SSH session were
retained. At `02:46:51+09:00`, live MAP-E still used the successful legacy
address layout and `encaplimit=ignore`. No physical cable movement, reboot,
MAC change, or neighbor-notification mutation was performed.

**Cause and proof.** The installed `/lib/netifd/proto/map.sh` submits ICMP,
TCP, and UDP SNAT entries with allocated port ranges. Installed
`/usr/share/ucode/fw4.uc`, lines 3092 onward, rejects SNAT sections with ports
unless `ensure_tcpudp()` succeeds. The actual fw4 warning was:

```text
ubus nat (ubus:mape_auto[map] nat 0) specifies ports but no UDP/TCP protocol, ignoring section
```

The resulting ruleset had TCP/UDP port-set SNAT, but no ICMP identifier
translation. ICMP echo identifier `30018` was observed leaving the tunnel
unchanged; it is not in the allocated ranges (PSID 22, length 6, offset 6;
`(30018 >> 4) & 63 = 20`). Baseline ping lost all packets. A temporary nft
SNAT rule translating echo identifiers to allocated range `1376-1391`
immediately restored 3/3 replies. This controlled test establishes the ICMP
identifier translation defect as the cause of the observed ping failure.

Commands in execution order (all router commands used the existing SSH shell):

```sh
date -Iseconds; command -v ping; readlink -f /bin/ping; uci show network.mape_auto; cat /tmp/map-mape_auto.rules | head -n 12
tcpdump -ni eth0 -c 4 'ip6 proto 4 and host 2001:380:a120::9' > /tmp/mape-ping-20261004.log 2>&1 &
ping -4 -c 2 -W 3 1.1.1.1; echo PING_BASELINE_EXIT=$?
kill %1 2>/dev/null; head -n 12 /tmp/mape-ping-20261004.log
nft list chain inet fw4 srcnat_wan | head -n 24
ping --help 2>&1 | head -n 24
nft list ruleset 2>/dev/null | grep -n -e snat -e icmp | head -n 30
tcpdump -ni eth0 -c 4 'ip6 proto 4 and ip6[49] = 1' > /tmp/mape-ping-20261004-icmp.log 2>&1 &
ping -4 -c 3 -W 3 1.1.1.1; echo ICMP_CAPTURE_PING_EXIT=$?
cp /usr/sbin/mape-auto-reconcile /tmp/mape-auto-reconcile-before-20261004
sh -n /tmp/mape-auto-reconcile-new && cp /tmp/mape-auto-reconcile-new /usr/sbin/mape-auto-reconcile && chmod 0755 /usr/sbin/mape-auto-reconcile; echo AUTOMATION_INSTALL_EXIT=$?
sha256sum /usr/sbin/mape-auto-reconcile
kill %1 2>/dev/null; cat /tmp/mape-ping-20261004-icmp.log
grep -n -e 'port' -e 'icmp' /usr/share/ucode/fw4.uc | tail -n 16
ls /usr/share/firewall4/templates/*nat*
/usr/sbin/mape-auto-reconcile; echo RECONCILE_EXIT=$?
sed -n '3035,3085p' /usr/share/ucode/fw4.uc; sed -n '3138,3185p' /usr/share/ucode/fw4.uc
logread -e firewall | tail -n 8
sed -n '3085,3138p' /usr/share/ucode/fw4.uc
nft insert rule inet fw4 srcnat meta nfproto ipv4 oifname map-mape_auto icmp type echo-request counter snat ip to 153.243.13.0:1376-1391; echo ICMP_SNAT_TEST_EXIT=$?
ping -4 -c 3 -W 3 1.1.1.1; echo ICMP_SNAT_PING_EXIT=$?
grep -n -e chain-pre -e chain-post /usr/share/firewall4/templates/*.uc /usr/share/ucode/fw4.uc | head -n 12
nft -a list chain inet fw4 srcnat | head -n 8
grep RULE_1_PORTSETS /tmp/map-mape_auto.rules | head -c 220; echo
grep -n -e chain-prepend -e 'nftables.d' /usr/share/ucode/fw4.uc | head -n 15
sed -n '3205,3280p' /usr/share/ucode/fw4.uc
```

The first broad capture filled with existing TCP traffic before capturing
ping; it did not prove the ping cause. The corrected ICMP-only capture showed:

```text
02:48:10.701740 ... 153.243.13.0 > 1.1.1.1: ICMP echo request, id 30018, seq 1
02:48:11.701892 ... 153.243.13.0 > 1.1.1.1: ICMP echo request, id 30018, seq 2
```

Baseline exits were `1` (2/2 lost and 3/3 lost respectively).
`AUTOMATION_INSTALL_EXIT=0`; the intermediate tunnel-only update hash was
`866a1e0f9dde6850b8c67df863c00efe6c96fe9369b0d08c2ebfbe3ca3f49748`.
Its no-op reconciliation exited `0` but printed a JSON parse error because
absent `wan6_4` emits a non-JSON message; final source suppresses this expected
parser diagnostic. The template wildcard lookup found no `*nat*` files;
subsequent reads of actual ruleset/includes code identified the supported
`chain-prepend` include. The nft test applied with exit `0`, then ping passed
3/3, average `3.410 ms`, exit `0`.

**Final implementation.** `tools/router/mape-auto-reconcile.sh` now:

- Calculates using `LEGACY=1` and recreates `legacymap=1`,
  `encaplimit=ignore` when missing, even if the existing rule and interface
  otherwise match.
- Extracts the IPv4 address and first allocated identifier range from current
  mapcalc output and writes `/etc/mape-auto-icmp.nft`. It registers the named
  UCI nftables include `firewall.mape_auto_icmp` at `chain-prepend/srcnat`,
  checks fw4, and reloads only when the file/include changes.
- Removes the ICMP include when WAN DHCP returns or dynamic MAP takes over,
  and avoids repeated WAN-zone membership when rebuilding the static map.
- Keeps the existing WAN/WAN6 hotplug entrypoint and BUFFALO DHCP guard.

The ICMP rule handles echo requests only and uses the first allocated range
(currently 16 identifiers, `1376-1391`); it does not change TCP/UDP NAT or WAN
input policy. Its address/range are derived, not fixed to this session.
The installed rule and include were:

```text
meta nfproto ipv4 oifname "map-mape_auto" icmp type echo-request counter snat ip to 153.243.13.0:1376-1391 comment "mape-auto ICMP identifiers"
firewall.mape_auto_icmp=include
firewall.mape_auto_icmp.type='nftables'
firewall.mape_auto_icmp.path='/etc/mape-auto-icmp.nft'
firewall.mape_auto_icmp.position='chain-prepend'
firewall.mape_auto_icmp.chain='srcnat'
```

Uploads were executed twice, for the intermediate tunnel-only change and
then the final ICMP-aware source, each exiting `0`:

```powershell
rtk proxy cmd.exe /c "scp -O -i .local-ssh/id_ed25519_v2 -o BatchMode=yes -o ConnectTimeout=10 tools/router/mape-auto-reconcile.sh root@192.168.1.1:/tmp/mape-auto-reconcile-new"
```

Final installation and verification commands, in order:

```sh
sysupgrade -b /tmp/mape-icmp-before-20261004.tar.gz; echo ICMP_BACKUP_EXIT=$?
sha256sum /tmp/mape-icmp-before-20261004.tar.gz
sh -n /tmp/mape-auto-reconcile-new && cp /tmp/mape-auto-reconcile-new /usr/sbin/mape-auto-reconcile && chmod 0755 /usr/sbin/mape-auto-reconcile; echo FINAL_INSTALL_EXIT=$?
/usr/sbin/mape-auto-reconcile; echo ICMP_RECONCILE_EXIT=$?
cat /etc/mape-auto-icmp.nft; uci show firewall.mape_auto_icmp
nft list chain inet fw4 srcnat | head -n 6
ping -4 -c 3 -W 3 1.1.1.1; echo PERSISTENT_PING_EXIT=$?
curl -4 --connect-timeout 5 --max-time 10 -sS -o /dev/null -w 'HTTP=%{http_code}\n' https://1.1.1.1/cdn-cgi/trace; echo PERSISTENT_HTTPS_EXIT=$?
uci -q delete network.mape_auto.legacymap
uci -q delete network.mape_auto.encaplimit
/usr/sbin/mape-auto-reconcile > /tmp/mape-auto-rebuild-20261004.log 2>&1; echo REBUILD_EXIT=$?
uci show network.mape_auto; sha256sum /usr/sbin/mape-auto-reconcile
sh -n /usr/sbin/mape-auto-reconcile; echo FINAL_SYNTAX_EXIT=$?
ping -4 -c 3 -W 3 1.1.1.1; echo REBUILD_PING_EXIT=$?
curl -4 --connect-timeout 5 --max-time 10 -sS -o /dev/null -w 'HTTP=%{http_code}\n' https://1.1.1.1/cdn-cgi/trace; echo REBUILD_HTTPS_EXIT=$?
ACTION=ifup INTERFACE=wan /etc/hotplug.d/iface/99-mape-auto; echo HOTPLUG_EXIT=$?
{ date -Iseconds; uci show network.mape_auto; uci show firewall.mape_auto_icmp; cat /etc/mape-auto-icmp.nft; nft list chain inet fw4 srcnat | head -n 6; ping -6 -c 2 -W 3 2606:4700:4700::1111; echo IPV6_FINAL_EXIT=$?; nslookup example.com 127.0.0.1; echo DNS_FINAL_EXIT=$?; } > /tmp/mape-auto-final-20261004.log 2>&1
grep -e EXIT -e 'packets transmitted' /tmp/mape-auto-final-20261004.log
fw4 check > /tmp/mape-auto-fw4check-20261004.log 2>&1; echo FW4_CHECK_EXIT=$?
ifstatus mape_auto | jsonfilter -e '@.up' -e '@.uptime'
uci changes
sha256sum /tmp/mape-ping-20261004*.log /tmp/mape-auto-*-20261004.log
```

All labelled final installation/check exits were `0`. The persistent rule
replaced the temporary nft test on firewall reload. Ping after reload and
after rebuilding passed 3/3, average `3.426 ms` in both tests. Both HTTPS
tests returned `HTTP=200`. Rebuild restored both missing options and briefly
restarted the tunnel. Hotplug returned `0`; after its settle interval,
`mape_auto` remained up, uptime `99`, with no pending `uci changes`. Final
native IPv6 ping passed 2/2; DNS returned A/AAAA answers, both exits `0`.
`fw4 check` passed while continuing to warn about the upstream-generated ICMP
sections it omits; the added native nft rule supplies the missing behavior.
No `/lib/netifd/proto/map.sh` or fw4 package file was patched.

PC backup/log copies and verification (all exited `0`):

```powershell
rtk proxy cmd.exe /c "scp -O -i .local-ssh/id_ed25519_v2 -o BatchMode=yes -o ConnectTimeout=10 root@192.168.1.1:/tmp/mape-icmp-before-20261004.tar.gz backups/mape-icmp-before-20261004.tar.gz"
rtk proxy cmd.exe /c "scp -O -i .local-ssh/id_ed25519_v2 -o BatchMode=yes -o ConnectTimeout=10 root@192.168.1.1:/tmp/mape-ping-20261004*.log root@192.168.1.1:/tmp/mape-auto-*-20261004.log root@192.168.1.1:/tmp/mape-auto-reconcile-before-20261004 backups/"
rtk proxy powershell -NoProfile -Command "Get-FileHash tools/router/mape-auto-reconcile.sh,backups/mape-icmp-before-20261004.tar.gz -Algorithm SHA256 | Format-List Path,Hash"
rtk proxy powershell -NoProfile -Command "Get-FileHash backups/mape-ping-20261004*.log,backups/mape-auto-*-20261004.log,backups/mape-auto-reconcile-before-20261004 -Algorithm SHA256 | Format-List Path,Hash"
rtk proxy cmd.exe /c "git diff --check"
```

Final source/router hash:
`ff050f573537b012be165730d566e0f20e7ea99302408f4426a015a5430e4884`.
Hash-verified ignored evidence under `backups/`:

| File | SHA-256 |
| --- | --- |
| `mape-icmp-before-20261004.tar.gz` | `eb6d33719f18b45cf7f89e878726cd8a40345cef0328cacf8cc62a9581af7043` |
| `mape-auto-reconcile-before-20261004` | `001b30601b24e3e24d9afbbbfd6a7032c3c53768a98658453d7ac68897db79dd` |
| `mape-ping-20261004.log` | `bff7b9a2bad0fcb807c688084e2b606822435212401d35a69e257421ed9ddee9` |
| `mape-ping-20261004-icmp.log` | `01bb41cffd088ec1a056468b96f7ddec02de1726f7f54a316a6a316a7592713a` |
| `mape-auto-final-20261004.log` | `82b529e5bc5751d28efdb59e2356e99a0503fbcb0e79bd15fa739f4521a02271` |
| `mape-auto-fw4check-20261004.log` | `98248f3db00bd253ad42863b90d7b3d20ea3d5b9247b5db7030585adc21cedb7` |
| `mape-auto-rebuild-20261004.log` (empty; rebuild exit captured separately) | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |

Individual exit statuses for unlabelled read-only queries were not captured.
Rollback of this source/include change is available but not executed:

```sh
cp /tmp/mape-auto-reconcile-before-20261004 /usr/sbin/mape-auto-reconcile
chmod 0755 /usr/sbin/mape-auto-reconcile
uci -q delete firewall.mape_auto_icmp
uci commit firewall
rm -f /etc/mape-auto-icmp.nft
/etc/init.d/firewall reload
```

This removes the ICMP fix but retains the working tunnel's legacy/encaplimit
options. The saved previous script is also available on the PC if `/tmp` is
lost. Verdict: ICMP cause identified and fixed; automation deployed; syntax,
firewall reload, missing-option reconciliation, hook invocation, IPv4 ping,
IPv4 HTTPS, IPv6, and DNS PASS. Reboot, physical reconnect, new-prefix
allocation, and return-to-BUFFALO cleanup were not run in this change.

### 2026-10-13 JST - Investigate missing upstream public IPv6 delegation (executed)

Scope: determine whether OpenWrt disabled DHCPv6 prefix requests or the
upstream service did not provide a delegated prefix. The user confirmed
**no Hikari Denwa subscription**. This is diagnostic work; it did not enable
LAN IPv6 or repair the earlier smartphone outage.

Topology: unchanged direct-ONU DS57U WAN eth0, DS57U br-lan/eth1 to BUFFALO
WAN 192.168.1.2, BUFFALO LAN 192.168.11.0/24. No cable moves.
Current IPv4 uses map-mape_auto. Investigation approximately 00:50-00:56 JST.
Worktree already had the earlier investigation edit to
`docs/history/phase3c-monitoring.md`; that edit was preserved.

No UCI writes, restarts of existing clients/services, firewall reloads, or
reboots. Temporary capture and diagnostic log files were created in /tmp.
A separate DHCPv6 process failed during ubus initialization before reaching
a DHCP transaction. The capture and its timer completed. No configuration
backup/rollback was needed, and rollback was not run.

#### Commands in execution order

Opened one persistent SSH connection with the authorized read-only network
escalation:

```powershell
rtk proxy cmd.exe /c "ssh -tt -i .local-ssh/id_ed25519_v2 -o BatchMode=yes -o ConnectTimeout=10 root@192.168.1.1"
```

Initial commands:

```sh
date -Iseconds; uptime; echo rc=$?
uci show network.wan6; uci show network.lan; uci show dhcp.lan; uci changes; echo rc=$?
ps ww | grep '[o]dhcp6c'; odhcp6c -h 2>&1 | head -n 60; echo rc=$?
ubus call network.interface.wan6 status | sed '/"data": {/,/^[[:space:]]*}/d'; echo rc=$?
grep -n -E 'reqprefix|reqaddress|forceprefix|noslaac|delegate|odhcp6c|prefix' /lib/netifd/proto/dhcpv6.sh; echo rc=$?
logread | grep -Ei 'odhcp6c|NoPrefixAvail|dhcpv6|wan6|prefix' | grep -v 'ra_lifetime to 0' | tail -n 35; echo rc=$?
ls -l /tmp/*dhcpv6* /tmp/*onu* 2>/dev/null; command -v tcpdump; command -v timeout; echo rc=$?
```

Then inspected the retained October 1 packet capture and installed request
logic (pipeline status is the last command's status, not every command):

```sh
tcpdump -nn -vvv -r /tmp/direct-onu-dhcpv6.pcap 'udp port 546 or udp port 547' 2>/dev/null | head -n 24; echo rc=$?
sed -n '80,110p' /lib/netifd/proto/dhcpv6.sh; sed -n '190,206p' /lib/netifd/proto/dhcpv6.sh; ip -6 route | head -n 12; echo rc=$?
```

Both groups printed rc=0. A bounded diagnostic capture and separate client
were started:

```sh
tcpdump -ni eth0 -s 0 -U -c 60 -w /tmp/pd-probe-20261013.pcap 'udp port 546 or udp port 547 or (icmp6 and ip6[40] == 134)' >/tmp/pd-probe-20261013.capture.log 2>&1 & pd_cap_pid=$!; echo capture_pid=$pd_cap_pid
odhcp6c -s /bin/true -p /tmp/pd-probe-20261013.pid -Nnone -P0 -F -c00030001020000131013 -t10 -e -l7 eth0 >/tmp/pd-probe-20261013.client.log 2>&1 & pd_client_pid=$!; echo diagnostic_client_pid=$pd_client_pid
(sleep 20; kill -TERM "$pd_client_pid" 2>/dev/null; kill -INT "$pd_cap_pid" 2>/dev/null) & pd_timer_pid=$!; echo timer_pid=$pd_timer_pid
cat /tmp/pd-probe-20261013.client.log; echo rc=$?; ps ww | grep '[o]dhcp6c'
tcpdump -nn -vvv -r /tmp/direct-onu-dhcpv6.pcap 'icmp6 and ip6[40] == 134' 2>/dev/null | head -n 12; echo rc=$?
wait "$pd_client_pid"; echo diagnostic_exit=$?; wait "$pd_cap_pid"; echo capture_exit=$?; wait "$pd_timer_pid"; echo timer_exit=$?; cat /tmp/pd-probe-20261013.capture.log
command -v rdisc6; command -v ndisc6; ubus -v list 'odhcp6c*'; echo rc=$?
tcpdump -nn -vvv -r /tmp/direct-onu-dhcpv6.pcap 'icmp6 and ip6[40] == 134 and src host fe80::212:e2ff:fe70:5250' 2>/dev/null | head -n 8; echo rc=$?
tcpdump -nn -vvv -r /tmp/pd-probe-20261013.pcap 2>/dev/null | head -n 20; echo rc=$?
ubus call odhcp6c.eth0 get_state | head -n 100; echo rc=$?; ubus call odhcp6c.eth0 get_statistics | head -n 90; echo rc=$?
date -Iseconds; ps ww | grep '[o]dhcp6c'; ubus call network.interface.wan6 status | jsonfilter -e @.up -e @.uptime -e '@["ipv6-prefix"]'; ubus call network.interface.mape_auto status | jsonfilter -e @.up -e @.uptime; echo rc=$?
ping -c 3 -W 2 1.1.1.1; echo ping4_rc=$?; curl -6 -sS --max-time 15 -o /dev/null -w 'IPv6_HTTPS=%{http_code}\n' https://example.com; echo curl6_rc=$?; uci changes
sha256sum /tmp/pd-probe-20261013.pcap /tmp/pd-probe-20261013.capture.log /tmp/pd-probe-20261013.client.log /tmp/direct-onu-dhcpv6.pcap; echo rc=$?
exit
```

The separate client used a distinct synthetic DUID, no address request
(`-Nnone`), automatic prefix request (`-P0`), force-prefix (`-F`),
and the inert callback `/bin/true`. It failed with:

```text
Disconnecting from ubus
ubus error: Invalid argument
[2]- Done(1) odhcp6c ...
```

The later `wait "$pd_client_pid"` printed 127 because that exited background
job was no longer waitable; this is not its original process exit code.
The background job notification recorded the original exit as 1.
The existing client remained PID 27265, with WAN uptimes continuing.
The [upstream ubus implementation](https://github.com/openwrt/odhcp6c/blob/master/src/ubus.c)
registers one `odhcp6c.<interface>` object; the already-existing
`odhcp6c.eth0` object and duplicate registration failure are consistent.
No fresh DHCPv6 rejection was captured; do not report otherwise.

Capture/timer wait statuses were 0. Capture output:

```text
1 packet captured
1 packet received by filter
0 packets dropped by kernel
```

Neither `timeout`, `rdisc6`, nor `ndisc6` was available. The initial
availability group printed rc=127 from missing `timeout`; the explicit
sleep/kill timer was used instead. Read-only ubus get_state/get_statistics
were used, not the listed renew/release/reconfigure methods.

#### Current configuration and observations

Relevant UCI output:

```text
network.wan6=interface
network.wan6.device='eth0'
network.wan6.proto='dhcpv6'
network.wan6.iface_map='1'
network.lan=interface
network.lan.device='br-lan'
network.lan.proto='static'
network.lan.ipaddr='192.168.1.1/24'
network.lan.ip6assign='60'
dhcp.lan.dhcpv6='server'
dhcp.lan.ra='server'
dhcp.lan.ra_slaac='1'
dhcp.lan.ra_flags='managed-config' 'other-config'
```

No explicit reqprefix=no or delegate=0 is present. The installed
`/lib/netifd/proto/dhcpv6.sh` maps unset/auto reqprefix to 0 and appends
`-P` unless reqprefix is no. Actual running command, live DUID redacted:

```text
27265 root odhcp6c -s /lib/netifd/dhcpv6.script -P0:a1a5b3d2 -c[REDACTED_LIVE_DUID] -r94 -r95 -r96 -t120 eth0
```

Installed help explicitly says `-P <[pfx/]len> Request IPv6-Prefix (0 = auto)`.
Thus prefix requests are enabled; ip6assign=60 describes downstream allocation,
not a fixed /60 request to the upstream. No request-size correction was made.

At 00:55:05 JST, wan6 up=true, uptime=774043 seconds,
ipv6-prefix=[ ]; mape_auto up=true, uptime=770558 seconds.
The live odhcp6c get_state had:

```text
DHCPV6_STATE: BOUND_PROCESSING
SERVER: fe80::212:e2ff:fe70:5250
PREFIXES: []
ADDRESSES: []
RA_ADDRESSES: one public address, length 64
RA_ROUTES: default via fe80::212:e2ff:fe70:5250, valid 1800
RA_ROUTES: matching on-link public /64, valid 2592000
```

This distinguishes a SLAAC/RA WAN address from a DHCPv6 delegated prefix.
The current statistics were:

```text
dhcp_solicit: 1
dhcp_advertise: 1
dhcp_request: 0
dhcp_renew: 0
dhcp_rebind: 0
dhcp_reply: 9
dhcp_information_request: 9
dhcp_discarded_packets: 0
dhcp_transmit_failures: 0
```

No relevant odhcp6c/NoPrefixAvail lines remained in the current syslog.
These counters establish successful information exchanges and no DHCP
address/prefix lease transaction in this client's lifetime; they do not
retain the ADVERTISE status code.

The fresh capture supplied one upstream RA, at **00:53:19.738271 JST**:

```text
fe80::212:e2ff:fe70:5250 > ff02::1
ICMP6, router advertisement, length 56
hop limit 64, Flags [other stateful], pref medium, router lifetime 1800s
source link-address: 00:12:e2:70:52:50
prefix info: [REDACTED_PUBLIC_PREFIX]/64, Flags [onlink, auto]
valid time 2592000s, preferred time 604800s
```

The retained October 1 capture was re-read, not treated as today's exchange:

```text
02:34:15.441169 upstream RA: public /64, [onlink, auto], router lifetime 1800s
02:34:16.267686 SOLICIT xid=b08e5: IA_NA and IA_PD, automatic prefix request
02:34:16.273791 ADVERTISE xid=b08e5: status-code NoPrefixAvail
02:34:17.432408 INFORMATION-REQUEST xid=1ca212
02:34:17.447247 REPLY xid=1ca212: DNS/search/SNTP, no delegated prefix
```

Source was the same upstream link-local gateway as today's capture.
The complete old capture remains /tmp/direct-onu-dhcpv6.pcap, SHA-256
`10aaba3090a67dc62a896ba523c4295522f8b89aca381c1d366b1fd88d58d793`.
The packet decode prints bad outbound UDP checksums for some transmit
packets, but the matching inbound ADVERTISE has a valid checksum and
transaction ID; no checksum-related failure was inferred.

#### Provider interpretation and verdict

[Yamaha's OCN Virtual Connect configuration guide](https://www.rtpro.yamaha.co.jp/UTM/docs/utx/ocn_mape/index.html)
sections 2-4-1 and 2-5-1 document that FLET'S Hikari Next without Hikari Denwa
uses router advertisements and that No Prefix Available indicates an
RA environment without DHCPv6-PD. Section 2-4-2 distinguishes Hikari Cross,
which can use DHCPv6-PD even without Hikari Denwa. Lack of a phone subscription
alone is therefore not universal proof of no PD.

The exact retail line contract was not inspected. However, today's observed
RA /64, the current automatic PD request with no lease, the older explicit
NoPrefixAvail, and the user's no-Hikari-Denwa answer all fit RA provisioning
rather than a disabled prefix request or a current DNS/WAN failure.
The historical upstream rejection is directly observed; a fresh rejection
was not obtained because the separate client could not register alongside
the live client. No disruptive restart was attempted.

Conclusion: OpenWrt is requesting delegation, but this observed upstream
connection provides an on-link SLAAC /64 and no delegated public prefix.
The LAN's normal DHCPv6/RA server setup has only ULA space to distribute.
This is a mismatch between ordinary downstream prefix-server configuration
and an RA-only uplink, not evidence of a failed upstream IPv6 Internet
connection. Changing only reqprefix or forcing RA default advertisement
does not establish a routed public prefix.

Possible follow-up (not executed): assess RA/DHCPv6 relay and NDP proxy
through both OpenWrt and router-mode BUFFALO, preserving IPv4/MAP-E and the
independent management path. Prefix sharing across two downstream routing
boundaries must be designed and tested; no LAN/WAN bridge, NAT66, guessed
public prefix, or cable change was applied. This investigation does not
establish the cause of the earlier transient phone outage.

Post-diagnostic checks: existing WAN6 client PID unchanged; ping4 3/3 replies,
0% loss, exit 0; router-originated IPv6 HTTPS=200, curl exit 0; uci changes
empty; SSH exit closed normally, exit 0.

#### Saved artifacts and local validation

Copied current capture/client/capture logs with:

```powershell
rtk proxy cmd.exe /c "scp -O -i .local-ssh/id_ed25519_v2 -o BatchMode=yes -o ConnectTimeout=10 root@192.168.1.1:/tmp/pd-probe-20261013.pcap root@192.168.1.1:/tmp/pd-probe-20261013.capture.log root@192.168.1.1:/tmp/pd-probe-20261013.client.log backups/2026-10-13-prefix-delegation/"
rtk proxy powershell -NoProfile -Command "Get-FileHash -Algorithm SHA256 'backups/2026-10-13-prefix-delegation/*'"
```

Both exited 0; copied artifact hashes matched router-side sha256sum.
All artifacts are ignored local files. PCAP contains the actual public
prefix; public identifiers are redacted in this tracked report and captured
text transcript.

| File under backups/2026-10-13-prefix-delegation/ | SHA-256 |
|---|---|
| captured-transcript.txt | c89cd5b653bb1120a44a8969fd38c21c952f94f27a10705b961f5cc2ee8e0a83 |
| pd-probe-20261013.pcap | 1bba7618603a6be10f1152a98a1579a2896ae25acc6f24d4c3ce3e94eea1d061 |
| pd-probe-20261013.capture.log | ba491121a6d7f293234305ef3af768e739cf4bba4dfd2ba4818d5636cb25d2dc |
| pd-probe-20261013.client.log | 38aa9709e0f36f49e3a2afa7b0a0adb536af0c34037ea855ec6cc7d37116fd84 |

Local validation: `rtk git diff --check` passed, exit 0; only the repository's
LF-to-CRLF warnings were emitted.
No tested configuration correction changed the rebuild procedure.

### 2026-10-14 JST - Inspect IPv6 relay readiness and propose settings (read-only)

Topology: direct-ONU OpenWrt eth0; OpenWrt br-lan/eth1 to BUFFALO WAN
192.168.1.2, BUFFALO LAN 192.168.11.1/24. No cable changes. The user supplied
WSR-6000AX8 firmware 1.15 screenshots: IPv4 DHCP WAN 192.168.1.2,
gateway 192.168.1.1, DNS 8.8.8.8/8.8.4.4 manually set plus 192.168.1.1;
IPv6 automatic Internet@Start, bridge permission unchecked, only fd57 ULA,
IPv6 gateway shown as ::/64. These are supplied screenshot observations,
not an authenticated read of BUFFALO configuration by this agent.

The user requested investigation and recommended changes. No router setting
was changed. Existing history edits were preserved. A proposed trial,
exact candidate UCI settings, acceptance checks and rollback requirements
are in [the untested IPv6 relay plan](../plans/ipv6-relay.md).
No backup or rollback was executed because this turn was read-only.

One persistent SSH session used:
`rtk proxy cmd.exe /c "ssh -tt -i .local-ssh/id_ed25519_v2 -o BatchMode=yes -o ConnectTimeout=10 root@192.168.1.1"`,
with authorized read-only network escalation. Router commands in order:

```sh
date -Iseconds; uptime; uci show network.wan6; uci show network.lan; uci show dhcp.lan; uci -q show dhcp.wan6; uci -q show dhcp.wan; uci changes
uci show firewall | grep -E 'zone|forwarding|icmp|ICMP|dhcpv6|DHCPv6|masq6|mtu_fix|network='; echo rc=$?
ubus call network.interface.wan6 status | jsonfilter -e @.up -e @.uptime -e '@["ipv6-address"]' -e '@["ipv6-prefix"]'; ubus call network.interface.mape_auto status | jsonfilter -e @.up -e @.uptime; ip -6 route; echo rc=$?
grep -n -E 'ra|dhcpv6|ndp|master|upstream|ignore' /etc/config/dhcp; apk info -v odhcpd odhcp6c; echo rc=$?
nft list chain inet fw4 input_wan; nft list chain inet fw4 forward_wan; echo rc=$?
apk info -e odhcpd-ipv6only; echo ipv6only_rc=$?; apk info -e odhcpd; echo odhcpd_rc=$?; ubus -v list dhcp | head -n 20; echo rc=$?
uci show firewall.@rule[3]; uci show firewall.@rule[5]; uci show firewall.@rule[6]; sysctl net.ipv6.conf.all.forwarding; echo rc=$?
ip -4 route; ping -c 3 -W 2 192.168.1.2; echo buffalo_ping_rc=$?; ping -c 3 -W 2 1.1.1.1; echo internet_ping_rc=$?
curl -6 -sS --max-time 15 -o /dev/null -w 'IPv6_HTTPS=%{http_code}\n' https://example.com; echo curl6_rc=$?
uci -q show dhcp.wan6; echo wan6_section_rc=$?; uci changes; echo changes_rc=$?; date -Iseconds
uci -q show firewall.Allow_DHCPv6_Relay; echo proposed_rule_exists_rc=$?; uci -q show dhcp.wan6; echo proposed_wan6_section_exists_rc=$?; exit
```

Observed approximately 00:09:56-00:11:14 JST:

```text
network.wan6.device='eth0'
network.wan6.proto='dhcpv6'
network.wan6.iface_map='1'
network.lan.device='br-lan'
network.lan.proto='static'
network.lan.ipaddr='192.168.1.1/24'
network.lan.ip6assign='60'
dhcp.lan.dhcpv4='server'
dhcp.lan.dhcpv6='server'
dhcp.lan.ra='server'
dhcp.lan.ra_slaac='1'
dhcp.lan.ra_flags='managed-config' 'other-config'
dhcp.wan.interface='wan'
dhcp.wan.ignore='1'
wan6_section_rc=1
changes_rc=0
proposed_rule_exists_rc=1
proposed_wan6_section_exists_rc=1
```

No upstream dhcp.wan6 relay/master section exists. No LAN ndp relay exists.
Current WAN6 is up, uptime 857741, has public /64 WAN address but
ipv6-prefix=[ ]. MAP-E is up, uptime 854256. IPv4 default is map-mape_auto.
ULA /62 route remains via BUFFALO's link-local address.

Current firewall includes WAN networks wan, wan6, mape_auto; WAN input
REJECT, forward DROP, IPv4 masq=1 and mtu_fix=1. LAN-to-WAN forwarding
exists. IPv6 all.forwarding=1. Allow-DHCPv6 accepts UDP destination 546;
live input_wan has no explicit UDP destination 547 allowance.
Allow-ICMPv6-Input includes RS/RA/NS/NA and packet-too-big. Existing IPv6
forward ICMP rules remain. The proposed relay rule accepts only IPv6
UDP source 547 to local destination 547 from the WAN zone; it does not
open general inbound forwarding.

Package query `apk info -v odhcpd odhcp6c` printed missing cached repository
index warnings, found odhcp6c information, and exited 1. Corrected targeted
local package checks found odhcpd-ipv6only (exit 0); full odhcpd is absent
(exit 1). Existing odhcpd DHCPv6/RA ubus methods were present.
No package install/update was needed or performed.

Checks: BUFFALO WAN ping 3/3, zero loss, exit 0; public IPv4 ping 3/3,
zero loss, exit 0; router IPv6 HTTPS=200, curl exit 0. UCI changes empty.
SSH exit closed normally, exit 0. Grouped pipeline rc values report only
the last command's status; independent ping/curl statuses were recorded.
The final ping reply and IPv6 HTTPS output arrived in the subsequent
read-only command response; both successful results are recorded here.

Recommendation, not applied:
- Create DHCP service section wan6 with interface=wan6, master=1,
  RA/DHCPv6/NDP relay and ignore=1 to suppress dnsmasq IPv4 service.
- Change LAN RA and DHCPv6 services from server to relay, add NDP relay.
- Add the scoped WAN DHCPv6 relay reply rule described above.
- Select BUFFALO Internet > IPv6 > NDプロキシを使用する.
- Retain working IPv4/MAP-E and router-mode BUFFALO with 192.168.11.0/24.
  Do not force a guessed delegated prefix or ra_default.

Primary references:
[odhcpd README](https://github.com/openwrt/odhcpd/blob/master/README.md),
[odhcpd config parser](https://github.com/openwrt/odhcpd/blob/master/src/config.c),
[DHCPv6 relay implementation](https://github.com/openwrt/odhcpd/blob/master/src/dhcpv6.c),
[BUFFALO ND proxy instructions](https://www.buffalo.jp/support/faq/detail/16428.html).
The parser explicitly enables IPv6 services when configured despite the
ignore flag. Upstream source was used for intended behavior, not as proof
that the untested proposal works on the installed firmware.

The two-proxy return path, relayed DNS, unsolicited IPv6 inbound protection,
BUFFALO/phone public addresses and actual phone IPv6 HTTPS remain untested.
These require a staged deployment and client-side validation.
This recommendation does not establish the cause of the earlier outage.
No tested correction changed the rebuild manual.

Ignored bounded PTY transcript:
`backups/2026-10-14-ipv6-settings/captured-transcript.txt`, SHA-256
`146cca8b18a048642b7573be9002d5865bf41d4ac9176eee7f481773381d294b`.
Public prefix redacted; this is not a complete router log export.
Local `rtk git diff --check` passed, exit 0, with LF-to-CRLF warnings only.


### 2026-10-14 JST - Apply OpenWrt IPv6 relay; BUFFALO change pending

The user explicitly authorized updating OpenWrt first, followed by their
manual BUFFALO change. Applied the prepared RA/DHCPv6/NDP relay and scoped
UDP 547 rule. No BUFFALO setting, WAN protocol, MAP-E rule, network config,
or physical cable was changed by the agent.

Topology initially OpenWrt-primary with BUFFALO WAN 192.168.1.2 and the PC
192.168.11.97 behind BUFFALO. At validation the PC's original Ethernet
was disconnected and its second Ethernet was directly on OpenWrt as
192.168.1.157; this was observed via ipconfig/SSH source, not an agent cable
action. Wi-Fi had a separate 10.175.121.x connection, so client HTTPS tests
explicitly bound their source address to the wired test path.

Initial date 00:56:18 JST, no pending UCI changes, proposed section/rule
names absent (uci query exit 1 each). WAN6 and MAP-E both up, default route
map-mape_auto, BUFFALO IPv4 lease confirmed. BUFFALO ping 3/3 and router
IPv4 HTTPS 200, both exit 0.

#### Backup, commands, and safeguard

Opened one persistent SSH session with the approved rtk/cmd.exe wrapper.
Saved DHCP/firewall/network to **/root/ipv6-relay-20261014.ddnGFC** and copied
all three files to ignored **backups/2026-10-14-ipv6-relay/** before mutation.
Router/local hashes matched.

Router preflight and backup commands in order:

```sh
date -Iseconds; uci changes; uci show dhcp.lan; uci -q show dhcp.wan6; echo wan6_section_rc=$?; uci -q show firewall.Allow_DHCPv6_Relay; echo rule_exists_rc=$?
ubus call network.interface.wan6 status | jsonfilter -e @.up -e @.uptime -e '@["ipv6-prefix"]'; ubus call network.interface.mape_auto status | jsonfilter -e @.up -e @.uptime; ip -4 route; cat /tmp/dhcp.leases; command -v setsid
echo SSH_CONNECTION=$SSH_CONNECTION; ping -c 3 -W 2 192.168.1.2; echo buffalo_rc=$?; curl -4 -sS --max-time 15 -o /dev/null -w 'IPv4_HTTPS=%{http_code}\n' https://example.com; echo ipv4_rc=$?
relay_backup=$(mktemp -d /root/ipv6-relay-20261014.XXXXXX); echo backup_dir=$relay_backup; cp -p /etc/config/dhcp "$relay_backup/dhcp"; cp -p /etc/config/firewall "$relay_backup/firewall"; cp -p /etc/config/network "$relay_backup/network"; sha256sum "$relay_backup/dhcp" "$relay_backup/firewall" "$relay_backup/network"
```

Local Get-NetIPAddress failed with access denied (exit 1); corrected with
rtk proxy ipconfig (exit 0). The initial SSH source was 192.168.1.2, not
independent wired management. For the IPv6-only settings change, a detached
300-second rollback was staged before application; by subsequent validation,
independent wired management was observed. The plan's original independent
management precondition was not established before the first mutation.

Prepared and copied apply.sh, rollback.sh, rollback-timer.sh into the backup
directory. The apply script checks empty pending UCI changes and byte-for-byte
DHCP/firewall match to backup, uses set -eu and set -x, stages the exact
settings below, runs fw4 check, commits DHCP/firewall, reloads firewall and
restarts odhcpd. Its error trap calls rollback.sh on failure. Full script
and log are saved locally and on the router.

Rollback script reverts pending DHCP/firewall changes, copies the saved
files, reloads firewall and restarts odhcpd, logging both service statuses.
Timer sleeps 300 seconds and restores only if keep-settings is absent.
setsid spawned a detached child (PID 20581); launcher PID 20580 exiting
was not timer completion. The child and sleep were observed running.

```sh
sh -n "$relay_backup/apply.sh"; echo apply_syntax_rc=$?; sh -n "$relay_backup/rollback.sh"; echo rollback_syntax_rc=$?; sh -n "$relay_backup/rollback-timer.sh"; echo timer_syntax_rc=$?; sha256sum "$relay_backup/"*.sh
setsid sh "$relay_backup/rollback-timer.sh" "$relay_backup" </dev/null >"$relay_backup/timer.log" 2>&1 & relay_timer_pid=$!; echo rollback_timer_pid=$relay_timer_pid; echo "$relay_timer_pid" >"$relay_backup/timer.pid"
sh "$relay_backup/apply.sh" "$relay_backup" >"$relay_backup/apply.log" 2>&1; relay_apply_rc=$?; echo apply_rc=$relay_apply_rc; tail -n 8 "$relay_backup/apply.log"
```

All three sh -n checks returned 0; script hashes matched local files.
apply_rc=0. fw4 check passed, then commits/reload/restart all completed
under set -e. Existing generated MAP ICMP port warnings recurred; they did
not prevent the ruleset check. Existing custom MAP ICMP SNAT was preserved.

Committed changes (only these differences were present in local Git
no-index comparisons):

```diff
-dhcp.lan.ra='server'
-dhcp.lan.dhcpv6='server'
+dhcp.lan.ra='relay'
+dhcp.lan.dhcpv6='relay'
+dhcp.lan.ndp='relay'
+dhcp.wan6=dhcp
+dhcp.wan6.interface='wan6'
+dhcp.wan6.ignore='1'
+dhcp.wan6.master='1'
+dhcp.wan6.ra='relay'
+dhcp.wan6.dhcpv6='relay'
+dhcp.wan6.ndp='relay'
+firewall.Allow_DHCPv6_Relay=rule
+firewall.Allow_DHCPv6_Relay.name='Allow-DHCPv6-Relay'
+firewall.Allow_DHCPv6_Relay.src='wan'
+firewall.Allow_DHCPv6_Relay.proto='udp'
+firewall.Allow_DHCPv6_Relay.src_port='547'
+firewall.Allow_DHCPv6_Relay.dest_port='547'
+firewall.Allow_DHCPv6_Relay.family='ipv6'
+firewall.Allow_DHCPv6_Relay.target='ACCEPT'
```

#### Verification, failures, and corrections

The original SSH session reset before the first post-change query could
complete. Reconnected once because that session ended. A first PC IPv4 curl
bound to the previous 192.168.11.97 address failed (curl 7, HTTP 000,
tool exit 1). Subsequent ipconfig showed that address/interface was no
longer connected; it was replaced by wired 192.168.1.157 on OpenWrt LAN.
Do not treat the obsolete-source test as a proven forwarding regression.

Post-change router commands:

```sh
relay_backup=/root/ipv6-relay-20261014.ddnGFC; date -Iseconds; ps ww | grep -E '[r]ollback-timer|[s]leep 300|[o]dhcpd'; uci show dhcp.wan6; uci changes
ubus call network.interface.wan6 status | jsonfilter -e @.up -e @.uptime; ubus call network.interface.mape_auto status | jsonfilter -e @.up -e @.uptime; ip -4 route; nft list chain inet fw4 input_wan | grep -E '547|546'; echo rc=$?
ping -c 3 -W 2 1.1.1.1; echo ping4_rc=$?; curl -4 -sS --max-time 10 -o /dev/null -w 'IPv4_HTTPS=%{http_code}\n' https://example.com; echo curl4_rc=$?; curl -6 -sS --max-time 10 -o /dev/null -w 'IPv6_HTTPS=%{http_code}\n' https://example.com; echo curl6_rc=$?
uci show dhcp.lan; sha256sum /etc/config/network; ubus call service list '{"name":"odhcpd"}' | head -n 22; logread | tail -n 12
touch "$relay_backup/keep-settings"; echo keep_rc=$?; test -f "$relay_backup/keep-settings"; echo timer_disarmed_rc=$?; test -f "$relay_backup/rollback.log"; echo rollback_log_exists_rc=$?; date -Iseconds
```

Observed at 01:02:14: odhcpd running PID 20685, WAN6 up uptime 860874,
MAP-E up uptime 857389. The default remained map-mape_auto.
Live input_wan had both the original UDP 546 allowance and the new
UDP source/destination 547 relay allowance. Public IPv4 ping 3/3, zero loss,
exit 0; router IPv4 HTTPS 200 and IPv6 HTTPS 200, curl exits 0.
Network SHA-256 unchanged. uci changes empty.

At 01:02:46 keep marker creation and existence checks both returned 0.
Rollback log existence returned 1 (absent); no rollback occurred. The
detached timer subsequently exited. The update remains applied.

New PC ipconfig: wired IPv4 192.168.1.157, public SLAAC IPv6 addresses in the
upstream /64, IPv6 gateway OpenWrt eth1 link-local, IPv4 gateway 192.168.1.1.
Final client checks used the corrected wired sources:

```text
rtk proxy cmd.exe /c "curl.exe --ipv4 --interface 192.168.1.157 --silent --show-error --max-time 15 --output NUL --write-out IPv4_HTTPS=%{http_code} https://example.com"
IPv4_HTTPS=200; exit 0

rtk proxy cmd.exe /c "curl.exe --ipv6 --interface <OBSERVED_WIRED_PUBLIC_IPV6> --silent --show-error --max-time 15 --output NUL --write-out IPv6_HTTPS=%{http_code} https://example.com"
IPv6_HTTPS=200; exit 0
```

The IPv6 address argument was the actual public address observed by ipconfig,
redacted here. Source binding excludes the PC's separate Wi-Fi IPv4 path.

Additional router commands:

```sh
tcpdump -ni br-lan -s 0 -U -c 8 -w "$relay_backup/lan-ra.pcap" 'icmp6 and ip6[40] == 134' >"$relay_backup/lan-ra-capture.log" 2>&1 & relay_capture_pid=$!; echo capture_pid=$relay_capture_pid
(sleep 60; kill -INT "$relay_capture_pid" 2>/dev/null) & echo capture_timer_pid=$!
diff -u "$relay_backup/dhcp" /etc/config/dhcp; diff -u "$relay_backup/firewall" /etc/config/firewall; cmp -s "$relay_backup/network" /etc/config/network; echo network_unchanged_rc=$?; uci changes; nslookup example.com 127.0.0.1; echo dns_rc=$?
cat "$relay_backup/lan-ra-capture.log"; tcpdump -nn -vvv -r "$relay_backup/lan-ra.pcap" 2>/dev/null | head -n 16; ps ww | grep '[r]ollback-timer'; test -f "$relay_backup/keep-settings"; echo keep_marker_rc=$?; date -Iseconds
wait "$relay_capture_pid"; echo capture_exit=$?; cat "$relay_backup/lan-ra-capture.log"; uci changes; test -f "$relay_backup/rollback.log"; echo rollback_log_exists_rc=$?; sha256sum "$relay_backup/lan-ra.pcap" "$relay_backup/lan-ra-capture.log" "$relay_backup/apply.log"
exit
```

Router diff is unavailable; both attempts failed before comparison.
cmp network returned 0; nslookup returned A/AAAA and dns_rc=0.
Copied before/after DHCP/firewall files for local comparisons.
rtk git diff --no-index was rejected by shim parameter binding; corrected
with rtk proxy cmd.exe /c "git diff --no-index -- ...". Both corrected Git
diffs exited 1 as expected for differing files and showed only the intended
changes listed above.

LAN RA capture completed exit 0: 1 packet captured/received, zero dropped.
Relevant verbatim decode at 01:03:09.988547, public prefix redacted:

```text
OpenWrt eth1 link-local > ff02::1: ICMP6, router advertisement, length 56
hop limit 64, Flags [other stateful], pref medium, router lifetime 1800s
prefix info option: [PUBLIC_UPSTREAM_PREFIX]/64, Flags [auto]
valid time 2592000s, preferred time 604800s
```

The relayed public prefix is SLAAC-enabled and deliberately not marked
on-link in this LAN advertisement. Direct-LAN source-bound IPv6 HTTPS
passed, proving a usable client data path, beyond merely seeing the RA.

SSH exit 0. No manual or automatic rollback executed. Verified manual
rollback command is available but unrun:

```sh
sh /root/ipv6-relay-20261014.ddnGFC/rollback.sh /root/ipv6-relay-20261014.ddnGFC
```

#### Artifacts and handoff

All files below are under ignored backups/2026-10-14-ipv6-relay/.
Router copies remain under /root/ipv6-relay-20261014.ddnGFC.
SCP copies exited 0. Configuration hashes, full apply log, and completed
LAN capture hashes were checked against router-side values.

| Artifact | SHA-256 |
|---|---|
| dhcp | d010aabf0e6fc05235c4dfda0b325a511fa2c6528729d239fc81f8c8b1ac9bef |
| firewall | 7913b92a9b96df14d2e9dc8394292c3bc56e24ed7d5e715a2ef6b8a0f9d2fda4 |
| network | 1e0c63ba79568b9a7db91e9d3ba4d8df1598ff880c413e21ec66117f4b39e847 |
| dhcp-after | 4b79c410362bbae08813112a9b4547b98e6c6400525e73a966545843ceeb6b30 |
| firewall-after | c453154a646539461bf0048a7dc4c037cd10067c1cf79244759957d5b327f60e |
| apply.sh | cda7dd749183571a968cd47f4306089d2d4ad1a5c507079e8e9f762d133e409f |
| rollback.sh | 6dfd3ef2a177670c886ec0a922b69cf316ee2cf333159f7d8fe26855db645f3a |
| rollback-timer.sh | b7a9a84e1a3348f9812f577eace487aa3d746f5d3461abf1c4cce55e981e38e4 |
| apply.log | 3ea1a57c72a813b2ab7b9fe709e9c44e6da370cd491fab6c19c6806b205ec586 |
| lan-ra.pcap | 3f540d7e0278ae703c8d252981f7778125bd2a975249d32327fdb7add6ba114f |
| lan-ra-capture.log | ffc006fbf1162750f23fd2aed7b6ff35d02eaa208f5dcc12fb3336a10a8b603a |

Verdict: OpenWrt stage PASS for committed relay settings, firewall check,
service operation, router DNS/IPv4/IPv6, public LAN RA, and wired-client
IPv4/IPv6 HTTPS. BUFFALO ND proxy setting is pending user action.
DHCPv6 relay response/DNS behavior through BUFFALO, phone public IPv6,
phone IPv6 HTTPS, unsolicited inbound IPv6 rejection, and reboot persistence
remain untested. The earlier phone outage cause remains unresolved.
Plan status updated to OpenWrt applied / downstream acceptance pending;
the complete two-router procedure is not marked verified.

Local documentation validation: `rtk git diff --check` passed, exit 0;
LF-to-CRLF warnings only.

### 2026-10-14 JST - BUFFALO automatic ND proxy and phone IPv6 failure follow-up (read-only)

Supplied screenshots after the OpenWrt relay update:
- BUFFALO remained in Internet@Start automatic mode and reported ND proxy,
  a public /64 address and OpenWrt eth1 link-local IPv6 gateway. The user
  said they had not manually changed the BUFFALO IPv6 setting.
- Phone IPv4 192.168.11.25, IPv4 gateway/DNS 192.168.11.1, public IPv6
  addresses in the upstream /64, gateway reported N/A by the phone app,
  IPv6 DNS equal to OpenWrt's eth1 link-local address.
- Phone test-ipv6.com screenshot reports no IPv6 detected, score 0/10,
  working OCN IPv4. Its DNS-server IPv6 check passed; that test concerns
  the resolver's connectivity, not proof of phone IPv6 data connectivity.
Cellular/VPN-disabled state during that screenshot was not independently
confirmed. The phone/browser failure remains an observed user test result.

No router configuration was changed this turn. Current OpenWrt relay
configuration matched the applied settings, uci changes empty.
Actual test topology: PC wired to BUFFALO LAN as 192.168.11.97,
default IPv4 gateway 192.168.11.1, public IPv6 address and IPv6 default route
via BUFFALO link-local. Wi-Fi/VPN adapters were disconnected in ipconfig.
One persistent read-only SSH session used the usual rtk/cmd wrapper.

Read-only commands and bounded captures:

```sh
date -Iseconds; uci show dhcp.wan6; uci show dhcp.lan; uci changes; ip -6 route; ip -6 neigh; echo rc=$?
pd_diag=$(mktemp -d /root/ipv6-buffalo-20261014.XXXXXX); echo diagnostic_dir=$pd_diag; tcpdump -ni br-lan -s 160 -U -c 100 -w "$pd_diag/lan.pcap" 'icmp6 or host 2400:4050:c340:1600:5de7:7be7:d472:3843' >"$pd_diag/lan.log" 2>&1 & pd_lan_pid=$!
tcpdump -ni eth0 -s 160 -U -c 100 -w "$pd_diag/wan.pcap" 'icmp6 or host 2400:4050:c340:1600:5de7:7be7:d472:3843' >"$pd_diag/wan.log" 2>&1 & pd_wan_pid=$!; (sleep 35; kill -INT "$pd_lan_pid" "$pd_wan_pid" 2>/dev/null) & echo bounded_capture_timer=$!
ping -6 -c 3 -W 2 2400:4050:c340:1600:44aa:1cff:fe67:f615; echo phone_stable_ping_rc=$?; ping -6 -c 3 -W 2 2400:4050:c340:1600:6519:2f8a:d367:dae8; echo phone_temporary_ping_rc=$?
ip -6 route | grep -E '44aa|6519|5de7'; ip -6 neigh | grep -E '44aa|6519|5de7'; echo rc=$?
wait "$pd_lan_pid"; echo lan_capture_exit=$?; wait "$pd_wan_pid"; echo wan_capture_exit=$?; cat "$pd_diag/lan.log" "$pd_diag/wan.log"
tcpdump -nn -r "$pd_diag/lan.pcap" 'host 2400:4050:c340:1600:5de7:7be7:d472:3843' 2>/dev/null | head -n 8; tcpdump -nn -r "$pd_diag/wan.pcap" 'host 2400:4050:c340:1600:5de7:7be7:d472:3843' 2>/dev/null | head -n 8; sha256sum "$pd_diag/"*.pcap; uci changes
tcpdump -nn -r "$pd_diag/lan.pcap" 'icmp6' 2>/dev/null | grep -E '44aa|6519|5de7' | head -n 12; ip -6 route | grep -E '44aa|6519|5de7'; uci changes; date -Iseconds
```

Client commands (public IPv6 source redacted here):

```text
rtk proxy ipconfig
exit 0; wired 192.168.11.97, public IPv6, BUFFALO gateways.

rtk proxy cmd.exe /c "netsh interface ipv6 show route"
exit 0; ::/0 on interface 11 via fe80::6ae1:dcff:fe37:1d10.

rtk proxy cmd.exe /c "curl.exe --ipv6 --interface <OBSERVED_PUBLIC_PC_IPV6> --silent --show-error --connect-timeout 8 --max-time 12 --output NUL --write-out IPv6_HTTPS=%{http_code} https://example.com"
IPv6_HTTPS=200, exit 0.

rtk proxy cmd.exe /c "curl.exe --ipv4 --interface 192.168.11.97 --silent --show-error --max-time 12 --output NUL --write-out IPv4_HTTPS=%{http_code} https://example.com"
IPv4_HTTPS=200, exit 0.
```

Both curl commands ran during a 35-second capture on br-lan and eth0.
Snapshots used snaplen 160 and limit 100 packets, including ICMPv6 and the
specified PC address. Final captures: LAN 45 packets, WAN 36 packets,
zero dropped by kernel. Background jobs completed; later wait attempts
returned 127 because the exited jobs were no longer waitable. This is
not their original exit code; the capture logs contain the completed counts.

Relevant decoded evidence at 01:16:40-01:16:42 JST, public addresses redacted:

```text
LAN: PC_PUBLIC:52379 > SERVER_V6:443 TCP SYN
LAN: OpenWrt link-local > multicast: NS who has PC_PUBLIC
LAN: BUFFALO link-local > OpenWrt link-local: NA target PC_PUBLIC
LAN: OpenWrt link-local > PC_PUBLIC: echo request
LAN: PC_PUBLIC > OpenWrt link-local: echo reply
WAN: PC_PUBLIC:52379 > SERVER_V6:443 TCP SYN
WAN: SERVER_V6:443 > PC_PUBLIC:52379 TCP SYN-ACK
WAN: PC_PUBLIC:52379 > SERVER_V6:443 TCP ACK
```

The PC's /128 route was learned on br-lan, with neighbor MAC
68:e1:dc:37:1d:10 (BUFFALO). Source-bound HTTPS success establishes a
working IPv6 data path from a client behind BUFFALO, not only from OpenWrt.
It does not establish the same result for the phone.

Pings to both phone IPv6 addresses supplied in the screenshot returned
0/3, exit 1 each. No corresponding br-lan host route was observed; their
neighbors were incomplete/failed on eth0. This is consistent with no
currently learned downstream path for those addresses, but does not prove
a missing phone route, stale screenshot, ICMP blocking, or specific cause.
The phone may not have been actively sending IPv6 during the capture.
No static routes or neighbor entries were added to mask the issue.

At 01:18:54, PC host route remained on br-lan and uci changes was empty.
Requested a phone Wi-Fi reconnect and repeat test with VPN/cellular
disabled, plus comparison with another browser. Results are pending.
The link-local DNS advertisement across the second router remains a
candidate issue to check; the working PC path and IPv4 DNS availability
do not prove the phone's resolver selection is healthy.

Documentation correction: the relay plan now says to retain BUFFALO
automatic mode when it selects ND proxy, rather than requiring a manual
selection. It records BUFFALO-LAN PC success and unresolved phone failure.
Do not mark the phone or full rollout acceptance complete.

Ignored local artifacts, copied by authorized read-only SCP from
/root/ipv6-buffalo-20261014.KoBbeK to
backups/2026-10-14-buffalo-ipv6/ (SCP exit 0):

| Artifact | SHA-256 |
|---|---|
| captured-transcript.txt | 4a4f748392693a4137c88937b8f53e3a2c2c15a2dbc5dfc543ff10611efeaadd |
| lan.pcap | 7c6ab19bdac324731b0a70774f200a0d3d2b9273dde4ba161b568c963646841c |
| wan.pcap | 2017890b2d889af5dcf5a314ff58f17c68d622418fd8dba4c308e231702eefc8 |
| lan.log | de713cc919a59225c70c1a3f59621d702b0b205a1b89acf169020b1d011596db |
| wan.log | 3c38d744f9b166a3b2a716e48b91eeafc7bd542eca16bfce6e00c6eabe438015 |

PCAP hashes match the router-side values. Text transcript public prefix
redacted; PCAPs contain original addresses and remain ignored.
A combined memory regex query failed at the rtk wrapper pipe parsing
before reading memory; no memory-derived diagnosis was used this turn.
No rollback, firewall reload, odhcpd restart, cable move or router setting
change was performed. Local `rtk git diff --check` passed, exit 0;
LF-to-CRLF warnings only. SSH remains available for the pending phone retest.

### 2026-10-14 JST - Android retest remains IPv4-only; DNS checks (read-only)

The user confirmed that Wi-Fi reconnect with VPN/cellular disabled still
gave 0/10 in both browsers, and identified the phone as Android.
They referred to current IP status and Tests Run screenshots, but those
images had not arrived when this record was written. Do not infer the
current phone address or individual failed test details from that text.

Reused the existing persistent SSH session; no network/service/router
configuration changed. At 01:23:04 JST, WAN6 up, uptime 862122,
uci changes empty. Neither previously supplied phone public address had a
learned br-lan /128 route; both eth0 neighbor entries were FAILED.
Those addresses may no longer be current after reconnecting.

Local ipconfig still showed PC wired to BUFFALO LAN, public IPv6 and
BUFFALO IPv4/IPv6 gateways. Its configured IPv6 DNS server was the same
OpenWrt eth1 link-local address reported by the phone app.
Read-only commands:

```text
rtk proxy ipconfig
exit 0; PC remains on 192.168.11.97 behind BUFFALO.

rtk proxy cmd.exe /c "netsh interface ipv6 show dnsservers"
exit 0; wired interface IPv6 DNS = fe80::82ee:73ff:feab:4af1%11.

rtk proxy cmd.exe /c "nslookup -timeout=2 -retry=1 -type=AAAA example.com fe80::82ee:73ff:feab:4af1%11"
exit 0; example.com AAAA answers 2606:4700:10::ac42:93f3 and 2606:4700:10::6814:179a.

rtk proxy cmd.exe /c "nslookup -timeout=2 -retry=1 -type=AAAA example.com fd57:3a20:c1d6::1"
exit 0; same AAAA answers.

rtk proxy cmd.exe /c "nslookup -timeout=2 -retry=1 -type=AAAA example.com 192.168.11.1"
exit 0; same AAAA answers.
```

These tests show the advertised link-local DNS endpoint is reachable from
this BUFFALO client through the proxy arrangement. The endpoint's address
scope alone therefore does not prove phone DNS failure. This is evidence
for the wired PC, not for Android's resolver selection or Wi-Fi path.
The earlier statement that link-local DNS could not be reached across
BUFFALO was too strong for a proxy configuration; direct routing
restrictions alone do not establish the observed behavior here.

Optional local capture-tool discovery: where tshark.exe returned not found,
exit 1; pktmon status returned access denied, exit 1. No local packet
capture was started and no driver/service setting was changed.
No escalation or install was needed for the completed DNS checks.

Router follow-up:
`uci show dhcp.lan; ubus call network.interface.wan6 status | jsonfilter -e '@["dns-server"]'; echo rc=$?`
returned current relay settings and upstream DNS
2404:1a8:7f01:b::3 / 2404:1a8:7f01:a::3, rc 0.

Verdict: IPv6 path and DNS from the wired BUFFALO client work, but Android
still reports IPv4-only in both browsers. Phone's current addresses,
default route and detailed test failures remain needed before choosing a
further router change. No automatic/manual rollback or setting change
performed; SSH retained for continuation. Local `rtk git diff --check`
passed, exit 0, with LF-to-CRLF warnings only.

### 2026-10-14 JST - Current Android screenshots and IPv6-only page test (read-only)

The newly received screenshots show Android Wi-Fi IPv4 192.168.11.10,
gateway/DNS 192.168.11.1, two public IPv6 addresses in the upstream /64
with suffixes 371c:c3ed:851f:9e8e and c426:9cd5:c745:c5b4,
link-local suffix f7c7:aebb:df83:9f55, IPv6 gateway shown N/A,
IPv6 DNS OpenWrt eth1 link-local. External IPv6 is shown N/A.
Previous phone suffixes 44aa/6519 are stale and must not be used for new
correlated testing.

Tests Run screenshot: IPv4 and dual-stack tests pass using IPv4; IPv6 DNS
record, IPv6 large packet, and IPv6 provider lookup fail. The resolver's
IPv6 test passes using IPv4. This does not identify whether DNS, Android's
route, BUFFALO Wi-Fi forwarding, or neighbor discovery is responsible.
Phone confirmed on main Wi-Fi, not a guest SSID.

Reused SSH session. Created /root/ipv6-android-20261014.CNjiPm and performed
bounded captures; no router configuration changes or service restarts.

First capture commands:

```sh
phone_diag=$(mktemp -d /root/ipv6-android-20261014.XXXXXX); echo diagnostic_dir=$phone_diag; date -Iseconds; ip -6 route | grep -E '371c|c426'; ip -6 neigh | grep -E '371c|c426|f7c7'
tcpdump -ni br-lan -s 160 -U -c 150 -w "$phone_diag/lan.pcap" 'icmp6 or host 2400:4050:c340:1600:371c:c3ed:851f:9e8e or host 2400:4050:c340:1600:c426:9cd5:c745:c5b4' >"$phone_diag/lan.log" 2>&1 & phone_lan_pid=$!
tcpdump -ni eth0 -s 160 -U -c 150 -w "$phone_diag/wan.pcap" 'icmp6 or host 2400:4050:c340:1600:371c:c3ed:851f:9e8e or host 2400:4050:c340:1600:c426:9cd5:c745:c5b4' >"$phone_diag/wan.log" 2>&1 & phone_wan_pid=$!; (sleep 60; kill -INT "$phone_lan_pid" "$phone_wan_pid" 2>/dev/null) & echo capture_timer=$!
ping -6 -I br-lan -c 3 -W 2 2400:4050:c340:1600:371c:c3ed:851f:9e8e; echo phone_lan_ping_rc=$?; ping -6 -I br-lan -c 3 -W 2 2400:4050:c340:1600:c426:9cd5:c745:c5b4; echo phone_temp_lan_ping_rc=$?
ip -6 route | grep -E '371c|c426'; ip -6 neigh | grep -E '371c|c426'; echo rc=$?
tcpdump -nn -r "$phone_diag/lan.pcap" 2>/dev/null | grep -E '371c|c426|router advertisement' | head -n 18; tcpdump -nn -r "$phone_diag/wan.pcap" 2>/dev/null | grep -E '371c|c426' | head -n 12
tcpdump -nn -r "$phone_diag/lan.pcap" 'host 2400:4050:c340:1600:371c:c3ed:851f:9e8e or host 2400:4050:c340:1600:c426:9cd5:c745:c5b4' 2>/dev/null | wc -l; tcpdump -nn -r "$phone_diag/wan.pcap" 'host 2400:4050:c340:1600:371c:c3ed:851f:9e8e or host 2400:4050:c340:1600:c426:9cd5:c745:c5b4' 2>/dev/null | wc -l
sha256sum "$phone_diag/"*.pcap; ip -6 route | grep -E '371c|c426'; uci changes; date -Iseconds
```

The first 60-second capture yielded LAN 102 packets and WAN 23 packets;
received-by-filter 127/25, kernel drops 0/0. No packets whose IPv6 source
or destination was either current phone address were found in either
capture (both decoded line counts 0). ICMPv6 from other clients was captured.
The user's fresh reload reply arrived after this capture ended, so this
absence is not treated as a capture of that reload.

Forced-interface router pings immediately failed with Network unreachable,
exit 1. No downstream /128 route existed for these addresses, so forcing
br-lan could not select a usable route; this failure is not a phone reachability
test and did not exercise the desired NS/NA exchange. No temporary route
was added.

Started a second five-minute, phone-address-only capture (snaplen 128,
limit 2500) on br-lan and eth0 at 01:29:46 JST:

```sh
tcpdump -ni br-lan -s 128 -U -c 2500 -w "$phone_diag/phone-live-lan.pcap" 'host 2400:4050:c340:1600:371c:c3ed:851f:9e8e or host 2400:4050:c340:1600:c426:9cd5:c745:c5b4' >"$phone_diag/phone-live-lan.log" 2>&1 & phone_live_lan=$!
tcpdump -ni eth0 -s 128 -U -c 2500 -w "$phone_diag/phone-live-wan.pcap" 'host 2400:4050:c340:1600:371c:c3ed:851f:9e8e or host 2400:4050:c340:1600:c426:9cd5:c745:c5b4' >"$phone_diag/phone-live-wan.log" 2>&1 & phone_live_wan=$!
(sleep 300; kill -INT "$phone_live_lan" "$phone_live_wan" 2>/dev/null) & echo capture_timer=$!; date -Iseconds
```

User initially opened ipv6test.google.com and saw No problems detected.
[Google's page](https://ipv6test.google.com/) pairs that result with no IPv6
but working access to dual-stack sites; it is not an IPv6 success result.
The user then opened exactly https://ipv6.google.com/ and confirmed failure.
This occurred during the second capture window. Reads at 01:31:04,
01:32:41 and 01:33:33 showed no decoded packets from either current phone
address. No br-lan /128 phone route was observed. This narrows the location
to before the OpenWrt LAN capture point for these addresses, but does not
prove the phone had no default route or locate the precise failure.

Comparison tests from the wired BUFFALO client:

```text
nslookup -timeout=2 -retry=1 -type=A ipv6.google.com 192.168.11.1
No A address returned; exit 0.

nslookup -timeout=2 -retry=1 -type=AAAA ipv6.google.com 192.168.11.1
AAAA addresses returned; exit 0.

curl.exe --ipv6 --interface <PUBLIC_WIRED_PC_IPV6> --silent --show-error --max-time 12 --output NUL --write-out Google_IPv6_HTTPS=%{http_code} https://ipv6.google.com/
Google_IPv6_HTTPS=200; exit 0.

ping.exe -6 -S <PUBLIC_WIRED_PC_IPV6> -n 3 -w 1500 2606:4700:4700::1111
3/3 replies, zero loss, 4 ms; exit 0.
```

All local commands used rtk proxy cmd.exe /c; network tests were approved
read-only diagnostics. Asked the user to run a numeric IPv6 ping from the
phone to distinguish name resolution from routing. Its result is pending
at this point. Phone's app supplies the Ping tool documented by
[Network Analyzer Android help](https://techet.net/netanalyzer/help-android);
app identification from the screenshot is an inference, not user confirmation.

Windows capture discovery: pktmon start help succeeded; pktmon status
returned access denied even under available elevated tool execution.
No Windows capture was started. This is a local privilege limitation, not
an automatic approval rejection or proof of a router issue.

First completed captures copied to ignored backups/2026-10-14-android-ipv6/,
SCP exit 0, matching router hashes:

| File | SHA-256 |
|---|---|
| captured-transcript.txt | 9a7a7f5439e8219c8e10c09fc56148a9c9f2e08159d28eed02f375cbd9ae304e |
| lan.pcap | 19ae48dc6ef097b3e9446fae7d622bf19c2d347d765e0457e353a87b7e9b885b |
| wan.pcap | ed323a8f0e6be52f3ffc1e3300ffcdb8e8a7e646b600f570dd7ff8ba1c2697e3 |
| lan.log | 64089a1a0fd53bb6549aa53018bdf08dc0fcb3c68f5af8b6fa47830877e670be |
| wan.log | 521921ee55ed2399c767ae751f9c05f1ba066e47e77a9cf201205da6a6fc81fb |

Second capture completed after 300 seconds (start 01:29:46); final log read
at 01:35:34 showed zero packets captured/received/dropped on both interfaces.
Both header-only PCAPs have SHA-256
`c6d5b6f39aa334ca0ef3e27b3cd8cf6a82e453275c16d5fa2f6397a63bb5506f`.
The completed phone-live-lan/wan.pcap and corresponding .log files were
copied into the same ignored local directory (SCP exit 0).
The filter covered the two supplied public IPv6 addresses, not the phone's
link-local DNS traffic. Therefore zero Internet traffic from those public
addresses was observed; this does not prove absence of IPv6 DNS queries.
The direct IPv6-only page failure was reported during this window.
Numeric phone ping result remains pending and will distinguish DNS from
the phone's route/BUFFALO forwarding path. No diagnosis of the exact cause
or corrective router setting is established yet.
No router mutations, rollback, restarts or cable moves performed.
Local `rtk git diff --check` passed, exit 0, with LF-to-CRLF warnings only.

### 2026-10-14 JST - ADB identifies Android RA lifetime mismatch (read-only)

User supplied the Windows platform-tools adb.exe path and authorized
inspection of the Android IPv6 issue. ADB devices listed two transports for
the same ASUS_AI2202; selected the explicit Wi-Fi transport
192.168.11.10:37501. Model ASUS_AI2202, Android 14, SDK 34, security patch
2024-07-05. Final device date was 2026-10-14T22:45:14+09:00.

No phone settings, sysctls, routes, VPN/private-DNS settings, router
configuration, Wi-Fi associations or physical cables were changed.
No reset, root request, reboot, Wi-Fi disable/enable, ADB pairing, or
new diagnostic app installation performed.

Local preflight: rtk git status --short was clean. Registry search for adb
returned no relevant memory entry. No memory-derived diagnosis was used.

Commands used the supplied executable and selected serial, wrapped in
rtk proxy cmd.exe /c. Read-only ADB queries/tests in execution order
(independent groups were batched):

```text
adb.exe devices -l
adb.exe -s 192.168.11.10:37501 shell getprop ro.build.version.release
adb.exe -s 192.168.11.10:37501 shell getprop ro.build.version.sdk
adb.exe -s 192.168.11.10:37501 shell ip -6 addr show dev wlan0
adb.exe -s 192.168.11.10:37501 shell ip -6 route show table all
adb.exe -s 192.168.11.10:37501 shell ip -6 rule show
adb.exe -s 192.168.11.10:37501 shell settings get global private_dns_mode
adb.exe -s 192.168.11.10:37501 shell settings get global private_dns_specifier
adb.exe -s 192.168.11.10:37501 shell settings get secure always_on_vpn_app
adb.exe -s 192.168.11.10:37501 shell settings get secure always_on_vpn_lockdown
adb.exe -s 192.168.11.10:37501 shell dumpsys connectivity
adb.exe -s 192.168.11.10:37501 shell ping -6 -I wlan0 -c 3 -W 2 2606:4700:4700::1111
adb.exe -s 192.168.11.10:37501 shell ping -6 -I wlan0 -c 3 -W 2 fe80::6ae1:dcff:fe37:1d10
adb.exe -s 192.168.11.10:37501 shell ip -6 neigh show dev wlan0
adb.exe -s 192.168.11.10:37501 shell cat /proc/sys/net/ipv6/conf/wlan0/accept_ra /proc/sys/net/ipv6/conf/wlan0/accept_ra_defrtr /proc/sys/net/ipv6/conf/wlan0/forwarding /proc/sys/net/ipv6/conf/wlan0/router_solicitations
adb.exe -s 192.168.11.10:37501 shell logcat -d -t 1500 -s IpClient IpClient.wlan0 ConnectivityService NetworkMonitor
adb.exe -s 192.168.11.10:37501 shell ping6 -I wlan0 -c 3 -W 2 2606:4700:4700::1111
adb.exe -s 192.168.11.10:37501 shell ping6 -I wlan0 -c 3 -W 2 fe80::6ae1:dcff:fe37:1d10
adb.exe -s 192.168.11.10:37501 shell cat /proc/sys/net/ipv6/conf/wlan0/accept_ra_min_rtr_lft /proc/sys/net/ipv6/conf/wlan0/accept_ra_rtr_pref /proc/sys/net/ipv6/conf/wlan0/disable_ipv6
adb.exe -s 192.168.11.10:37501 shell ip -6 route get 2606:4700:4700::1111 oif wlan0
adb.exe -s 192.168.11.10:37501 shell id
adb.exe -s 192.168.11.10:37501 shell cat /proc/sys/net/ipv6/conf/wlan0/accept_ra_min_lft
adb.exe -s 192.168.11.10:37501 shell ls /proc/sys/net/ipv6/conf/wlan0
adb.exe -s 192.168.11.10:37501 shell device_config get connectivity ipclient_min_ra_lifetime
adb.exe -s 192.168.11.10:37501 shell device_config get connectivity min_ra_lifetime
adb.exe -s 192.168.11.10:37501 shell getprop ro.build.version.security_patch
```

The first dumpsys connectivity returned very large output, truncated by
the tool. Corrected collection saved full network_stack/connectivity dumps
locally to ignored backups with a PowerShell helper, without displaying
all raw data:

```text
rtk proxy powershell -NoProfile -File backups/2026-10-14-adb-ipv6/collect.ps1
exit 0; both ADB dumpsys calls exit 0.
```

Focused UTF-8 reads of the first network-stack section revealed RA filter
summary and packet bytes. Long-line matches containing provisioning
information were omitted from the tracked report; ignored raw dumps retain
the full evidence. Two combined-regex rg calls failed at rtk shell pipe
parsing; direct focused reads replaced them.

#### Direct observations

```text
Wi-Fi interface: wlan0, index 26
Wi-Fi IPv4: 192.168.11.10/24
Wi-Fi public IPv6: stable and temporary addresses in the upstream /64
Wi-Fi routing table: 1026
IPv6 default route in table 1026: ABSENT
Wi-Fi LinkProperties ::/0 route: ABSENT
IPv4 default: 192.168.11.1

/proc/sys/net/ipv6/conf/wlan0/accept_ra = 2
/proc/sys/net/ipv6/conf/wlan0/accept_ra_defrtr = 1
/proc/sys/net/ipv6/conf/wlan0/forwarding = 0
/proc/sys/net/ipv6/conf/wlan0/disable_ipv6 = 0
/proc/sys/net/ipv6/conf/wlan0/accept_ra_min_lft = 180

APF RA filters:
RA fe80::6ae1:dcff:fe37:1d10 -> ff02::1 108s
[PUBLIC_UPSTREAM_PREFIX]/64 7200s/3600s
DNS 600s fe80::82ee:73ff:feab:4af1
```

The raw cached RA contains lifetime field 0x006c (108 seconds).
Source link-local/MAC belongs to BUFFALO; the RA contains the expected
public prefix and OpenWrt eth1 link-local DNS. Android accepts the prefix
lifetimes, but the advertised default-router lifetime is below its configured
minimum. APF has seen this RA repeatedly (passed/dropped duplicate RA
counters); a generic dropped-RA counter alone was not treated as a fault.

The full route query included an IPv6 default on a cellular IMS interface,
but not Wi-Fi. Do not confuse the IMS route with a Wi-Fi Internet route.
ConnectivityService's active default network was Wi-Fi (netId 183),
NOT_VPN and IPv4-validated. The phone's UI N/A gateway was corroborated
by kernel routing and Wi-Fi LinkProperties, not merely app display.

Private DNS mode = opportunistic; stored specifier exists but is not an
active strict hostname mode. Always-on VPN app=null, lockdown=0.
The current Wi-Fi NetworkAgentInfo is NOT_VPN. None of these settings
was changed or identified as the cause.

Tests:

```text
ping6 -I wlan0 -c 3 -W 2 2606:4700:4700::1111
connect: Network is unreachable
exit 1

ip -6 route get 2606:4700:4700::1111 oif wlan0
RTNETLINK answers: Network is unreachable
exit 1

ping -I wlan0 -c 3 -W 2 1.1.1.1
3 transmitted, 3 received, 0% packet loss
exit 0
```

Initial ping -6 commands failed because this Android ping binary does not
support that flag; corrected with ping6. A link-local ping6 using -I wlan0
failed with sendmsg Invalid argument; this utility/scoping failure is not
proof that the gateway is unreachable. The neighbor table separately
showed BUFFALO's link-local router as REACHABLE. The earlier sysctl name
accept_ra_min_rtr_lft was absent; the actual accept_ra_min_lft file was
present and read twice as 180.

#### Diagnosis and correction boundary

The [Android kernel implementation](https://android.googlesource.com/kernel/common/+/dd976ecce2ce969d698599c84c8e7dcbb07c9aaf%5E%21)
checks a nonzero advertised router lifetime against accept_ra_min_lft and
skips default-router installation if it is lower. Here 108 < 180.
This provides a concrete explanation for accepted public IPv6 addresses
without a Wi-Fi IPv6 default route and immediate numeric-ping failure.
The findings supersede the earlier generic suspicion of phone network
settings: the identified issue is compatibility between BUFFALO ND proxy
advertisement lifetime and Android's route-lifetime acceptance policy.

The user's same-Wi-Fi iPhone 10/10 result is user-reported. Previous wired-PC
IPv6 tests passed. Those results are consistent with other clients accepting
the shorter lifetime; they do not negate the Android threshold.

Preferred correction: a BUFFALO advertised router lifetime of at least
180 seconds (e.g. 1800 if the firmware exposes/supports that control).
No such timing control has been shown on this BUFFALO UI. Candidate
workaround: BUFFALO IPv6 bridge/passthrough, retaining IPv4 router mode,
to pass OpenWrt's advertisements to clients. Recorded OpenWrt LAN RA
lifetime was 1800 seconds at 01:03:09; that is earlier evidence, not a fresh
router check at 22:45. Revalidate OpenWrt advertisements and WAN IPv6
filtering before the bridge trial. BUFFALO IPv6 filtering is bypassed in
bridge mode, so end-to-end security-boundary checks remain required.

[BUFFALO support](https://www.buffalo.jp/support/faq/detail/16422.html)
documents IPv6 passthrough as an alternative when ND proxy fails.
The bridge workaround is proposed, not applied or verified here. No Android
threshold reduction/static route was attempted. A corrective A/B trial
remains needed to establish the final fix. The original intermittent IPv4
Internet outage is not proven to have the same cause.

#### Saved evidence

Ignored local directory: backups/2026-10-14-adb-ipv6/.

| File | SHA-256 |
|---|---|
| checks.txt | 0ac6030dbdcedaa2651193a85f2fdd4f19632c0f05e7ef27280ed053366983ea |
| network_stack.txt | 4ab096cc2ac3ac8fce06f9e9f4aa81c7ec82d57b0879a4bc7c9e21d157b158b6 |
| connectivity.txt | b3f0279ee356aab9ceb6a8ec480791be5f555e95a7eaab75bab0f325b788a19b |

Full dumps may contain SSIDs, device identifiers and app/network activity;
they remain ignored. Tracked evidence above omits unnecessary private data.
The IPv6 relay plan records the diagnosis and untested corrective options.
Local documentation validation: rtk git diff --check passed, exit 0; LF-to-CRLF warnings only.

### 2026-10-14 JST - Android IPv6 passes after BUFFALO bridge selection

User reported selecting **IPv6ブリッジを使用する** and saving on BUFFALO.
Topology remains ONU -> OpenWrt -> BUFFALO WAN -> Android main Wi-Fi;
BUFFALO retains IPv4 router mode. Verification at 23:01 JST used ADB
transport `192.168.11.10:37501` on ASUS_AI2202. No OpenWrt or phone
configuration was changed in this verification. No rollback was run.

Commands executed through
`rtk proxy cmd.exe /c "C:\Users\akusu\Downloads\platform-tools-latest-windows\platform-tools\adb.exe -s 192.168.11.10:37501 shell <command>"`:

1. `ip -6 route show table all`: exit 0; wlan0 table 1026 now includes
   `default via fe80::82ee:73ff:feab:4af1 ... proto ra ... expires 1622sec`.
2. `ping6 -I wlan0 -c 3 -W 2 2606:4700:4700::1111`: exit 0; 3/3 replies.
3. `command -v curl`: exit 0; `/system/bin/curl`.

Saved repeatable collection command:
`rtk proxy powershell -NoProfile -ExecutionPolicy Bypass -File backups/2026-10-14-adb-ipv6-bridge/collect.ps1`, exit 0.
The script executed these commands in order through the same explicit ADB
transport; all exited 0:

```text
date
  Wed Oct 14 23:01:13 JST 2026
cat /proc/sys/net/ipv6/conf/wlan0/accept_ra_min_lft
  180
ip -6 route show table 1026
  default via fe80::82ee:73ff:feab:4af1 dev wlan0 proto ra metric 1024 expires 1589sec hoplimit 64 pref medium
ping6 -I wlan0 -c 3 -W 2 2606:4700:4700::1111
  3 packets transmitted, 3 received, 0% packet loss
curl --interface wlan0 -6 --connect-timeout 10 --max-time 20 -sS -o /dev/null -w HTTP=%{http_code} https://ipv6.google.com/
  HTTP=200
curl --interface wlan0 -4 --connect-timeout 10 --max-time 20 -sS -o /dev/null -w HTTP=%{http_code} https://www.google.com/
  HTTP=200
dumpsys network_stack
  RA fe80::82ee:73ff:feab:4af1 -> ff02::1 1800s 2400:4050:c340:1600::/64 2592000s/604800s
  RA fe80::6ae1:dcff:fe37:1d10 -> ff02::1 108s 2400:4050:c340:1600::/64 7200s/3600s DNS 600s fe80::82ee:73ff:feab:4af1
dumpsys connectivity
  Saved locally; exit 0.
```

The cached APF list contains both the previous BUFFALO advertisement and
the newly received OpenWrt advertisement; the stale entry alone does not
prove that BUFFALO continues transmitting it. Android's threshold remains
180, but the 1800-second advertisement now permits default-route installation.
IPv6 ping and IPv6-only HTTPS are observed passes over wlan0, independently
of the cellular interface. IPv4 HTTPS also passes. Browser test-ipv6.com
score, reconnect/reboot persistence and unsolicited external inbound
filtering remain untested. This establishes the Android IPv6 workaround,
not the cause of the original intermittent Internet outage.

Ignored evidence directory: `backups/2026-10-14-adb-ipv6-bridge/`.
Full dumps stay local because they include unrelated device/app details.

| File | SHA-256 |
|---|---|
| checks.txt | b6f78968e89dc35d3e89d4c64e748d0e08728ea8c9a26b4953d8a67c00c8c31b |
| network_stack.txt | 1730bf54dea07b146ab9bf41fc42e231260020343869c8614c94b87c1433c7b5 |
| connectivity.txt | a0549f81022de39e676c2f29cbaa68e401ac8f8a3ad2d9b11c69e1710386fc7e |
### 2026-10-16 JST - Current interface MTU inspection (read-only)

Topology: live routes show IPv4 default through `map-mape_auto`, IPv6 default
through `eth0`, LAN `192.168.1.0/24` on `br-lan`, and BUFFALO LAN
`192.168.11.0/24` through `192.168.1.2`. Cable positions were not physically
inspected. No configuration changes, backup, or rollback were needed.

Access attempts: the first sandboxed SSH connection failed with exit 1,
`ssh: connect to host 192.168.1.1 port 22: Permission denied`.
An elevated connection succeeded, but its stdin closed because it lacked a
local TTY; no diagnostic commands ran there. Reconnected with a local TTY:

```text
rtk proxy cmd.exe /c 'ssh -tt -i .local-ssh/id_ed25519_v2 -o BatchMode=yes -o ConnectTimeout=8 root@192.168.1.1'
```

Commands sent through that persistent session, in execution order:

```sh
date -Iseconds
ip -o link show
echo link_rc=$?
ip route show default
ip -6 route show default
for n in wan wan6 mape_auto; do echo INTERFACE=$n; ifstatus "$n" | jsonfilter -e '@.up' -e '@.device' -e '@.l3_device'; done
uci show network | grep -E 'mtu|proto|device'
echo config_rc=$?
exit
```

Observed time: `2026-10-16T01:44:19+09:00`. Relevant verbatim excerpts:

```text
2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc mq state UP qlen 1000
3: eth1: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc fq_codel master br-lan state UP qlen 1000
5: br-lan: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP qlen 1000
10: map-mape_auto@eth0: <POINTOPOINT,NOARP,UP,LOWER_UP> mtu 1280 qdisc noqueue state UNKNOWN qlen 1000
link_rc=0
default dev map-mape_auto scope link
INTERFACE=wan
false
eth0
INTERFACE=wan6
true
eth0
eth0
INTERFACE=mape_auto
true
map-mape_auto
network.wan.device='eth0'
network.wan.proto='dhcp'
network.wan6.device='eth0'
network.wan6.proto='dhcpv6'
network.mape_auto.proto='map'
config_rc=0
```

IPv6 default used `eth0` (global IPv6 addresses omitted). No explicit `mtu`
option appeared in `uci show network`. Individual route/ifstatus exit codes
were not captured; their output was observed. MTU inspection passed: LAN and
native WAN link MTU 1500 bytes, active IPv4 MAP-E interface MTU 1280 bytes.
No path-MTU probe, downstream BUFFALO inspection, connectivity test, or reboot
test was performed. This establishes interface MTUs only.

### 2026-10-16 JST - MAP-E MTU 1460 test and persistence (executed)

Topology: DS57U IPv4 default `map-mape_auto`, native IPv6 default `eth0`,
LAN `192.168.1.1/24` on `br-lan`/`eth1`. Windows wired client
`192.168.11.97` uses BUFFALO `192.168.11.1`; Wi-Fi and NordLynx were
disconnected. No cables moved. `wan=false`, `wan6=true`, `mape_auto=true`.
UCI network had no pending changes; baseline tunnel MTU 1280, physical WAN
1500, `encaplimit=ignore`, WAN zone `mtu_fix=1`. Installed map backend line
82 confirmed `json_add_int mtu "${mtu:-1280}"`.

Pre-change backup commands (persistent SSH session):

```sh
mkdir -p /root/mtu-test-20261016
cp -p /etc/config/network /root/mtu-test-20261016/network.before
cp -p /etc/config/firewall /root/mtu-test-20261016/firewall.before
cp -p /etc/config/dhcp /root/mtu-test-20261016/dhcp.before
sha256sum /root/mtu-test-20261016/*.before
```

SHA-256 output:

```text
4b79c410362bbae08813112a9b4547b98e6c6400525e73a966545843ceeb6b30  dhcp.before
c453154a646539461bf0048a7dc4c037cd10067c1cf79244759957d5b327f60e  firewall.before
1e0c63ba79568b9a7db91e9d3ba4d8df1598ff880c413e21ec66117f4b39e847  network.before
```

All three backup files were read by sha256sum; individual cp exit statuses
were not separately captured. Baseline IPv4 and IPv6 ping each passed 3/3,
DNS returned A/AAAA, and IPv4 HTTPS returned HTTP 200, all reported rc=0.
Windows baseline DF ping with 1252-byte payload passed 3/3 (exit 0).
The first long SSH input was truncated at curl (curl reported no URL);
rerunning the complete curl command separately returned HTTP 200/rc=0.

Runtime test commands, after baseline checks:

```sh
( trap '' HUP; sleep 300; ip link set dev map-mape_auto mtu 1280; logger -t mtu-test 'automatic rollback to 1280' ) >/tmp/mtu-rollback.log 2>&1 &
RB=$!; echo rollback_pid=$RB; kill -0 "$RB"; echo rollback_armed_rc=$?
ip link set dev map-mape_auto mtu 1460; echo set_mtu_rc=$?
cat /sys/class/net/map-mape_auto/mtu
tcpdump -ni eth0 -vv -c 12 'ip6 proto 4' >/tmp/mtu1460-capture.txt 2>&1 &
```

Observed rollback PID 7971, armed rc=0; set_mtu_rc=0, readback 1460.
PC commands (prefix each with `rtk proxy cmd.exe /c`, with the inner command
quoted as a single argument):

```text
ping -4 -S 192.168.11.97 -f -l 1432 -n 4 -w 2000 1.1.1.1
ping -4 -S 192.168.11.97 -f -l 1432 -n 4 -w 2000 8.8.8.8
ping -4 -S 192.168.11.97 -f -l 1433 -n 2 -w 2000 1.1.1.1
curl.exe --noproxy * --interface 192.168.11.97 -4 --connect-timeout 5 --max-time 25 -sS -o NUL -w HTTP=%{http_code} https://openwrt.org/
```

Both 1432-byte DF tests passed 4/4 with 4-5 ms RTT (exit 0).
1432 + 20-byte IPv4 header + 8-byte ICMP header = 1460 bytes.
At 1433 bytes, output included `Reply from 192.168.1.1: Packet needs to be
fragmented but DF set.` Windows returned exit 0 despite that response;
the content establishes rejection, not echo success.
Sandboxed curl to openwrt.org failed rc=7/HTTP=000 (process exit 1), as did
a Cloudflare retry. Repeating the source-bound openwrt.org request with
sandbox network restrictions lifted passed HTTP=200, process exit 0.
This distinguishes the local execution restriction from a tunnel failure.

Router follow-up commands:

```sh
cat /tmp/mtu1460-capture.txt
ping -6 -c 3 -W 3 2606:4700:4700::1111; echo test_v6_rc=$?
nslookup openwrt.org 127.0.0.1; echo test_dns_rc=$?
curl -4 -sS -o /dev/null --connect-timeout 5 --max-time 20 -w 'HTTP=%{http_code}\n' https://openwrt.org/; echo test_https_rc=$?
tcpdump -ni eth0 -vv -c 4 'ip6 proto 4 and ip6[40] = 0x45 and ip6[49] = 1' >/tmp/mtu1460-icmp.txt 2>&1 &
```

IPv6 passed 3/3, DNS returned A/AAAA, HTTPS HTTP=200; all rc=0.
First capture reached its limit with background TCP before the test ping;
it showed TCP MSS 1420 but did not establish the ping packet size.
Repeated PC DF ping with 1432-byte payload and `-n 2` passed 2/2, exit 0.
Then `cat /tmp/mtu1460-icmp.txt` showed four ICMP tunnel packets, zero kernel
drops. Relevant excerpt, endpoint addresses redacted:

```text
IP6 (flowlabel 0x79d8c, hlim 64, next-header IPIP (4), payload length 1460) [CE] > [BR]: IP (tos 0x0, ttl 126, id 40409, offset 0, flags [DF], proto ICMP (1), length 1460)
    [PUBLIC_IPV4] > 1.1.1.1: ICMP echo request, id 1387, seq 14, length 1440
IP6 (hlim 60, next-header IPIP (4), payload length 1460) [BR] > [CE]: IP (tos 0x38, ttl 54, id 19887, offset 0, flags [none], proto ICMP (1), length 1460)
    1.1.1.1 > [PUBLIC_IPV4]: ICMP echo reply, id 1387, seq 14, length 1440
4 packets captured
4 packets received by filter
0 packets dropped by kernel
```

The outer IPv6 packets have 1460-byte payload plus 40-byte header, direct
IPIP next-header, and no fragmentation header. This validates this packet
size on the observed path in both directions.

After reviewing the sole UCI delta and writing the sanitized baseline in
`router-config/mtu-1460.md`, persisted the setting:

```sh
uci set network.mape_auto.mtu='1460'; echo stage_rc=$?
uci changes network
uci -q get network.lan.ipaddr
uci -q get network.lan.device
uci -q get network.@device[0].ports
uci commit network; echo commit_rc=$?
uci get network.mape_auto.mtu
cat /sys/class/net/map-mape_auto/mtu
kill "$RB"; echo cancel_rollback_rc=$?
kill -0 "$RB" 2>/dev/null; echo rollback_alive_rc=$?
sha256sum /etc/config/firewall /etc/config/dhcp
uci changes network
ip -4 route show default
kill -0 "$RB" 2>/dev/null; echo rollback_alive_final_rc=$?
cat /sys/class/net/map-mape_auto/mtu
uci get network.mape_auto.mtu
ping -4 -c 3 -W 3 1.1.1.1; echo final_v4_rc=$?
exit
```

Stage and commit rc=0. Sole delta `network.mape_auto.mtu='1460'`;
LAN readback remained `192.168.1.1/24`, `br-lan`, `eth1`. Committed and
runtime MTU both 1460. Firewall/DHCP hashes matched backups, no pending
network changes, IPv4 default remained `map-mape_auto`. Rollback kill rc=0;
immediate alive check raced with termination (rc=0), shell then reported
job terminated, final alive check rc=1 confirmed it stopped. Automatic
rollback did not execute. Router final ping 3/3, rc=0; PC final 1432-byte DF
ping 3/3 at 4 ms, exit 0. SSH exited 0.

Verdict: 1460 passed the runtime/client-path acceptance checks and is saved
in UCI. No throughput improvement is claimed. Reboot, interface recreation,
and all possible Internet destinations remain unverified. The rollback
commands and reprovisioning limitation are in the sanitized change record.

Complete collected router command/output chunks and initial client tests
are in ignored `backups/mtu-test-20261016/session.json`, SHA-256
`48e3ef404904691cb9c95c7cefb36eccae86ae62b2bc179f7d2965cc1464944f`.
Later elevated client HTTPS and final client ping results are recorded above.
No credentials are included. Public/client addresses and unrelated captured
endpoint metadata remain confined to ignored local evidence.
### 2026-10-16 JST - Post-change MTU recheck (read-only)

Observed router time `2026-10-16T01:56:29+09:00`. Same topology as the
preceding MTU test; no cable move or configuration change performed.
Used one persistent SSH session with the documented key and root endpoint.
Commands and relevant output:

```sh
date -Iseconds
for n in eth0 eth1 br-lan map-mape_auto; do printf '%s MTU=' "$n"; cat /sys/class/net/$n/mtu; done
uci get network.mape_auto.mtu; echo saved_mtu_rc=$?
uci changes network
for n in wan wan6 mape_auto; do echo INTERFACE=$n; ifstatus "$n" | jsonfilter -e '@.up' -e '@.l3_device'; done
exit
```

```text
eth0 MTU=1500
eth1 MTU=1500
br-lan MTU=1500
map-mape_auto MTU=1460
1460
saved_mtu_rc=0
INTERFACE=wan
false
INTERFACE=wan6
true
eth0
INTERFACE=mape_auto
true
map-mape_auto
```

`uci changes network` emitted no pending changes. SSH exited 0; individual
loop-command exit statuses were not separately captured. Local command
`rtk proxy cmd.exe /c 'netsh interface ipv4 show subinterfaces'` exited 0
and showed connected Ethernet MTU 1500 (MediaSenseState 1). Disconnected
NordLynx MTU 1420 is not the active path.

PASS: active and committed MAP-E MTU both remain 1460; router LAN and
physical WAN plus connected PC Ethernet remain 1500. BUFFALO interface
MTUs were not directly inspected. No new packet-size probe or reboot was
performed; prior runtime proof remains in the preceding test record.
Rollback not needed for this read-only check.
