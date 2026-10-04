# Phase 2 Implementation Procedure — Verifying IPv6 IPoE / MAP-E via Direct OCN Connection

Last updated: 2026-10-04
Rebuild manual. Dated results and verification limits: [Phase 2 execution history](docs/history/phase2-setup.md).

## 1. Objective and Completion Conditions

Switch the Shuttle DS57U OpenWrt from the BUFFALO router to a direct ONU connection temporarily, and verify the following in order. The migration of the entire home LAN and turning the BUFFALO router into an AP are not included in this procedure.

| Phase | Activity | Completion Condition |
|---|---|---|
| 2A | Direct ONU connection for IPv6 IPoE | OpenWrt itself has a global IPv6 address, default route, and external IPv6 connectivity |
| 2B | MAP-E info retrieval/verification | Can record measured or OCN-provided IPv6 prefix, IPv4 rules, BR, EA bits, PSID/offset, and port set sources/values |
| 2C | IPv4 over IPv6 | IPv4 communication for the test PC via MAP-E succeeds, and IPv4-in-IPv6 is observed on the WAN |
| 2D | Port sets | Multiple allocated port ranges are configured in NAT, and their actual usage can be confirmed from an external observation point |

Success in IPv6 (2A) alone does not mean MAP-E success. Web browsing (2C) alone does not complete 2D. OCN guides the use of IPv4 over IPv6 assuming compatible devices, so actual device verification is required for MAP-E on OpenWrt. [OCN IPv6 Internet Connection](https://support.ocn.ne.jp/personal/purpose/detail/pid2900000jzj/)

## 2. Rebuild Baseline

Recheck these design values after Phase 1. Dated addresses, storage readings,
and backup hashes are retained in the [Phase 1 records](docs/history/phase1-setup.md).

| Item | Required baseline / build example |
|---|---|
| Hardware / OS | Shuttle DS57U, OpenWrt 25.12.5 x86/64, ext4 |
| Lower blue cable | `eth0` / Intel i211 / WAN in the Phase 1 topology |
| Upper white cable | `eth1` / Intel i218-LM / `br-lan` / Connected to test PC |
| OpenWrt LAN | `192.168.1.1/24`, SSH/LuCI accessible |
| Phase 1 WAN | DHCP `192.168.11.x/24`, gateway `192.168.11.1`; reacquire the actual lease |
| IPv6 config | `network.wan6.device='eth0'`, `network.wan6.proto='dhcpv6'` |
| Storage | Check current free space; use the storage expansion manual if needed |
| Backup | Create a fresh external backup and record its matching router/PC hash |

`backups/` is not tracked by Git because backups contain credentials.

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

Stop installation if the package is unavailable, dependencies cannot be resolved,
or space is insufficient. Do not run `apk upgrade`. Review any existing MAP
interfaces before installing the automation in 3.4; avoid competing static rules.
[OpenWrt IPv6 Config](https://openwrt.org/docs/guide-user/network/ipv6/configuration)

### 3.3 Git-Managed Configuration Baseline

Git records the intended, sanitized router configuration; it is not an automatic synchronization mechanism and must not apply changes to the router. Before any Phase 2 configuration change, capture a reviewable baseline in `router-config/` and commit it only after checking that it contains no credentials or personal network data that should remain private. Track sanitized UCI exports for `network`, `firewall`, and `dhcp`, together with the apply, verification, and rollback instructions. Do not track sysupgrade backups, packet captures, DHCP leases, SSH keys, password hashes, Wi-Fi/PPPoE credentials, or MAP-E values acquired from the live connection. `backups/` remains untracked.

Treat a Git change as a proposed change. Review its diff first, take and verify the pre-change backup from 3.2, and then apply the equivalent deliberate UCI commands on the router. Before committing/reloading, inspect `uci changes` and verify that `br-lan`, `eth1`, and `192.168.1.1/24` remain unchanged. Record the executed commands, the sanitized diff, router output, and the rollback result in the implementation log. A committed Git baseline documents intent and review history; the verified backup remains the recovery artifact.

### 3.4 Prepare automatic MAP-E before the cable switch

Keep the test PC on upper `eth1` and preserve `192.168.1.1` management.
Use the checked-in [reconcile script](tools/router/mape-auto-reconcile.sh)
and [hotplug hook](tools/router/99-mape-auto). A dynamic `wan6_4` is preferred
when DHCPv6 supplies a usable rule. The guarded fallback creates `mape_auto`
only without WAN DHCP IPv4, without an active dynamic MAP, and with a matching
OCN `2400:4050:8000::/33` address and successful `LEGACY=1 mapcalc` result.
The snapshot is provider/allocation-specific; do not reuse it for another
provider or an unmatched prefix.

After the backup in 3.2, enable DHCPv6 MAP support on the router:

```sh
uci set network.wan6.iface_map='1'
uci changes
uci commit network
```

Confirm only the intended WAN6 option changed. From the PC, stage the files:

```powershell
rtk proxy scp -O -i .local-ssh/id_ed25519_v2 -o BatchMode=yes tools/router/mape-auto-reconcile.sh root@192.168.1.1:/tmp/mape-auto-reconcile-new
rtk proxy scp -O -i .local-ssh/id_ed25519_v2 -o BatchMode=yes tools/router/99-mape-auto root@192.168.1.1:/tmp/99-mape-auto-new
rtk proxy certutil -hashfile tools/router/mape-auto-reconcile.sh SHA256
rtk proxy certutil -hashfile tools/router/99-mape-auto SHA256
```

On the router, syntax-check both and match hashes before installing:

```sh
sh -n /tmp/mape-auto-reconcile-new
sh -n /tmp/99-mape-auto-new
sha256sum /tmp/mape-auto-reconcile-new /tmp/99-mape-auto-new
cp /tmp/mape-auto-reconcile-new /usr/sbin/mape-auto-reconcile
cp /tmp/99-mape-auto-new /etc/hotplug.d/iface/99-mape-auto
chmod 0755 /usr/sbin/mape-auto-reconcile /etc/hotplug.d/iface/99-mape-auto
```

Review WAN zone identity (`firewall.@zone[1].name='wan'`) because the script
uses that zone index. Keep `wan` DHCP and `wan6` DHCPv6 on `eth0`; do not
create an independent `network.map` alongside this automation.
On a direct supported allocation it derives the rule from current WAN6,
sets `legacymap=1` and `encaplimit=ignore`, and installs a derived nft ICMP
echo-identifier SNAT include. This avoids the recorded fw4 omission of MAP
ICMP SNAT entries. TCP/UDP port-set NAT remains the MAP package's work.

Before the physical change, save this manual and the rollback path locally.
Cloud access may disappear. Keep BUFFALO WAN and DS57U WAN from being attached
to the ONU-side hub simultaneously. Move only DS57U's lower WAN connection
for the isolated test in Section 4; use the separate
[replacement manual](phase2-router-mode-replacement.md) for the final topology.

After link/RA/DHCPv6 settle, classify the route by live state: dynamic
`wan6_4`, guarded static `mape_auto`, IPv6-only, or no IPv6. Interface `up`
alone is insufficient: run Sections 5-7. If IPv6/IPv4 fail, return cables
as in Section 8. Reboot, physical reconnect, new-prefix allocation, and
return-to-BUFFALO cleanup need separate acceptance runs; the latest history
does not claim them tested.

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

MAP-E derives shared IPv4 and allowed ports from the CE IPv6 and provider rule.
On the recorded OCN line DHCPv6 supplied no usable Softwire46 rule; therefore
`iface_map=1` alone is insufficient. Use the guarded automation from 3.4 and
cross-check its calculation offline using `tools/calculate-ocn-mape.ps1`.
The capture and subsequent successful trials remain in the execution history.

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
status. Record absent DHCPv6 delegation explicitly rather than inventing it.
The guarded fallback derives an explicit `/64` calculation prefix from the
observed WAN6 address; that is not evidence of provider-delegated LAN IPv6.
Do not activate a rule with missing required calculation inputs or with a
CE address from the BUFFALO-behind path rather than direct ONU.

| Item | Measured Value | Source/Time |
|---|---|---|
| `wan6` global IPv6 / length | `<CURRENT_DIRECT_WAN6_IPV6>/<LENGTH>` | Direct-ONU wan6 status and current timestamp |
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
rtk proxy powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\calculate-ocn-mape.ps1 <DIRECT_WAN6_GLOBAL_IPV6>
```

Save the output in ignored `backups/`, record its SHA-256 in the execution log,
and compare the input with `ubus call network.interface.wan6 status`.
Do not fill BR or rules with guesses. OpenWrt's `mapcalc`
takes `<interface|*> <rule1> [rule2] ...` and independently outputs derived
IPv4 addresses, PSID, and port sets.
[OpenWrt mapcalc source](https://raw.githubusercontent.com/openwrt/openwrt/v25.12.5/package/network/ipv6/map/src/mapcalc.c)

Construct the rule string only after confirming the local calculator result and run a
**read-only calculation** first. Replace bracketed portions with those exact
values. `mapcalc` is the independent local check: its IPv4 address, PSID, BR,
and port sets must agree with the local result before any UCI change.

```sh
MAP_RULE='type=map-e,ipv6prefix=<RULE_V6>,prefix6len=<V6_LEN>,ipv4prefix=<RULE_V4>,prefix4len=<V4_LEN>,ealen=<EA_BITS>,offset=<OFFSET>,br=<BR_V6>,pd=<CURRENT_DIRECT_64_PREFIX>,pdlen=64'
LEGACY=1 mapcalc wan6 "$MAP_RULE"
```

Record `RULE_BMR`, `RULE_1_IPV4ADDR`, `RULE_1_PSIDLEN`, `RULE_1_PORTSETS`, and `RULE_1_BR` and compare them with the local result. If the prefix changed, rerun the script; a no-match is a safe stop requiring a newly verified rule snapshot, not an invitation to reuse a prior IPv4 address or port set. If `RULE_BMR` is empty, shows `NO_MATCHING_PD`, or has a calculation error, do not proceed. [OpenWrt mapcalc source](https://raw.githubusercontent.com/openwrt/openwrt/v25.12.5/package/network/ipv6/map/src/mapcalc.c)

## 6. Phase 2C — IPv4 over IPv6 with MAP-E

After the 2B calculation agrees with current direct-WAN6 state, use the
installed automation from 3.4. Do not paste a historical static rule.

```sh
/usr/sbin/mape-auto-reconcile; echo RECONCILE_EXIT=$?
ubus call network.interface.wan6 status
ubus call network.interface.wan6_4 status
ubus call network.interface.mape_auto status
uci -q show network.mape_auto
uci -q show firewall.mape_auto_icmp
ip -4 route
ip -6 route
nft list ruleset
fw4 check
logread -e mape-auto
ping -4 -c 4 1.1.1.1
ping -6 -c 4 2606:4700:4700::1111
```

For the fallback require `mape_auto` up, an IPv4 default route,
`legacymap=1`, `encaplimit=ignore`, matching TCP/UDP SNAT port sets, and the
derived ICMP include at `chain-prepend/srcnat`. For a dynamic rule require
`wan6_4` up and verify its actual routing/NAT instead. An absent inactive
alternative interface is expected. `RECONCILE_EXIT=0` may also mean a guard
stopped activation; always check live state and traffic.
The source and latest verification record describe the fw4 warning for its
omitted generated ICMP section; verify the added nft rule rather than treating
that warning alone as success or failure.

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

Before returning behind BUFFALO, preserve the current configs/scripts and compare them with the pre-test backup. The reconcile script removes its generated map/include when WAN DHCP IPv4 returns; run it after DHCP settles and verify that cleanup actually occurred. If restoring pre-test configuration manually, first disable the hotplug hook so it cannot recreate the generated state. If changes were made in 2C, verify the `/root/phase2-prep/network`, `firewall`, and `dhcp` files saved in 3.2 before restoring. Compare current files with saved ones using `diff` to account for intentional changes since Phase 1.

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

## 9. Execution records and acceptance checklist

Record each run in [Phase 2 history](docs/history/phase2-setup.md), using the
[common record template](docs/history/README.md). Start a fresh checklist for
backup/hash, package/source installation, isolated topology, 2A IPv6, 2B rule
agreement, 2C client traffic and WAN encapsulation, 2D external port evidence,
and any performed rollback. Do not inherit checked boxes from an earlier run.

## 10. References

- [OCN IPv6 Internet Connection](https://support.ocn.ne.jp/personal/purpose/detail/pid2900000jzj/) — IPoE provisioning, compatible devices, OCN connection check.
- [OpenWrt IPv6 configuration](https://openwrt.org/docs/guide-user/network/ipv6/configuration) — `wan6`, DHCPv6, prefix delegation, and MAP auto-config.
- [OpenWrt 25.12.5 MAP implementation](https://raw.githubusercontent.com/openwrt/openwrt/v25.12.5/package/network/ipv6/map/files/map.sh) / [mapcalc](https://raw.githubusercontent.com/openwrt/openwrt/v25.12.5/package/network/ipv6/map/src/mapcalc.c) — UCI items, tunneling, port set calculation.
- [OpenWrt apk](https://openwrt.org/docs/guide-user/additional-software/apk) / [Backup & Restore](https://openwrt.org/docs/guide-user/troubleshooting/backup_restore).
- [RFC 7597](https://www.rfc-editor.org/rfc/rfc7597) / [RFC 7598](https://www.rfc-editor.org/rfc/rfc7598) — MAP-E and DHCPv6 Softwire46 options.
