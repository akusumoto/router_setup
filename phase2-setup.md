# Phase 2 Implementation Procedure — Verifying IPv6 IPoE / MAP-E via Direct OCN Connection

Last updated: 2026-09-23
Status: **The automatic-MAP preparation in the execution log has been completed. Direct-ONU wiring and Phase 2A–2D device testing have not been executed.**

## 1. Objective and Completion Conditions

Switch the Shuttle DS57U OpenWrt from the BUFFALO router to a direct ONU connection temporarily, and verify the following in order. The migration of the entire home LAN and turning the BUFFALO router into an AP are not included in this procedure.

| Phase | Activity | Completion Condition |
|---|---|---|
| 2A | Direct ONU connection for IPv6 IPoE | OpenWrt itself has a global IPv6 address, default route, and external IPv6 connectivity |
| 2B | MAP-E info retrieval/verification | Can record measured or OCN-provided IPv6 prefix, IPv4 rules, BR, EA bits, PSID/offset, and port set sources/values |
| 2C | IPv4 over IPv6 | IPv4 communication for the test PC via MAP-E succeeds, and IPv4-in-IPv6 is observed on the WAN |
| 2D | Port sets | Multiple allocated port ranges are configured in NAT, and their actual usage can be confirmed from an external observation point |

Success in IPv6 (2A) alone does not mean MAP-E success. Web browsing (2C) alone does not complete 2D. OCN guides the use of IPv4 over IPv6 assuming compatible devices, so actual device verification is required for MAP-E on OpenWrt. [OCN IPv6 Internet Connection](https://support.ocn.ne.jp/personal/purpose/detail/pid2900000jzj/)

## 2. Values Carried Over from Phase 1

The following are values from the [Phase 1 records](phase1-setup.md) and do not necessarily apply after the direct ONU connection.

| Item | Status Confirmed in Phase 1 |
|---|---|
| Hardware / OS | Shuttle DS57U, OpenWrt 25.12.5 x86/64, ext4 |
| Lower blue cable | `eth0` / Intel i211 / WAN. Currently connected to BUFFALO LAN |
| Upper white cable | `eth1` / Intel i218-LM / `br-lan` / Connected to test PC |
| OpenWrt LAN | `192.168.1.1/24`, SSH/LuCI accessible |
| Phase 1 WAN | `192.168.11.108/24`, gateway `192.168.11.1` |
| IPv6 config | `network.wan6.device='eth0'`, `network.wan6.proto='dhcpv6'` |
| Storage | root 98.3 MiB, approx. 72.1 MiB free at end of Phase 1 |
| Existing backup | `backups/phase1-baseline.tar.gz`, SHA-256 `dce1e58a40a79eb93c53b1500b616bfd6007987f8992fc04076fee28e715e7bf` |

On 2026-09-21, the SHA-256 match with the backup file on the PC was reconfirmed. `backups/` is not tracked by Git, as the backup contains credentials.

## 3. Common Preparation and Recovery Path

### 3.1 Wiring, Connections, and Work Logging

Before starting, log the power and cable states of the ONU, BUFFALO, DS57U, and test PC. Maintain the white LAN cable and the `192.168.1.1` management route. Only the blue WAN cable will be moved from the BUFFALO LAN to the ONU in 2A. If the device change is not immediately reflected by the ONU, follow the OCN/NTT instructions to verify link status, and if needed, revert to BUFFALO to restore connectivity. Do not hardcode IPv4 addresses or MAP rules without evidence.

```text
Normal state: ONU -> BUFFALO -> [Blue, Lower eth0] DS57U [White, Upper eth1] -> Test PC
Test state: ONU -----------> [Blue, Lower eth0] DS57U [White, Upper eth1] -> Test PC
```

During testing, devices under the BUFFALO router on the home network may lose internet connectivity. Connect the PC from the wired LAN side `192.168.1.x` to OpenWrt and specify the source interface so test results aren't misattributed to Wi-Fi routing. To free an ONU port, unplug the cable connecting the ONU and BUFFALO WAN at the ONU end, and plug the BUFFALO end of the blue cable into that ONU port.

### 3.2 Backups, Free Space, Packages

Confirm Phase 1 settings are present and check root free space. Use `.local-ssh/id_ed25519_v2` for SSH, running multiple commands in the same session. Connect from the PC with the command below and execute the router commands in order.

```powershell
ssh -i .local-ssh/id_ed25519_v2 -o IdentitiesOnly=yes root@192.168.1.1
```

```sh
date -Iseconds
cat /etc/openwrt_release
uci show network
uci show firewall
df -h /
sysupgrade -l
umask 077
mkdir -p /root/phase2-prep
cp -p /etc/config/network /root/phase2-prep/network
cp -p /etc/config/firewall /root/phase2-prep/firewall
cp -p /etc/config/dhcp /root/phase2-prep/dhcp
sysupgrade -b /tmp/phase2-before-wan.tar.gz
sha256sum /tmp/phase2-before-wan.tar.gz
```

Copy the backup to the PC and confirm the SHA-256 matches. Since OpenWrt lacked an SFTP server in Phase 1, use `-O` for Windows `scp`. [OpenWrt Backup Guide](https://openwrt.org/docs/guide-user/troubleshooting/backup_restore)

```powershell
scp -O -i .local-ssh/id_ed25519_v2 -o BatchMode=yes root@192.168.1.1:/tmp/phase2-before-wan.tar.gz backups/
certutil -hashfile backups\phase2-before-wan.tar.gz SHA256
```

Obtain and install the `map` package while IPv4 internet is still available via BUFFALO. First, verify the package exists and check required space. Do not create the MAP interface after installation. Use `apk` for package management in OpenWrt 25.12. [OpenWrt apk](https://openwrt.org/docs/guide-user/additional-software/apk), [OpenWrt 25.12.5 MAP implementation](https://raw.githubusercontent.com/openwrt/openwrt/v25.12.5/package/network/ipv6/map/files/map.sh)

```sh
apk update
apk search map
apk add map
apk info -e map
command -v mapcalc
test -f /lib/netifd/proto/map.sh
df -h /
uci -q get network.wan6.iface_map
ubus call network.interface dump
```

Stop installation if `apk search map` fails to find the package, if dependencies can't be resolved, or if space is insufficient. Do not run `apk upgrade`. Ensure no auto-generated MAP interface exists before proceeding to 2A. If `iface_map` is enabled, research how current and auto settings interact before proceeding to 2A. [OpenWrt IPv6 Config](https://openwrt.org/docs/guide-user/network/ipv6/configuration)

### 3.3 Git-Managed Configuration Baseline

Git records the intended, sanitized router configuration; it is not an automatic synchronization mechanism and must not apply changes to the router. Before any Phase 2 configuration change, capture a reviewable baseline in `router-config/` and commit it only after checking that it contains no credentials or personal network data that should remain private. Track sanitized UCI exports for `network`, `firewall`, and `dhcp`, together with the apply, verification, and rollback instructions. Do not track sysupgrade backups, packet captures, DHCP leases, SSH keys, password hashes, Wi-Fi/PPPoE credentials, or MAP-E values acquired from the live connection. `backups/` remains untracked.

Treat a Git change as a proposed change. Review its diff first, take and verify the pre-change backup from 3.2, and then apply the equivalent deliberate UCI commands on the router. Before committing/reloading, inspect `uci changes` and verify that `br-lan`, `eth1`, and `192.168.1.1/24` remain unchanged. Record the executed commands, the sanitized diff, router output, and the rollback result in the implementation log. A committed Git baseline documents intent and review history; the verified backup remains the recovery artifact.

### 3.4 Automatic WAN Cable-Switch Test Procedure

This procedure tests whether DS57U can establish the direct OCN connection automatically after a single physical WAN cable move. Here, “blue WAN cable” means the cable attached to DS57U's lower `eth0`; it is not a LAN cable. The test PC must stay wired to the white upper `eth1` LAN port. Do not connect BUFFALO WAN and DS57U `eth0` to the ONU-side hub at the same time.

| Step | Owner | Action | Pass condition / boundary |
|---|---|---|---|
| 1 | Codex | Complete package, backup, and configuration preparation while DS57U remains behind BUFFALO. | `map` is installed; `network.wan6.iface_map='1'` is committed; pre-change backup hash matches on router and PC. Completed on 2026-09-23; see the execution log. |
| 2 | Codex | Confirm the pre-switch WAN configuration without changing active addressing. | `wan` remains DHCP on `eth0`; `wan6` remains DHCPv6 on `eth0`; the WAN firewall zone contains `wan` and `wan6`; no static `network.map` rule exists. No additional WAN change is required. |
| 3 | User | Move the ONU-side connection from BUFFALO to DS57U. | Only DS57U is connected to the ONU-side hub. The current home network may lose internet. |
| 4 | Codex | Once the PC regains cloud access through DS57U, inspect automatic IPv6 and MAP-E state. | A valid direct `wan6` state is recorded; automatic IPv4 succeeds only if dynamic `wan6_4` is present and verified. |
| 5 | User | Return the ONU-side connection to BUFFALO. | Only BUFFALO is connected to the ONU-side hub; the normal home internet path returns. |
| 6 | Codex | Verify DS57U behind BUFFALO and restore its pre-test UCI state only if requested. | `wan`/`wan6` recover through BUFFALO. Leaving `iface_map='1'` is safe and permits another direct test; no restoration is normally required. |

#### Step 1 — Codex preparation (completed)

The completed work is documented in the 2026-09-23 execution log: a hash-verified pre-change backup was copied to the PC, package `map-7` was installed, and `network.wan6.iface_map='1'` was committed. `map` provides `/lib/netifd/proto/map.sh`; when DHCPv6 supplies MAP-E data, `iface_map='1'` permits netifd to add a dynamic `wan6_4` MAP interface. No static MAP-E rule was created because direct-service values are unknown.

#### Step 2 — Codex pre-switch confirmation

Immediately before the cable move, in the existing PC-to-DS57U SSH session, run read-only checks:

```sh
uci show network.wan
uci show network.wan6
uci show firewall.@zone[1]
uci -q get network.map; echo STATIC_MAP_EXIT=$?
apk info -e map; echo MAP_PACKAGE_EXIT=$?
ubus call network.interface.wan6 status
```

Expected results: `wan` is DHCP on `eth0`; `wan6` is DHCPv6 on `eth0` with `iface_map='1'`; `STATIC_MAP_EXIT=1`; `MAP_PACKAGE_EXIT=0`; and LAN is not modified. Do not run `uci commit`, `ifdown`, or reboot in this step. The existing DHCP `wan` interface may fail to acquire native IPv4 after direct ONU connection; this alone is expected and is not a failure.

#### Step 3 — User cable move

1. Keep the PC wired only to DS57U `eth1`; disconnect Wi-Fi or other active routes used for testing.
2. Disconnect BUFFALO WAN from the ONU-side hub and confirm that BUFFALO is no longer attached to that hub.
3. Move the blue DS57U `eth0` WAN cable from BUFFALO LAN to the same ONU-side hub port.
4. Do not reboot DS57U and do not connect BUFFALO WAN to the ONU-side hub while DS57U is connected.
5. Wait up to two minutes for the Ethernet link, RA, and DHCPv6 exchange. Cloud access may disappear during this interval, so no Codex action is expected until the PC can reach the service through DS57U.

#### Step 4 — Codex direct-ONU verification

After cloud access returns, Codex runs the following over SSH and records the unredacted raw output only in ignored local logs; the phase document receives a redacted relevant excerpt:

```sh
date -Iseconds
cat /sys/class/net/eth0/carrier
ubus call network.interface.wan status
ubus call network.interface.wan6 status
ubus call network.interface.wan6_4 status
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

Classify the result before making any further setting change:

- **Automatic success:** `wan6` is up with a direct IPv6 route; `wan6_4` is up; an IPv4 default route and MAP-generated SNAT rules exist; IPv6 and IPv4 pings pass. Continue to the Phase 2C/2D evidence checks.
- **IPv6-only:** `wan6` is up but `wan6_4` is absent or down. Do not enter a static MAP-E rule. Capture DHCPv6/RA evidence and treat the automatic IPv4 attempt as failed or inconclusive.
- **No IPv6:** `wan6` is down, lacks a default route, or fails external IPv6 ping. Do not modify UCI; proceed directly to Step 5.

#### Step 5 — User return to BUFFALO

1. Disconnect DS57U `eth0` from the ONU-side hub.
2. Reconnect BUFFALO WAN to the ONU-side hub.
3. Keep DS57U `eth0` connected to a BUFFALO LAN port as in the normal topology.
4. Wait up to two minutes for BUFFALO and DS57U DHCP/DHCPv6 recovery. Confirm normal home connectivity before requesting Step 6.

#### Step 6 — Codex post-return verification and optional restoration

Codex verifies the normal DS57U path with:

```sh
ubus call network.interface.wan status
ubus call network.interface.wan6 status
ubus call network.interface.wan6_4 status
ip route
ip -6 route
ping -c 4 192.168.11.1
ping -c 4 1.1.1.1
ping -6 -c 4 2606:4700:4700::1111
```

No router-setting restoration is normally needed: `map` is inert without MAP-E DHCPv6 data, and `iface_map='1'` does not create `wan6_4` through the current BUFFALO path. If the automatic direct-ONU test is abandoned and the original UCI state is specifically desired, use the reversible change below, then verify the commands above. Do not remove package `map`; retaining it preserves the tested preparation for a future attempt.

```sh
uci delete network.wan6.iface_map
uci commit network
ubus call network reload
```

### 3.5 BUFFALO Comparison Data

Before rewiring, record the current IPv4 address, IPv6 prefix, available port ranges, and connection type from the BUFFALO status screen. Check IPoE provisioning status on the OCN MyPage. The values `153.243.46.0` and `1392-1407`, `2416-2431`, `3440-3455` in `router-project.md` are past examples and shouldn't be transcribed as Phase 2 settings. [OCN Provisioning Check](https://support.ocn.ne.jp/hikari/faq/detail/pid2300000h6p/)

## 4. Phase 2A — Direct ONU Connection for IPv6 IPoE

### 4.1 Wiring Changes

Before changing router settings, disconnect the existing cable connecting the ONU and BUFFALO WAN at the ONU side. Then move the BUFFALO end of the blue lower WAN cable to the ONU. Leave the white upper LAN cable connected to the test PC. Confirm SSH/LuCI access to `192.168.1.1` from the PC. Since Phase 1's `wan6` is already `eth0` DHCPv6, observe without changing settings first. Even if the IPv4 DHCP `wan` cannot get an IPv4 directly from the ONU, it is not considered a failure at this stage.

### 4.2 Router Observation

```sh
cat /sys/class/net/eth0/carrier
ubus call network.interface.wan6 status
ip -6 addr show dev eth0
ip -6 route
logread -e odhcp6c
ping -6 -c 4 2606:4700:4700::1111
nslookup openwrt.org
```

When observing RA, DHCPv6, or IPv6 traffic, start the following in a separate SSH session and Ctrl-C after capturing necessary packets. Because personal prefixes and peers will be included, save the pcap in untracked locations like `backups/`.

```sh
tcpdump -ni eth0 -vv 'icmp6 or (udp port 546 or udp port 547)'
```

Log `wan6`'s `up` state, acquired global IPv6 address, prefix length, delegated prefix presence, IPv6 default route, DNS, external IPv6 ping, and timestamp. A global address on WAN does not guarantee prefix delegation to LAN, so test PC IPv6 might not work. Evaluate 2A success based on OpenWrt's own IPv6 connectivity; record LAN IPv6 separately. [OpenWrt IPv6 Config](https://openwrt.org/docs/guide-user/network/ipv6/configuration)

Also verify OCN's [IPoE Connection Check Site](https://v6test.ocn.ne.jp/) from a device actually using the test route. If the PC has Wi-Fi or other paths, do not treat those results as proof for OpenWrt.

## 5. Phase 2B — Retrieving and Calculating MAP-E Info

MAP-E determines shared IPv4 addresses and permitted ports based on IPv6 prefixes, IPv4 rules, EA bits, PSID/offset, BR, etc. RFC 7598 defines a method to deliver info via DHCPv6 Softwire46 options, but what this OCN line provides is unmeasured. [RFC 7597](https://www.rfc-editor.org/rfc/rfc7597), [RFC 7598](https://www.rfc-editor.org/rfc/rfc7598)

Fill out the table below with measured values or OCN-confirmed values. Do not apply MAP-E settings while blanks remain.

| Item | Measured Value | Source/Time |
|---|---|---|
| `wan6` global IPv6 / length | Unmeasured |  |
| Delegated prefix / length | Unmeasured |  |
| MAP rule IPv6 prefix / length | Unmeasured |  |
| MAP rule IPv4 prefix / length | Unmeasured |  |
| EA bits | Unmeasured |  |
| PSID length, PSID, offset | Unmeasured |  |
| BR IPv6 address | Unmeasured |  |
| Derived IPv4 address | Unmeasured |  |
| Permitted port ranges | Unmeasured |  |

Cross-reference DHCPv6 received info, `ubus call network.interface.wan6 status`, `logread -e odhcp6c`, and concurrent BUFFALO displays. Do not fill BR or rules with guesses. OpenWrt's `mapcalc` takes `<interface|*> <rule1> [rule2] ...` and outputs derived IPv4 addresses, PSID, port sets, etc. [OpenWrt mapcalc source](https://raw.githubusercontent.com/openwrt/openwrt/v25.12.5/package/network/ipv6/map/src/mapcalc.c)

Construct the rule string only after confirming sources for all values, and run a **read-only calculation** first. Replace bracketed portions with actual values. If explicit additions are required, log them based on OCN data and `mapcalc` supported fields.

```sh
MAP_RULE='type=map-e,ipv6prefix=<RULE_V6>,prefix6len=<V6_LEN>,ipv4prefix=<RULE_V4>,prefix4len=<V4_LEN>,ealen=<EA_BITS>,offset=<OFFSET>,br=<BR_V6>'
mapcalc wan6 "$MAP_RULE"
```

Record `RULE_BMR`, `RULE_1_IPV4ADDR`, `RULE_1_PSIDLEN`, `RULE_1_PORTSETS`, and `RULE_1_BR` and check for contradictions with BUFFALO displays from the same period. If the prefix changed, it might not match Phase 1 recorded IPv4 or ports. If `RULE_BMR` is empty, shows `NO_MATCHING_PD`, or has a calculation error, do not proceed; review prefixes and rule sources. [OpenWrt mapcalc source](https://raw.githubusercontent.com/openwrt/openwrt/v25.12.5/package/network/ipv6/map/src/mapcalc.c)

## 6. Phase 2C — IPv4 over IPv6 with MAP-E

Configure this only after 2B values are confirmed and `mapcalc` results are checked. The following is **the procedure when re-entering the verified complete rule string into `MAP_RULE`**. If the shell is reopened, variables from 2B will be lost. In Phase 1 UCI, it was `firewall.@zone[1].name='wan'`, but verify this before applying.

```sh
: "${MAP_RULE:?Set the MAP_RULE verified in 2B}"
test "$(uci get firewall.@zone[1].name)" = wan || exit 1
uci -q get network.map && exit 1
uci set network.map='interface'
uci set network.map.proto='map'
uci set network.map.maptype='map-e'
uci set network.map.tunlink='wan6'
uci set network.map.zone='wan'
uci set network.map.rule="$MAP_RULE"
uci add_list firewall.@zone[1].network='map'
uci changes
```

Check `uci changes` to ensure LAN's `br-lan`, `eth1`, and `192.168.1.1/24` are unchanged. If all is well:

```sh
uci commit network
uci commit firewall
/etc/init.d/firewall restart
ifup map
ubus call network.interface.map status
ip -4 addr
ip -4 route
nft list ruleset
logread -e map
```

OpenWrt 25.12.5's `map.sh` configures the IPv4-in-IPv6 tunnel and IPv4 default route for `map-e`, passing SNAT info corresponding to the calculated port sets to netifd. Confirm that generated interfaces, routes, and nftables rules match. [OpenWrt map.sh](https://raw.githubusercontent.com/openwrt/openwrt/v25.12.5/package/network/ipv6/map/files/map.sh)

Verify the wired test PC's IPv4, specify the source, and try IPv4 DNS, ping, and HTTPS. Run `tcpdump -ni eth0 'ip6 proto 4'` on the WAN, generate IPv4 traffic from the PC, and observe IPv4-in-IPv6. Don't mistakenly attribute success to PC Wi-Fi.

```powershell
ipconfig /all
nslookup openwrt.org 192.168.1.1
ping -4 -S <TEST_PC_LAN_IP> -n 4 1.1.1.1
curl.exe --noproxy * --interface <TEST_PC_LAN_IP> -4 --connect-timeout 5 --max-time 15 -sSI https://openwrt.org/
```

Even if the MAP interface is `up`, 2C is not complete without actual IPv4 communication, DNS, and tunnel observation.

## 7. Phase 2D — Actual Use of Allocated Port Sets

First, compare `mapcalc`'s `RULE_1_PORTSETS` with `nft list ruleset`'s SNAT ranges. Then, generate multiple TCP/UDP requests from the wired test PC to an external controllable server, and cross-reference the public IPv4 address and source port seen by the server with the router's `conntrack` output.

```sh
conntrack -L
nft list ruleset
tcpdump -ni eth0 'ip6 proto 4'
```

Verify that each allocated range is used at the external observation point, and record that no out-of-range ports are used. If only some ranges are used naturally, note them as "Unobserved" and don't count 2D as complete. Even if an external server isn't available, document nftables settings and actual traffic confirmation separately. If needed, perform a separate test for inbound reachability to ports within the allocated range.

## 8. Recovery on Failure

### Reverting Wiring Only

First, return the ONU end of the lower blue WAN cable to the BUFFALO LAN, and reconnect the removed ONU-BUFFALO WAN cable to the ONU. Leave the white LAN cable as is. Confirm `eth0` acquires `192.168.11.x` from BUFFALO again, and IPv4/DNS/HTTPS recovers on the PC.

```sh
ifup wan
ifup wan6
ubus call network.interface.wan status
ip route
ping -c 4 192.168.11.1
ping -c 4 1.1.1.1
```

### Reverting MAP Settings

If changes were made in 2C, verify the `/root/phase2-prep/network`, `firewall`, and `dhcp` files saved in 3.2 before restoring. Compare current files with saved ones using `diff` to account for intentional changes since Phase 1.

```sh
diff -u /root/phase2-prep/network /etc/config/network
diff -u /root/phase2-prep/firewall /etc/config/firewall
cp -p /root/phase2-prep/network /etc/config/network
cp -p /root/phase2-prep/firewall /etc/config/firewall
cp -p /root/phase2-prep/dhcp /etc/config/dhcp
ubus call network reload
/etc/init.d/firewall restart
ubus call network.interface.wan status
```

If SSH drops, reconnect to `192.168.1.1` via the white LAN cable PC. If config files are lost, use `backups/phase2-before-wan.tar.gz` on the PC or Phase 1 backup, confirming contents before following [OpenWrt Restore Guide](https://openwrt.org/docs/guide-user/troubleshooting/backup_restore).

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

## 10. References

- [OCN IPv6 Internet Connection](https://support.ocn.ne.jp/personal/purpose/detail/pid2900000jzj/) — IPoE provisioning, compatible devices, OCN connection check.
- [OpenWrt IPv6 configuration](https://openwrt.org/docs/guide-user/network/ipv6/configuration) — `wan6`, DHCPv6, prefix delegation, and MAP auto-config.
- [OpenWrt 25.12.5 MAP implementation](https://raw.githubusercontent.com/openwrt/openwrt/v25.12.5/package/network/ipv6/map/files/map.sh) / [mapcalc](https://raw.githubusercontent.com/openwrt/openwrt/v25.12.5/package/network/ipv6/map/src/mapcalc.c) — UCI items, tunneling, port set calculation.
- [OpenWrt apk](https://openwrt.org/docs/guide-user/additional-software/apk) / [Backup & Restore](https://openwrt.org/docs/guide-user/troubleshooting/backup_restore).
- [RFC 7597](https://www.rfc-editor.org/rfc/rfc7597) / [RFC 7598](https://www.rfc-editor.org/rfc/rfc7598) — MAP-E and DHCPv6 Softwire46 options.
