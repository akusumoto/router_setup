# phase2-router-mode-replacement - Execution History

Manual: [rebuild procedure](../../phase2-router-mode-replacement.md).

These are dated records, including failures, corrections, retests, and unrun plans retained as historical context. Addresses, hashes, checklists, and statements of current state apply to the recorded session only. Use the manual for a new rebuild; append new execution evidence here. Original section numbers are retained for references within the records.

## 8. Execution record

| Date (JST) | Topology | Action / command | Result and exit status |
|---|---|---|---|
| 2026-09-28 | No physical change; `ONU -> BUFFALO -> DS57U` remains recorded topology | Wrote this planned procedure from the recorded Phase 1/2 topology and the user's router-mode requirement. | Planned only; no live verification performed. |
| 2026-09-28 | No physical change; DS57U remains behind BUFFALO. | Read-only DS57U inspection: `uci show dhcp`, `uci show network.lan`, and `cat /tmp/dhcp.leases`. | Observed LAN `192.168.1.1/24`, DHCP pool `192.168.1.100`–`249`, and no lease for `68:E1:DC:37:1D:10`; `192.168.1.2` is available for the planned reservation. |
| 2026-09-28 | No physical change; DS57U remains behind BUFFALO. | Created a fresh DS57U backup, then committed the `dhcp.buffalo_wan` reservation and reloaded `dnsmasq`. | Backup SHA-256 matched on router and PC. Reservation is committed; `dnsmasq` reload exited `0`. No BUFFALO lease is expected until the physical switchover. See Section 8.1. |

When the switchover is performed, append the cable state, commands in order,
verbatim relevant outputs, and pass/fail results here.  Redact passwords,
private keys, and lease identifiers.

### 8.1 2026-09-28 JST — BUFFALO WAN DHCP reservation (executed)

Topology was unchanged: `ONU -> BUFFALO -> DS57U eth0`; this PC remained on
DS57U LAN at `192.168.1.157`.  The router reported
`2026-09-28T09:44:42+00:00` (18:44:42 JST) for the initial read-only check.

Before changing DHCP, the following read-only commands returned the current
LAN and lease state:

```sh
uci show dhcp
uci show network.lan
cat /tmp/dhcp.leases
```

Relevant output was `dhcp.lan.start='100'`, `dhcp.lan.limit='150'`,
`network.lan.ipaddr='192.168.1.1/24'`, and the only IPv4 lease was
`192.168.1.157` for a different MAC.  There was no existing
`dhcp.buffalo_wan` section and no lease for `68:E1:DC:37:1D:10`.  Thus
`192.168.1.2` is outside the dynamic `192.168.1.100`–`249` pool and was
available.

A fresh backup was created before the change.  The initial combined shell
attempt created the backup but caused the local shell to interpret
`sha256sum`; that hash attempt failed.  The correction ran the hash as a
separate SSH command and then copied the backup with `scp -O` to the ignored
local `backups/` directory.  Router and PC SHA-256 values matched:

```text
Router backup: sysupgrade -b /tmp/phase2-buffalo-wan-reservation-pre-20260928.tar.gz
Router hash: sha256sum /tmp/phase2-buffalo-wan-reservation-pre-20260928.tar.gz
PC copy: scp -O root@192.168.1.1:/tmp/phase2-buffalo-wan-reservation-pre-20260928.tar.gz backups/phase2-buffalo-wan-reservation-pre-20260928.tar.gz
PC hash: certutil -hashfile backups/phase2-buffalo-wan-reservation-pre-20260928.tar.gz SHA256

225883de65da189405e8501f6d07c153f01502625b6c750e4f0dec3a83d6d01d  phase2-buffalo-wan-reservation-pre-20260928.tar.gz
```

The committed DS57U commands, in order, were:

```sh
uci set dhcp.buffalo_wan='host'
uci set dhcp.buffalo_wan.name='buffalo-wan'
uci set dhcp.buffalo_wan.mac='68:E1:DC:37:1D:10'
uci set dhcp.buffalo_wan.ip='192.168.1.2'
uci commit dhcp
/etc/init.d/dnsmasq reload
uci show dhcp.buffalo_wan
uci changes dhcp
cat /tmp/dhcp.leases
```

Observed result:

```text
DNSMASQ_RELOAD_EXIT=0
dhcp.buffalo_wan=host
dhcp.buffalo_wan.name='buffalo-wan'
dhcp.buffalo_wan.mac='68:E1:DC:37:1D:10'
dhcp.buffalo_wan.ip='192.168.1.2'
UCI_CHANGES_EXIT=0
```

`uci changes dhcp` had no output, confirming the DHCP change was committed.
The lease file still contained only the current PC lease, which is expected
while BUFFALO WAN is not connected to DS57U LAN.  The reservation is ready;
the post-switch acceptance check in Section 6 must confirm the matching lease
and BUFFALO WAN address `192.168.1.2`.

### 8.2 2026-09-29 JST - Section 5 DS57U readiness recheck (executed)

Topology was unchanged: `ONU -> BUFFALO -> DS57U eth0`; the read-only SSH
session to `root@192.168.1.1` opened successfully.  The router time was
`2026-09-29T01:19:55+09:00`.  No UCI, cable, service, or package change was
made.  The commands were run in this order:

```sh
date -Iseconds
uci show network.wan; echo WAN_EXIT=$?
uci show network.wan6; echo WAN6_EXIT=$?
uci show network.lan; echo LAN_EXIT=$?
uci show firewall.@zone[1]; echo FIREWALL_EXIT=$?
uci show dhcp.buffalo_wan; echo RESERVATION_EXIT=$?
uci -q get network.map; echo STATIC_MAP_EXIT=$?
apk info -e map; echo MAP_PACKAGE_EXIT=$?
ubus call network.interface.lan status; echo LAN_STATUS_EXIT=$?
ubus call network.interface.wan6 status; echo WAN6_STATUS_EXIT=$?
cat /tmp/dhcp.leases; echo LEASES_EXIT=$?
uptime; echo UPTIME_EXIT=$?
ubus call network.interface.wan status; echo WAN_STATUS_EXIT=$?
for f in /sys/class/net/eth0/carrier /sys/class/net/eth0/speed /sys/class/net/eth0/duplex /sys/class/net/eth1/carrier /sys/class/net/eth1/speed /sys/class/net/eth1/duplex; do printf '%s=' "$f"; cat "$f"; done; echo LINK_EXIT=$?
ip -4 route; echo IPV4_ROUTE_EXIT=$?
```

All named UCI, `ubus`, link, lease, and route commands exited `0`, except
`STATIC_MAP_EXIT=1`, which is the required result for an absent
`network.map`.  Relevant verbatim output was:

```text
network.wan.device='eth0'
network.wan.proto='dhcp'
network.wan6.device='eth0'
network.wan6.proto='dhcpv6'
network.wan6.iface_map='1'
network.lan.device='br-lan'
network.lan.ipaddr='192.168.1.1/24'
firewall.cfg03dc81.network='wan' 'wan6'
firewall.cfg03dc81.masq='1'
dhcp.buffalo_wan.mac='68:E1:DC:37:1D:10'
dhcp.buffalo_wan.ip='192.168.1.2'
STATIC_MAP_EXIT=1
map
MAP_PACKAGE_EXIT=0
1790655425 04:ab:18:d7:15:b8 192.168.1.157 akirawin11 01:04:ab:18:d7:15:b8
eth0/carrier=1
eth0/speed=1000
eth0/duplex=full
eth1/carrier=1
eth1/speed=1000
eth1/duplex=full
```

`wan` was up on `eth0` with DHCP address `192.168.11.108/24`, default route
via `192.168.11.1`, and DNS server `192.168.11.1`; this confirms the expected
pre-switch BUFFALO-facing state, not a direct-ONU result.  `wan6` was up with
an IPv6 default route.  The only DS57U DHCP lease was the test PC at
`192.168.1.157`; there was no lease for the BUFFALO WAN MAC, so the reserved
`192.168.1.2` remains unclaimed.  DS57U-side Section 5 preflight is PASS.
Direct-ONU connectivity, BUFFALO router/DHCP-WAN UI state, the behind-BUFFALO
client baseline, cable labels, and the post-move checks remain unperformed.

### 8.3 2026-09-29 JST - BUFFALO client baseline (executed)

Before any physical change, `ipconfig /all` on the test PC identified the
Realtek Ethernet adapter (MAC `10-FF-E0-4D-2B-90`) as a BUFFALO-side DHCP
client: IPv4 `192.168.11.21/24`, IPv4 gateway `192.168.11.1`, DHCP server
`192.168.11.1`, and IPv4 DNS server `192.168.11.1`.  This PC also remained
connected to the DS57U LAN through its separate ASIX adapter
(`192.168.1.157`), so the public HTTPS check was explicitly source-bound to
the BUFFALO-side address.

```powershell
ping.exe -4 -n 4 192.168.11.1
curl.exe --ipv4 --interface 192.168.11.21 --connect-timeout 10 --max-time 20 --silent --show-error https://cloudflare.com/cdn-cgi/trace
```

The ping returned four replies with `time<1ms`, zero packet loss, and exit
status `0`.  The source-bound HTTPS request exited `0` and returned a
Cloudflare trace with `h=cloudflare.com`, `ip=153.243.13.0`, `colo=NRT`,
`loc=JP`, `tls=TLSv1.3`, and `warp=off`.  This is a PASS baseline for the
existing BUFFALO `192.168.11.0/24` client network.  Repeat the same
source-bound request after the move if the Realtek adapter retains
`192.168.11.21`; otherwise substitute its newly leased `192.168.11.x`
address.

### 8.4 2026-09-29 JST - BUFFALO UI preflight (user-confirmed)

Before the cable move, the user confirmed in the BUFFALO administration UI
that it remains in router mode, its LAN is `192.168.11.1/24`, and its WAN
addressing mode is automatic/DHCP.  No BUFFALO setting was changed.  This is
a PASS for the BUFFALO UI portion of Section 4.  Cable labels and confirmation
of the test PC's post-move BUFFALO-LAN connection remain physical preflight
steps.

### 8.5 2026-09-29 JST - Cable and test-PC physical preflight (user-confirmed)

Before the cable move, the user confirmed that the ONU, blue, and white cables
were labelled and that the test PC can be connected to a BUFFALO LAN port after
the move.  This is a PASS for the remaining physical preflight.  All Section 4
gates are complete; Section 5 has not yet been performed.

### 8.6 2026-09-29 JST - Section 5 attempt, failure, and rollback (executed)

The user performed the Section 5 cable move and then restored the previous
topology after the home network did not obtain Internet access.  No router
configuration was changed during the attempt.  The user-provided DS57U LuCI
screenshot from the switched state showed `lan` up at `192.168.1.1/24`, `wan`
carrier present with DHCP client protocol but no displayed IPv4 address, and
`wan6` carrier present with a global IPv6 address
`2400:4050:c340:1600:82ee:73ff:feab:4af0/64`.  No `wan6_4` interface was shown.
The simultaneous BUFFALO status screenshot showed router mode, LAN
`192.168.11.1/24`, a 1000BASE-T full-duplex wired link, and WAN connection
detection still in progress.

After rollback, a read-only persistent SSH check at
`2026-09-29T01:55:03+09:00` returned:

```text
wan: up, DHCP address 192.168.11.108/24, default via 192.168.11.1
wan6: up, DHCPv6 address 2400:4050:c340:1600:82ee:73ff:feab:4af0/64
wan6_4: Command failed: Not found (exit 4)
```

`/tmp/dhcp.leases` contains the active reservation
`68:e1:dc:37:1d:10 -> 192.168.1.2 buffalo-wan`.  More importantly, the
preserved `dnsmasq` log recorded the same BUFFALO WAN MAC receiving that lease
during the failed switched state at `01:36:18`, `01:37:37`, `01:37:47`,
`01:39:06`, and `01:39:17`, followed by releases while cables were moved back.
Therefore the DS57U-LAN-to-BUFFALO-WAN DHCP link worked; it was not the cause
of the Internet failure.

Verdict: **rollback PASS; replacement acceptance FAIL.**  The observed failure
is IPv4-over-IPv6/MAP-E: native IPv6 came up on DS57U, but a native IPv4 DHCP
lease is not expected on this direct IPoE service and the required automatic
`wan6_4` MAP-E interface was absent.  The retained evidence cannot distinguish
whether the direct DHCPv6 exchange omitted usable Softwire46/MAP-E data or
whether it was not processed; a future direct retry must capture `wan6_4`,
DHCPv6/odhcp6c evidence, routes, and IPv4/IPv6 probes before any configuration
change.  Do not infer or enter a static MAP-E rule from the BUFFALO screenshot.

### 8.7 Next direct-ONU diagnostic retry (planned; no setting change)

Before another full replacement attempt, perform a short isolated DS57U
direct-ONU test to determine why automatic MAP-E did not appear.  Keep the
existing `map` package, `network.wan6.iface_map='1'`, WAN firewall zone, and
BUFFALO automatic/DHCP WAN setting unchanged.  Do not add `network.map`, edit
MAP-E values, reboot either router, or add `wan6_4` manually: automatic
creation of that interface is the evidence being tested.

Use the Phase 2 topology for this diagnostic only: the test PC connects solely
to DS57U `eth1`; DS57U `eth0` connects to the ONU-side hub; and BUFFALO WAN is
disconnected from the ONU and DS57U.  This retains direct PC-to-DS57U
management and removes BUFFALO from the diagnostic path.  Wait two minutes,
then retain the direct topology while collecting this read-only evidence in
one persistent SSH session:

```sh
date -Iseconds
cat /sys/class/net/eth0/carrier
ubus call network.interface.wan status
ubus call network.interface.wan6 status
ubus call network.interface.wan6_4 status; echo WAN6_4_EXIT=$?
ip -6 addr show dev eth0
ip -6 route
ip -4 addr
ip -4 route
nft list ruleset
logread -e odhcp6c
logread -e map
ping -6 -c 4 2606:4700:4700::1111
ping -4 -c 4 1.1.1.1
```

Do not rely on Internet or a live chat session while switched.  Before moving
the cable, stage a bounded packet capture and a timestamped status loop on
DS57U, writing to ignored `/tmp` files.  They continue locally across the
outage and can be retrieved after rollback.  Start them in the persistent SSH
session, note the printed PIDs, then perform the cable move:

```sh
(
  trap '' HUP
  exec tcpdump -c 300 -ni eth0 -s 0 -w /tmp/direct-onu-dhcpv6.pcap '(icmp6 or udp port 546 or udp port 547)'
) </dev/null >/tmp/direct-onu-tcpdump.stderr 2>&1 & echo TCPDUMP_PID=$!
(
  trap '' HUP
  for n in $(seq 1 24); do
    date -Iseconds
    ubus call network.interface.wan6 status
    ubus call network.interface.wan6_4 status; echo WAN6_4_EXIT=$?
    ip -6 route
    ip -4 route
    sleep 10
  done
) >/tmp/direct-onu-status.log 2>&1 & echo STATUS_PID=$!
```

After returning to the established topology, stop a still-running capture with
`kill <TCPDUMP_PID>`, then copy `/tmp/direct-onu-status.log`,
`/tmp/direct-onu-tcpdump.stderr`, and the PCAP to the ignored local evidence
area for review.  Record only redacted, relevant excerpts in this document.

If `wan6_4` is still absent, preserve a short DHCPv6/RA packet capture during
the next cable move (rather than guessing settings) so the received
Softwire46 options can be checked.  Then restore the established topology and
verify recovery before planning a configuration change.  If `wan6_4` appears,
verify its routes and firewall-generated NAT before repeating the full
DS57U-to-BUFFALO replacement topology.

### 8.8 2026-10-01 JST - Direct-ONU diagnostic preparation (executed; no cable move)

Topology remained `ONU -> BUFFALO WAN` and `BUFFALO LAN -> DS57U eth0`; the
test PC remained on DS57U LAN.  No UCI, package, service, or physical-cable
change was made.  A read-only SSH preflight at `2026-10-01T02:29:01+09:00`
confirmed the required starting state:

```text
network.wan.device='eth0'
network.wan.proto='dhcp'
network.wan6.device='eth0'
network.wan6.proto='dhcpv6'
network.wan6.iface_map='1'
network.lan.ipaddr='192.168.1.1/24'
firewall.cfg03dc81.network='wan' 'wan6'
firewall.cfg03dc81.masq='1'
dhcp.buffalo_wan.mac='68:E1:DC:37:1D:10'
dhcp.buffalo_wan.ip='192.168.1.2'
STATIC_MAP_EXIT=1
map
MAP_PACKAGE_EXIT=0
wan: up, DHCP address 192.168.11.108/24, default via 192.168.11.1
wan6: up, IPv6 default route via eth0
wan6_4: Command failed: Not found (exit 4)
eth0: carrier=1, speed=1000, duplex=full
eth1: carrier=1, speed=1000, duplex=full
```

The only active DS57U DHCP lease was the test PC; the BUFFALO WAN reservation
was still unclaimed.  This is the expected pre-diagnostic state behind
BUFFALO, not direct-ONU proof.  The following commands were executed, in
order (the first SSH command is read-only):

```powershell
ssh -i .local-ssh/id_ed25519_v2 -o BatchMode=yes -o ConnectTimeout=10 root@192.168.1.1 'date -Iseconds; uci show network.wan; uci show network.wan6; uci show network.lan; uci show firewall.@zone[1]; uci show dhcp.buffalo_wan; uci -q get network.map; echo STATIC_MAP_EXIT=$?; apk info -e map; echo MAP_PACKAGE_EXIT=$?; ubus call network.interface.wan status; echo WAN_STATUS_EXIT=$?; ubus call network.interface.wan6 status; echo WAN6_STATUS_EXIT=$?; ubus call network.interface.wan6_4 status; echo WAN6_4_EXIT=$?; cat /tmp/dhcp.leases; echo LEASES_EXIT=$?; for f in /sys/class/net/eth0/carrier /sys/class/net/eth0/speed /sys/class/net/eth0/duplex /sys/class/net/eth1/carrier /sys/class/net/eth1/speed /sys/class/net/eth1/duplex; do printf "%s=" "$f"; cat "$f"; done; echo LINK_EXIT=$?; ip -4 route; ip -6 route; uptime'
ssh -i .local-ssh/id_ed25519_v2 -o BatchMode=yes -o ConnectTimeout=10 root@192.168.1.1 'sysupgrade -b /tmp/phase2-direct-onu-diagnostic-pre-20261001.tar.gz && sha256sum /tmp/phase2-direct-onu-diagnostic-pre-20261001.tar.gz'
scp -O -i .local-ssh/id_ed25519_v2 -o BatchMode=yes -o ConnectTimeout=10 root@192.168.1.1:/tmp/phase2-direct-onu-diagnostic-pre-20261001.tar.gz backups/phase2-direct-onu-diagnostic-pre-20261001.tar.gz
certutil -hashfile backups/phase2-direct-onu-diagnostic-pre-20261001.tar.gz SHA256
```

The backup command and copy both exited `0`.  The router and ignored local
copy matched at SHA-256
`b7e2b194d5e1a39b88f5aab4f82112724403eaad03bf4295790db6d8d23229a3`.
The local backup is `backups/phase2-direct-onu-diagnostic-pre-20261001.tar.gz`.

Preparation is PASS.  The next action must be Section 8.7's *isolated*
direct-ONU diagnostic, not the full DS57U-to-BUFFALO replacement: immediately
before moving the ONU cable, open one persistent SSH session and start the
bounded capture and status loop in Section 8.7.  Do not start those jobs early,
because their capture/count limits would expire before the cable event.

### 8.9 2026-10-01 JST - Isolated direct-ONU diagnostic, evidence review, and rollback (executed)

The diagnostic used the Section 8.7 isolated topology: the ONU-side hub was
connected to DS57U `eth0`, the test PC remained connected only to DS57U
`eth1`, and BUFFALO WAN was disconnected.  No UCI, package, service, or router
setting was changed.  The internet connection did not work, so the user
restored the established topology.  The rollback check at
`2026-10-01T02:47:27+09:00` restored the expected WAN state: `wan` was again up as
`192.168.11.108/24` with default gateway `192.168.11.1`; `wan6` was up; and
`wan6_4` was still absent (exit `4`).

The first capture/status-loop launch used a base64 decoder that is not present
on this OpenWrt image (`base64: applet not found`), and two inline SSH loop
forms failed before a loop was started because of Windows-to-SSH quoting.
Neither failure changed router state.  The correction copied an ignored
literal shell helper to `/tmp` and started it with `setsid`.  The bounded
capture completed with `300 packets captured`, `300 packets received by
filter`, and `0 packets dropped by kernel`; the status loop covered
`02:33:29` through `02:37:20` JST.

The status log recorded the direct-ONU transition between its
`02:34:09` and `02:34:19` samples.  In the direct interval, `wan6` received a
native IPv6 address/default route via the ONU-side router, but every
`wan6_4` query returned `Command failed: Not found` (exit `4`) and there was
no IPv4 default route.  The packet capture supplies the decisive cause:

```text
02:34:16 DHCPv6 SOLICIT: option-request opt_94 opt_95 opt_96 ... (IA_NA, IA_PD)
02:34:16 DHCPv6 ADVERTISE: status-code NoPrefixAvail
02:34:17 DHCPv6 INFORMATION-REQUEST: option-request opt_94 opt_95 opt_96 ...
02:34:17 DHCPv6 REPLY: DNS-server, DNS-search-list, SNTP-servers only
```

Options `94`, `95`, and `96` are the Softwire46 container options for MAP-E,
MAP-T, and Lightweight 4over6 respectively (RFC 7598).  The captured reply
did not contain any container, so it could not carry MAP-E's embedded rule,
border-relay, or default-mapping-rule values.  Thus the prior uncertainty is
resolved: in this observed direct DHCPv6 exchange, usable MAP-E configuration
was **not supplied by the upstream server**; it was not merely unprocessed by
DS57U.  Native IPv6 alone therefore came up, while required IPv4-over-IPv6
did not.  Do not retry the full replacement or invent static MAP-E values from
this result.

Post-rollback reachability at `02:50 JST` was mixed.  The following commands
were run from DS57U, in order:

```sh
ping -4 -c 4 1.1.1.1; echo PING4_EXIT=$?
ping -6 -c 4 2606:4700:4700::1111; echo PING6_EXIT=$?
nslookup cloudflare.com 192.168.11.1; echo DNS_EXIT=$?
```

IPv4 returned four replies (0% loss, `3.920`–`4.303 ms`, exit `0`) and the
BUFFALO DNS server resolved both A and AAAA records (exit `0`).  The IPv6 ping
returned 0/4 replies (exit `1`) despite the displayed `wan6` address and
default route.  Therefore **IPv4 and DNS rollback recovery are PASS; IPv6
end-to-end recovery is FAIL/needs separate diagnosis**.  This outcome is
recorded as observed; this diagnostic does not establish whether it predates
the cable test or was caused by it.

The following ignored local evidence files were copied after rollback and
hashed with `Get-FileHash -Algorithm SHA256`:

```text
backups/direct-onu-status-20261001.log
  c2c29ae6f689973b3383a151281111420487dbe7777846ed4a53db121cb2c060
backups/direct-onu-tcpdump-20261001.stderr
  0c8b71f1caa5f483bfb6404008f72c7607d1aa686c8c163ef45c9e7ff3691a7c
backups/direct-onu-dhcpv6-20261001.pcap
  10aaba3090a67dc62a896ba523c4295522f8b89aca381c1d366b1fd88d58d793
```

Verdict: **isolated diagnostic FAIL for MAP-E availability; IPv4/DNS rollback
PASS; IPv6 rollback reachability needs diagnosis.**  The MAP-E evidence is
sufficient to stop cable/replacement retries under the current automatic
configuration.  Any future path requires ISP/service-side MAP-E provisioning
information or a separately authorized, source-verified static configuration
design; neither is inferred or applied here.
