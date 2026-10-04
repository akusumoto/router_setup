# Phase 2 Implementation Procedure — Verifying IPv6 IPoE / MAP-E via Direct OCN Connection

Last updated: 2026-10-04
Status: **Direct-ONU operation on 2026-10-04 proved native IPv6, DNS, IPv4 HTTPS, and IPv4 ping. The user reported Internet access through the router. Updated MAP-E automation is installed and verified to restore the required tunnel settings and ICMP identifier translation. Reboot/physical reconnect and downstream BUFFALO acceptance have not been retested.**

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

## 5. Phase 2B — Calculating MAP-E Info from the CE IPv6 Address

MAP-E determines the shared IPv4 address and permitted ports from the CE IPv6
address and the provider's MAP rule. The 2026-10-01 direct-ONU capture proved
that DHCPv6 does **not** return a Softwire46/MAP-E rule on this OCN Virtual
Connect line, so `iface_map='1'` cannot establish IPv4 automatically. For the
static path, run the offline local calculator
`tools/calculate-ocn-mape.ps1` with the direct-ONU CE IPv6 address, then
configure OpenWrt from its displayed rule.

The local script contains a narrow OCN rule snapshot, published as current in
2026-07 and matching the 2026-10-01 direct CE prefix. It performs the RFC 7597
EA-bit calculation offline and emits an OpenWrt `MAP_RULE`, IPv4 address, PSID,
and port ranges. It fails closed when the CE address does not match that
snapshot; update its rule source before retrying rather than selecting a guessed
rule. This avoids any internet dependency during the cable change. [Published
OCN rule snapshot](https://note.com/imototakashi/n/n4a9d91472639), [RFC
7597](https://www.rfc-editor.org/rfc/rfc7597), [RFC
7598](https://www.rfc-editor.org/rfc/rfc7598)

Fill out the table below from the local calculator and concurrent direct `wan6`
status. Do not apply a static rule while a field is blank or while the entered
CE address is from the BUFFALO-behind path rather than the direct ONU.

| Item | Measured Value | Source/Time |
|---|---|---|
| `wan6` global IPv6 / length | `2400:4050:c340:1600:82ee:73ff:feab:4af0/64` observed 2026-10-01; reacquire before use | Direct-ONU diagnostic, 2026-10-01 JST |
| Delegated prefix / length | Unmeasured |  |
| MAP rule IPv6 prefix / length | Unmeasured |  |
| MAP rule IPv4 prefix / length | Unmeasured |  |
| EA bits | Unmeasured |  |
| PSID length, PSID, offset | Unmeasured |  |
| BR IPv6 address | Unmeasured |  |
| Derived IPv4 address | Unmeasured |  |
| Permitted port ranges | Unmeasured |  |

Use the exact global `wan6` address/prefix visible during the direct session as
the local calculator input. On the PC, run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\calculate-ocn-mape.ps1 <DIRECT_WAN6_GLOBAL_IPV6>
```

Save the output in ignored `backups/`, record its SHA-256 in the execution log,
and compare the input with `ubus call network.interface.wan6 status`. The
observed 2026-10-01 address is evidence of the method, not an enduring
configuration value. Do not fill BR or rules with guesses. OpenWrt's `mapcalc`
takes `<interface|*> <rule1> [rule2] ...` and independently outputs derived
IPv4 addresses, PSID, and port sets.
[OpenWrt mapcalc source](https://raw.githubusercontent.com/openwrt/openwrt/v25.12.5/package/network/ipv6/map/src/mapcalc.c)

Construct the rule string only after confirming the local calculator result and run a
**read-only calculation** first. Replace bracketed portions with those exact
values. `mapcalc` is the independent local check: its IPv4 address, PSID, BR,
and port sets must agree with the local result before any UCI change.

```sh
MAP_RULE='type=map-e,ipv6prefix=<RULE_V6>,prefix6len=<V6_LEN>,ipv4prefix=<RULE_V4>,prefix4len=<V4_LEN>,ealen=<EA_BITS>,offset=<OFFSET>,br=<BR_V6>'
mapcalc wan6 "$MAP_RULE"
```

Record `RULE_BMR`, `RULE_1_IPV4ADDR`, `RULE_1_PSIDLEN`, `RULE_1_PORTSETS`, and `RULE_1_BR` and compare them with the local result. If the prefix changed, rerun the script; a no-match is a safe stop requiring a newly verified rule snapshot, not an invitation to reuse a prior IPv4 address or port set. If `RULE_BMR` is empty, shows `NO_MATCHING_PD`, or has a calculation error, do not proceed. [OpenWrt mapcalc source](https://raw.githubusercontent.com/openwrt/openwrt/v25.12.5/package/network/ipv6/map/src/mapcalc.c)

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

## 10. References

- [OCN IPv6 Internet Connection](https://support.ocn.ne.jp/personal/purpose/detail/pid2900000jzj/) — IPoE provisioning, compatible devices, OCN connection check.
- [OpenWrt IPv6 configuration](https://openwrt.org/docs/guide-user/network/ipv6/configuration) — `wan6`, DHCPv6, prefix delegation, and MAP auto-config.
- [OpenWrt 25.12.5 MAP implementation](https://raw.githubusercontent.com/openwrt/openwrt/v25.12.5/package/network/ipv6/map/files/map.sh) / [mapcalc](https://raw.githubusercontent.com/openwrt/openwrt/v25.12.5/package/network/ipv6/map/src/mapcalc.c) — UCI items, tunneling, port set calculation.
- [OpenWrt apk](https://openwrt.org/docs/guide-user/additional-software/apk) / [Backup & Restore](https://openwrt.org/docs/guide-user/troubleshooting/backup_restore).
- [RFC 7597](https://www.rfc-editor.org/rfc/rfc7597) / [RFC 7598](https://www.rfc-editor.org/rfc/rfc7598) — MAP-E and DHCPv6 Softwire46 options.
