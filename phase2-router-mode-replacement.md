# DS57U Replacement with BUFFALO Kept in Router Mode

## 1. Goal and boundary

Make the Shuttle DS57U/OpenWrt the router directly connected to the ONU while
keeping the BUFFALO WSR-6000AX8 in **router mode**.  Devices connected to
BUFFALO LAN ports or its Wi-Fi keep the existing IPv4 network
`192.168.11.0/24`, with BUFFALO at `192.168.11.1`.

Rebuild manual. Execution evidence: [replacement history](docs/history/phase2-router-mode-replacement.md). Complete the [Phase 2 direct-ONU checks](phase2-setup.md) before downstream replacement. A prior direct-ONU success does not establish BUFFALO acceptance after this topology change.

## 2. Intended topology

```text
ONU
 |
 |  DS57U lower port, eth0 (WAN)
 |
DS57U / OpenWrt
 |
 |  DS57U upper port, eth1 (LAN, 192.168.1.1/24)
 |
BUFFALO WAN port (DHCP client, reserved `192.168.1.2`)
 |
BUFFALO router mode (LAN gateway 192.168.11.1/24)
 |
+-- existing wired clients
`-- existing BUFFALO Wi-Fi clients
```

The DS57U LAN and BUFFALO LAN remain separate networks.  Connect the DS57U
LAN only to the **BUFFALO WAN/Internet** port.  Never connect a DS57U LAN port
to a BUFFALO LAN port for this design: that would join two DHCP servers on the
same Ethernet segment and cannot preserve the intended routed boundary.

The DS57U DHCP server reserves `192.168.1.2` for BUFFALO WAN MAC
`68:E1:DC:37:1D:10`.  BUFFALO must remain an automatic/DHCP WAN client; do not
enter `192.168.1.2` as a static WAN address in its UI.  The reservation avoids
an address collision while retaining DS57U as the gateway and DNS authority
for that WAN link.

IPv4 traffic will be NATed twice: first by BUFFALO (`192.168.11.0/24` to its
WAN address), then by DS57U to the direct OCN connection.  Normal outbound
internet access should work if the direct DS57U WAN is working.  Services that
need unsolicited inbound IPv4 connections need forwarding on both routers.
IPv6 must be verified after the cable move; its availability depends on the
direct OCN delegation and on BUFFALO receiving and delegating an IPv6 prefix
through its WAN.

## 3. Cable map: current to target

When starting behind BUFFALO, identify these three cables before the move:

| Cable | Current endpoint A | Current endpoint B | Target endpoint A | Target endpoint B |
|---|---|---|---|---|
| ONU cable | ONU-side hub/ONU | BUFFALO WAN | ONU-side hub/ONU | DS57U lower `eth0` WAN |
| Blue cable | BUFFALO LAN | DS57U lower `eth0` WAN | DS57U upper `eth1` LAN | BUFFALO WAN |
| White cable | DS57U upper `eth1` LAN | test PC | BUFFALO LAN | test PC |

This is therefore a cable-endpoint swap, not a one-cable move.  Label the
three cables before disconnecting them.  If the test PC is already connected
to a BUFFALO LAN switch, leave that PC connection in place and use the former
white cable for the DS57U-LAN-to-BUFFALO-WAN link instead.  Do not add a
second DS57U-LAN-to-BUFFALO connection.

## 4. Preflight: do this while the existing topology still works

1. Confirm the planned direct-ONU state on DS57U from a PC connected to its
   current LAN.  Keep an SSH session open to `root@192.168.1.1` using
   `.local-ssh/id_ed25519_v2`.

   ```sh
   date -Iseconds
   uci show network.wan
   uci show network.wan6
   uci show network.lan
   uci show firewall.@zone[1]
   uci show dhcp.buffalo_wan
   uci -q get network.map; echo STATIC_MAP_EXIT=$?
   apk info -e map; echo MAP_PACKAGE_EXIT=$?
   ubus call network.interface.lan status
   ubus call network.interface.wan6 status
   ```

   Require `wan` on `eth0` using DHCP, `wan6` on `eth0` using DHCPv6 with
   `iface_map='1'`, no static `network.map`, and the existing LAN on
   `eth1`/`br-lan` at `192.168.1.1/24`.  The existing Phase 2 preparation
   recorded `map` installed and `iface_map='1'`; re-check the live state before
   relying on it.

2. Create and hash a fresh DS57U sysupgrade backup before moving a cable.
   Retain it outside the router and do not put credentials or leases in Git.

3. Confirm the named DS57U DHCP reservation before moving a cable.  Confirm
   `192.168.1.2` is outside the active DHCP pool and does not appear in
   `/tmp/dhcp.leases`, then verify:

   ```sh
   uci show dhcp.buffalo_wan
   ```

   If the reservation is absent, create it with:

   ```sh
   uci set dhcp.buffalo_wan='host'
   uci set dhcp.buffalo_wan.name='buffalo-wan'
   uci set dhcp.buffalo_wan.mac='68:E1:DC:37:1D:10'
   uci set dhcp.buffalo_wan.ip='192.168.1.2'
   uci commit dhcp
   /etc/init.d/dnsmasq reload
   uci show dhcp.buffalo_wan
   ```

   The recorded DS57U DHCP pool is `192.168.1.100` through
   `192.168.1.249`, so `192.168.1.2` is intentionally excluded from dynamic
   allocation.  The reservation does not change the address of any device
   until the matching BUFFALO WAN interface requests a DHCP lease.

4. In the BUFFALO administration UI, record the current LAN address
   (`192.168.11.1/24`), router-mode setting, and WAN addressing mode.  Its WAN
   must be set to automatic/DHCP.  Do not set a static WAN address.  Do not
   change its LAN address, DHCP scope, Wi-Fi setup, or router mode for this
   procedure.

5. Record a short baseline from one device that will remain behind BUFFALO:
   its IPv4 address, gateway, DNS server, and one HTTPS request.  This is the
   evidence that `192.168.11.0/24` was retained after the move.

6. Ensure the PC has a path to a BUFFALO LAN port after the move.  It will no
   longer reach DS57U at `192.168.1.1` directly from `192.168.11.0/24` unless
   an explicit management route is later designed and applied.  BUFFALO's WAN
   address can be used to verify only the BUFFALO-to-DS57U uplink; it is not a
   substitute for DS57U management access.

## 5. Physical switchover

1. Leave DS57U powered on.  Do not reboot either router during the cable move.
2. Disconnect the ONU cable from the BUFFALO WAN port.  This removes BUFFALO
   from the ONU-side network.
3. Disconnect the blue cable from BUFFALO LAN and DS57U lower `eth0`.
4. Connect the ONU cable to DS57U lower `eth0`.
5. Connect the blue cable from DS57U upper `eth1` to the **BUFFALO WAN** port.
6. Move the test PC's white cable from DS57U upper `eth1` to a BUFFALO LAN
   port, unless that PC already has an equivalent BUFFALO LAN connection.
7. Wait up to two minutes for Ethernet link, IPv6 RA/DHCPv6, MAP-E creation,
   DS57U DHCP, and the BUFFALO WAN DHCP client.  During this interval the home
   network can be offline.

Only DS57U may be connected to the ONU-side hub at the end of this sequence.

## 6. Acceptance checks

First, from a client behind BUFFALO, confirm all of the following:

```powershell
ipconfig /all
ping.exe -4 -n 4 192.168.11.1
ping.exe -4 -n 4 1.1.1.1
curl.exe --ipv4 --connect-timeout 10 --max-time 20 --silent --show-error https://cloudflare.com/cdn-cgi/trace
```

The client must still have `192.168.11.x/24` and gateway `192.168.11.1`.
IPv4 ping and HTTPS must pass.  Then inspect the BUFFALO WAN status: it must
have the DHCP-reserved address `192.168.1.2`, gateway `192.168.1.1`, and a
link at the expected speed.  From a PC temporarily connected directly to
DS57U LAN, verify the active lease matches exactly:

```sh
uci show dhcp.buffalo_wan
cat /tmp/dhcp.leases
```

The lease must contain MAC `68:e1:dc:37:1d:10` and IP `192.168.1.2`.

For direct-ONU verification, temporarily attach the PC to DS57U `eth1` only
(disconnect its BUFFALO LAN link first), then run the Phase 2 checks over SSH:

```sh
cat /sys/class/net/eth0/carrier
ubus call network.interface.wan status
ubus call network.interface.wan6 status
ubus call network.interface.wan6_4 status
ubus call network.interface.mape_auto status
ip -4 route
ip -6 route
ping -4 -c 4 1.1.1.1
ping -6 -c 4 2606:4700:4700::1111
```

Acceptance requires carrier `1`, a usable direct IPv6 default route, a live
`wan6_4` or guarded `mape_auto` interface and IPv4 default route for MAP-E, and successful IPv4 and
IPv6 pings.  Reconnect the PC to BUFFALO LAN after collecting the results and
record the exact outputs and exit statuses in the replacement history.

## 6.1 Optional route to BUFFALO LAN

To route DS57U traffic to `192.168.11.0/24`, use BUFFALO's reserved WAN
address `192.168.1.2` as the next hop on `lan`. First check `uci changes network`
for unrelated pending changes and back up `/etc/config/network`.

```sh
uci set network.buffalo_lan_route=route
uci set network.buffalo_lan_route.interface='lan'
uci set network.buffalo_lan_route.target='192.168.11.0'
uci set network.buffalo_lan_route.netmask='255.255.255.0'
uci set network.buffalo_lan_route.gateway='192.168.1.2'
uci commit network
/etc/init.d/network reload
uci show network.buffalo_lan_route
ip -4 route get 192.168.11.1
ping -c 3 -W 2 192.168.1.2
ping -c 3 -W 2 192.168.11.1
```

Expected lookup: `192.168.11.1 via 192.168.1.2 dev br-lan src 192.168.1.1`.
Accept only after the committed route appears in the live routing table.
Successful gateway pings establish router reachability; downstream host and
application access still depend on BUFFALO firewall policy and host settings.
Reboot persistence requires a separate runtime check.

To remove this route:

```sh
uci delete network.buffalo_lan_route
uci commit network
/etc/init.d/network reload
```

## 7. Failure handling and rollback

For an IPv6-only regression while IPv4 still works, first restore the
pre-relay OpenWrt DHCP/firewall files and BUFFALO's original IPv6 mode using
the [IPv6 relay plan's rollback](docs/plans/ipv6-relay.md#rollback-not-run).
If the OpenWrt path remains unusable, use the direct-ONU fallback below.
Use the reviewed Phase 2 automation; do not guess MAP-E values or add a
competing static MAP interface.

### 7.1 Prepare the direct-ONU BUFFALO fallback before changing settings

Keep an offline copy of this procedure and the saved router configurations
on the test PC. Recovery must work without Internet access or this chat.
Save BUFFALO's configuration export and screenshots of the Internet and
IPv6 pages. Save OpenWrt's pre-relay `dhcp` and `firewall` files in a unique
backup directory, copy them to ignored local `backups/`, and record the
actual directory and SHA-256 hashes in the execution history.

Identify cables by endpoints; cable colors alone are not reliable:

| Cable | OpenWrt-primary endpoints | Direct-ONU BUFFALO fallback endpoints |
|---|---|---|
| ONU uplink | ONU / ONU-side hub to DS57U lower `eth0` WAN | ONU / ONU-side hub to BUFFALO WAN/Internet |
| Downstream link | DS57U upper `eth1` LAN to BUFFALO WAN | Disconnected initially; optionally BUFFALO LAN to DS57U lower `eth0` WAN after recovery |
| Management link | Test PC directly to DS57U upper `eth1` LAN | Test PC directly to DS57U upper `eth1` LAN |
| Existing client links | BUFFALO LAN/Wi-Fi to clients | Same BUFFALO LAN/Wi-Fi to clients |

Establish the independent wired IPv4 management link and verify SSH/LuCI at
`192.168.1.1` before starting the relay trial. If the PC is currently wired
only through BUFFALO, move that PC link to DS57U `eth1` or its LAN switch;
use a separate BUFFALO Wi-Fi client to keep the admin page accessible at
`192.168.11.1`. Keep the physical ONU powered and the fiber unchanged.

### 7.2 Restore BUFFALO as the direct-ONU Internet router

Target recovery topology:

```text
ONU / ONU-side hub
  |
BUFFALO WAN/Internet
  |
BUFFALO router mode, LAN 192.168.11.1/24
  +-- existing wired clients
  `-- existing Wi-Fi clients

OpenWrt initially isolated from the Internet:
test PC -- DS57U upper eth1 LAN, 192.168.1.1/24
DS57U lower eth0 WAN disconnected
```

1. Open BUFFALO's admin page at `http://192.168.11.1/` from its LAN/Wi-Fi.
   Keep it in **router mode**, with LAN `192.168.11.1/24` and DHCP enabled.
   In **Internet > Internet**, keep/select the IP address acquisition method
   **「インターネット＠スタートを行う」**. In **Internet > IPv6**, select
   **「インターネット＠スタートを行う」** instead of
   **「NDプロキシを使用する」**. Restore the saved bridge-permission checkbox
   state (the original supplied screenshot has
   **「IPv6ブリッジを許可する」 unchecked**), then apply with **「設定」**.
   Wait for the admin page to become available again. Applying this while
   BUFFALO still sits behind OpenWrt is preparation, not proof of recovery.
2. Disconnect the link between **DS57U `eth1` LAN and BUFFALO WAN** at both
   ends. Keep the independent test-PC-to-DS57U-management link connected.
3. Disconnect the ONU uplink from **DS57U lower `eth0` WAN** and connect that
   same ONU uplink to **BUFFALO WAN/Internet**. Use the WAN/Internet port,
   not a BUFFALO LAN port. Leave DS57U WAN disconnected for initial recovery.
4. Leave existing BUFFALO LAN and Wi-Fi clients connected. Allow about two
   minutes for link establishment and automatic line detection, then inspect
   **ステータス > システム**. If automatic detection has not recovered the
   connection, reapply the automatic Internet setting with the ONU uplink
   now connected and inspect the status/log again. Record the result; do not
   assume the two-minute wait is a guaranteed recovery time.
5. Reconnect the phone's Wi-Fi if needed. Confirm an IPv4 address in
   `192.168.11.0/24` with gateway `192.168.11.1`, reach the BUFFALO admin page,
   resolve a hostname, and open HTTPS sites. Disable cellular/VPN/other
   routes during acceptance checks so they cannot mask a failed Wi-Fi path.
6. Record IPv4 and IPv6 separately. For IPv6, require a public address,
   usable default gateway, and an IPv6-only or explicitly IPv6-bound HTTPS
   check. Private `fd...` and link-local `fe80...` addresses alone are not
   IPv6 Internet acceptance. In direct-ONU operation, BUFFALO should detect
   the provider connection rather than continue reporting OpenWrt's
   `192.168.1.2` WAN lease; reacquire actual values, do not enter guessed
   public IPv4/MAP-E settings. MAP-E status may differ from ordinary DHCP.

If the admin page becomes unavailable during preparation, connect a test
device directly to a BUFFALO LAN port, renew its DHCP lease, and use
`192.168.11.1`. Keep the OpenWrt management cable independent. Recovery of
BUFFALO Internet service does not require restoring or reconnecting OpenWrt.

BUFFALO's documented setup/status menus are described in its
[Internet configuration guide](https://www.buffalo.jp/support/faq/detail/124144869.html).
The exact automatic-mode labels above come from the supplied WSR-6000AX8
screenshots. The full fallback after an IPv6 relay trial remains untested;
record its actual outcome when run.

### 7.3 Optionally reconnect OpenWrt behind BUFFALO after Internet recovery

Complete Section 7.2 first. From the independently attached PC, preserve any
failure evidence and restore OpenWrt's saved **pre-relay** DHCP/firewall
configuration using the actual verified backup directory. Reload firewall
and restart odhcpd as described in the relay plan. This avoids leaving WAN6
as a relay master while moving it under the original upstream router.
Recheck IPv4 management access before reconnecting its WAN.

Connect **BUFFALO LAN to DS57U lower `eth0` WAN**. Leave DS57U upper `eth1`
connected to the test PC. This is a routed, subordinate OpenWrt connection;
do not connect BUFFALO LAN to DS57U LAN or retain the former
DS57U-LAN-to-BUFFALO-WAN link.

After DHCP settles, use one persistent SSH session and inspect:

```sh
ubus call network.interface.wan status
ip -4 route
ubus call network.interface.wan6 status
ubus call network.interface.mape_auto status
ping -c 4 192.168.11.1
ping -c 4 1.1.1.1
nslookup example.com
curl -4 -I --max-time 15 https://example.com
```

Expected IPv4 WAN is a newly acquired `192.168.11.x` lease, gateway
`192.168.11.1`; do not assume the previous lease address will return.
Verify the default route actually uses this WAN. A now-absent `mape_auto`
is expected if the guarded cleanup completed. If the generated MAP-E
interface/include persists, follow
[Phase 2: Reverting MAP Settings](phase2-setup.md#reverting-map-settings):
preserve configs, run the reviewed reconcile script after DHCP IPv4 is up,
and verify cleanup. If it fails, leave DS57U WAN disconnected and retain
the working direct-ONU BUFFALO connection while investigating locally.
Return-to-BUFFALO cleanup is an open verification gate, not an assumed pass.

Record date, cable endpoints, exact settings/commands, outputs, exit statuses,
configuration diffs, failures and retests in the replacement history. Treat
BUFFALO client Internet recovery and optional subordinate OpenWrt recovery
as separate outcomes.

Execution evidence: [docs/history/phase2-router-mode-replacement.md](docs/history/phase2-router-mode-replacement.md).
