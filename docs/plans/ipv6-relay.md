# Proposed IPv6 relay configuration

Status: OpenWrt settings applied on 2026-10-14. Direct-LAN and BUFFALO-LAN
PC IPv4/IPv6 HTTPS passed. BUFFALO automatic mode selected ND proxy without
a manual setting change. The phone's supplied test reports IPv4 only;
phone acceptance and the cause of that failure remain unresolved.
Execution evidence: [OpenWrt relay update](../history/phase2-setup.md#2026-10-14-jst---apply-openwrt-ipv6-relay-buffalo-change-pending).

Purpose: carry the upstream public SLAAC /64 to downstream clients while
keeping router-mode BUFFALO and the existing IPv4/MAP-E topology.

## Proposed settings

| Device/interface | Setting |
|---|---|
| OpenWrt WAN6 DHCP service section | RA relay; DHCPv6 relay; NDP relay; master=1 |
| OpenWrt LAN DHCP service section | RA relay; DHCPv6 relay; NDP relay |
| OpenWrt WAN firewall | Allow IPv6 UDP server/relay replies from source port 547 to local destination port 547 |
| BUFFALO Internet > IPv6 | Automatic mode may remain if status shows NDプロキシ; select NDプロキシを使用する explicitly only if automatic mode does not select it |

[odhcpd configuration](https://github.com/openwrt/odhcpd/blob/master/README.md)
documents relaying on uplinks without delegated prefixes.
[BUFFALO ND proxy instructions](https://www.buffalo.jp/support/faq/detail/16428.html)
confirm the router-mode IPv6 menu and option. The supplied WSR-6000AX8
firmware 1.15 screenshot confirms that this option exists on this device.

The upstream /64 remains an RA prefix, not a newly delegated LAN range.
NDP proxy route learning is required for return traffic. The additional
BUFFALO proxy boundary is untested. IPv6 bridge is a fallback to evaluate
only if ND proxy fails with evidence; it is not the initial proposed mode.

Retain the working IPv4 DHCP service, BUFFALO reservation 192.168.1.2,
BUFFALO LAN 192.168.11.1/24, OpenWrt LAN 192.168.1.1/24, network.wan6 settings,
network.lan.ip6assign=60, and existing MAP-E rules. The server-only RA flags
can remain stored; the proposed RA service forwards upstream advertisements.
No guessed public prefix, forced ra_default, NAT66, AP mode, or Ethernet
LAN-to-LAN connection is part of this proposal.

## Preconditions before applying

- Verify the live state again and ensure uci changes is empty.
- Use an independent wired IPv4 management connection to OpenWrt.
- Save BUFFALO's current settings/export; original IPv6 mode is
  インターネット＠スタートを行う with IPv6ブリッジを許可する unchecked.
- Save complete /etc/config/dhcp and /etc/config/firewall to a unique backup
  directory, copy them to ignored local backups, and record hashes.
- Confirm proposed dhcp.wan6 and firewall.Allow_DHCPv6_Relay names still
  do not exist before creating them.
- Record commands and outputs in docs/history/phase2-setup.md as executed.

## OpenWrt UCI changes (applied)

Execute on OpenWrt in the persistent SSH session after the backup above:

```sh
uci set dhcp.wan6='dhcp'
uci set dhcp.wan6.interface='wan6'
uci set dhcp.wan6.ignore='1'
uci set dhcp.wan6.master='1'
uci set dhcp.wan6.ra='relay'
uci set dhcp.wan6.dhcpv6='relay'
uci set dhcp.wan6.ndp='relay'

uci set dhcp.lan.ra='relay'
uci set dhcp.lan.dhcpv6='relay'
uci set dhcp.lan.ndp='relay'

uci set firewall.Allow_DHCPv6_Relay='rule'
uci set firewall.Allow_DHCPv6_Relay.name='Allow-DHCPv6-Relay'
uci set firewall.Allow_DHCPv6_Relay.src='wan'
uci set firewall.Allow_DHCPv6_Relay.proto='udp'
uci set firewall.Allow_DHCPv6_Relay.src_port='547'
uci set firewall.Allow_DHCPv6_Relay.dest_port='547'
uci set firewall.Allow_DHCPv6_Relay.family='ipv6'
uci set firewall.Allow_DHCPv6_Relay.target='ACCEPT'

uci changes
fw4 check
```

The WAN6 ignore option prevents dnsmasq from offering IPv4 DHCP on WAN.
Explicit IPv6 relay modes enable odhcpd there; master selects the upstream
relay interface. DHCPv6 relay listens on the server port, distinct from the
existing odhcp6c client listener on port 546. Upstream support for relayed
DHCPv6 information requests still requires live validation.

If review and fw4 check succeed, commit the two affected packages, reload
the firewall, and restart only odhcpd:

```sh
uci commit dhcp
uci commit firewall
/etc/init.d/firewall reload
/etc/init.d/odhcpd restart
```

Do not restart network/wan6 just to apply these service settings.
Then inspect BUFFALO status. If automatic mode already reports NDプロキシ,
retain it and test downstream clients. Otherwise select
NDプロキシを使用する and apply.
Capture logs and behavior around each step.

## Acceptance checks

Observed after the OpenWrt update: WAN6/MAP-E remained up, network config
unchanged, DNS and router IPv4/IPv6 HTTPS passed. A PC directly on OpenWrt
LAN received a public IPv6 address and default gateway; explicitly source-bound
IPv4 and IPv6 HTTPS both returned 200. LAN capture showed the public /64
with SLAAC enabled and router lifetime 1800 seconds. Subsequently a PC on
BUFFALO LAN also passed source-bound IPv4/IPv6 HTTPS; captures showed NDP
proxy responses and bidirectional IPv6 traffic. The phone acquired public
addresses but its supplied test-ipv6.com screenshot reports 0/10 and IPv4
only. Its IPv6 gateway/DNS path and phone/browser behavior remain to be
verified. PC success does not satisfy phone acceptance; the checks below
remain the full acceptance criteria.

- OpenWrt: wan6 and mape_auto remain up; IPv4 default still map-mape_auto.
- LAN capture: public /64 advertised with SLAAC enabled and nonzero
  router lifetime; NDP neighbor discovery and learned /128 routes function.
- BUFFALO: public IPv6 address/range and usable IPv6 default gateway.
- Phone after reconnecting Wi-Fi: public IPv6 address in the upstream /64,
  IPv6 default gateway present; private fd57 addresses alone do not pass.
- Test from a BUFFALO client with cellular/VPN/other network paths disabled:
  IPv4 HTTPS, IPv6 HTTPS, DNS, and gateway access. Force each IP family on
  a test PC rather than treating a dual-stack site's success as IPv6 proof.
- Check permitted return traffic and rejection of unsolicited inbound
  IPv6 TCP; ICMPv6 allowances alone do not constitute a failed firewall.
- Device/runtime result through both proxies is required before promoting
  this proposal into the rebuild manual.

## Rollback (not run)

Saved pre-change files on OpenWrt:
`/root/ipv6-relay-20261014.ddnGFC/{dhcp,firewall,network}`.
Matching local files: `backups/2026-10-14-ipv6-relay/` (ignored).
The five-minute rollback safeguard was disarmed with `keep-settings` after
OpenWrt checks passed; it did not restore settings. For this specific run,
manual rollback from a persistent SSH session is:

```sh
sh /root/ipv6-relay-20261014.ddnGFC/rollback.sh /root/ipv6-relay-20261014.ddnGFC
```

The saved script restores DHCP/firewall, reloads firewall, restarts odhcpd,
and records statuses in `rollback.log`. It has not been executed. Recheck
the backup files before use and restore BUFFALO's original IPv6 mode if
it has since been changed.

For complete recovery using BUFFALO directly on the ONU, follow
[Direct-ONU BUFFALO fallback](../../phase2-router-mode-replacement.md#71-prepare-the-direct-onu-buffalo-fallback-before-changing-settings).
Save that procedure offline before the trial. It covers automatic Internet
settings, cable moves, BUFFALO client checks, independent OpenWrt management,
and optional reconnection of OpenWrt behind BUFFALO after recovery.

Restore the saved dhcp/firewall files from the actual backup directory,
then reload firewall and restart odhcpd. Record that directory and exact
commands when the backup is created; do not substitute an unverified path.
If changes have not been committed, uci revert dhcp and uci revert firewall
discard them. Restore BUFFALO's original automatic IPv6 mode with bridge
permission unchecked. Reconnect the phone's Wi-Fi and recheck IPv4.
