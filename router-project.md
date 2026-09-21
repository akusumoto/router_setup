# Custom Router Setup Technical Notes

Last updated: 2026-09-13

## 1. Objective

Turn a small PC with 2 LAN ports into a router, log in directly to the router, and build an environment where the following can be done:

- Monitor network status
- Capture and analyze packets
- Observe routing, Firewall, and NAT
- Add monitoring and analysis functions via custom programs

Currently using **NTT FLET'S + OCN**, with a BUFFALO WSR-6000AX8 acting as the router. The connection method is **OCN Virtual Connect**, utilizing IPv6 IPoE and IPv4 over IPv6.

## 2. Current Network

```text
NTT FLET'S / OCN
        |
      ONU
        |
BUFFALO WSR-6000AX8
        |
    Home LAN
```

Confirmed information:

| Item | Details |
|---|---|
| Router | BUFFALO WSR-6000AX8 |
| Connection Method | OCN Virtual Connect |
| IPv6 | IPoE |
| IPv4 | IPv4 over IPv6 |
| LAN | 192.168.11.0/24, Router 192.168.11.1 |

On the BUFFALO status screen, the IPv4 address `153.243.46.0` and multiple usable port ranges such as `1392-1407`, `2416-2431`, `3440-3455` are displayed.

These can be used as expected values for verification when configuring MAP-E on the custom router.

## 3. Technology Stack

Currently, **OpenWrt x86_64** is the primary candidate.

| Area | Technology | Policy |
|---|---|---|
| Router OS | OpenWrt x86_64 | Primary candidate |
| Firewall / NAT | nftables | Directly observe/control standard Linux mechanisms |
| IPv6 | OCN IPv6 IPoE | Direct WAN connection for early verification |
| IPv4 | OCN Virtual Connect / MAP-E | Highest technical risk. Requires real-device testing |
| CLI | SSH / iproute2 | Direct login to the router |
| Packet capture | tcpdump / libpcap | Initial analysis methods |
| Connection monitoring | conntrack / vnStat | Monitor connections/traffic |
| Custom backend | Rust | Primary candidate for custom router-agent / API / MCP implementation |
| Frontend | React / TypeScript | Candidate for custom monitoring Web UI |
| Metrics | Prometheus compatible + Grafana | To be added in later phases |
| IDS | Suricata | Future candidate |


## 3.1 Expected Hardware

Use **Shuttle DS57U** as the custom router PC.

Confirmed specs:

| Item | Details | Policy |
|---|---|---|
| Model | Shuttle DS57U | Adopted |
| CPU | Intel Celeron 3205U / 2 Cores / 1.5GHz | Expected to be sufficient for OpenWrt, routing, and monitoring |
| Wired LAN 1 | Intel i211 Gigabit Ethernet | WAN candidate |
| Wired LAN 2 | Intel i218LM Gigabit Ethernet | LAN candidate |
| Wireless LAN | Realtek RTL8188EE | Will not be used this time |
| RAM | Unconfirmed | To be confirmed |
| Storage | Unconfirmed | To be confirmed |

Since both wired LAN ports are Intel NICs, they are expected to be suitable for OpenWrt/Linux.

The wireless LAN (Realtek RTL8188EE) is an older 2.4GHz Wi-Fi adapter and will not be used in this project. The plan is to use the existing BUFFALO router in AP mode for Wi-Fi.

Expected final topology:

```text
ONU
  |
Intel NIC 1 (WAN)
  |
Shuttle DS57U / OpenWrt
  |
Intel NIC 2 (LAN)
  |
Switch
  |
  +-- Wired Devices
  +-- BUFFALO (AP mode)
          |
        Wi-Fi
```

## 4. Reasons for choosing OpenWrt

- Has all the necessary foundations for a router (WAN/LAN, DHCP, DNS, Firewall, NAT, IPv6, etc.).
- Being Linux-based, allows SSH login and direct use of `ip`, `nft`, `tcpdump`, `conntrack`, etc.
- Can be used on x86_64 mini PCs.
- Has a `map` package that handles MAP-E.
- Can run custom programs.
- Easy to add custom monitoring UIs and packet analysis functions in the future.

## 5. Custom Programs on OpenWrt

Custom programs can be executed on OpenWrt.

However, standard Linux binaries (for Ubuntu/Debian) do not always work out-of-the-box. Since OpenWrt is a lightweight environment utilizing `musl libc`, the general approach is to **cross-compile for the target architecture using the OpenWrt SDK / toolchain**.

```text
Dev PC
  |-- Rust / C++ / C / Go, etc.
  |-- OpenWrt SDK / toolchain
  |
  +--> Build for OpenWrt x86_64
             |
             +--> SCP or package
                       |
                       v
                 Custom OpenWrt Router
```

**Rust** is the primary candidate for implementing the custom `router-agent`.

The future architecture is envisioned as follows:

```text
Browser / AI / Codex
        |
        +-- React / TypeScript
        +-- MCP client
        |
REST API / WebSocket / MCP
        |
Rust router-agent
        |
        +-- UCI
        +-- ubus
        +-- Netlink
        +-- /proc
        +-- /sys
        +-- nftables
        +-- conntrack
        +-- libpcap
```

Packet analysis will start with `tcpdump` / `libpcap`. The following will also be considered as needed:

- AF_PACKET
- Netfilter / NFQUEUE
- eBPF


### router-agent / MCP Policy

The `router-agent` will not be off-the-shelf software, but a management agent newly implemented for OpenWrt in this project. The implementation language will be **Rust**.

In the initial stage, it will start as read-only, prioritizing safe retrieval of router status by AI. In the future, MCP server functions will be added, allowing AI/Codex to diagnose and operate the router using structured Tools.

Examples of expected read-only Tools:

- `get_wan_status`
- `get_ipv6_status`
- `get_mape_status`
- `get_routes`
- `get_connections`
- `get_firewall_rules`
- `get_interface_stats`

Architecture image:

```text
AI / Codex
    |
   MCP
    |
Rust router-agent
    |
    +-- UCI       : OpenWrt configuration
    +-- ubus      : OpenWrt current status / service operations
    +-- Netlink   : Linux network info
    +-- nftables  : Firewall / NAT
    +-- libpcap   : Packet capture / analysis
```

Configuration-changing Tools will be added gradually later. Instead of granting root shell access directly to AI, only permitted operations will be provided via the `router-agent`. For configuration changes, the design aims to support verification, backup, application, connectivity checks, and rollback on failure.

Reasons for adopting Rust:

- Can prioritize memory safety as a resident daemon.
- Works well with low-level processes like Netlink, libpcap, nftables.
- Suitable for asynchronous I/O and API server implementation.
- Easy to distribute as a single binary for OpenWrt x86_64.
- Highly compatible with future evolutions like eBPF.

## 6. Testing Behind BUFFALO

Initial configuration:

```text
ONU
 |
BUFFALO
 |
Custom OpenWrt
 |
Test LAN
```

What can be confirmed in this state:

- OpenWrt boot
- NIC recognition
- WAN / LAN
- DHCP
- DNS
- NAT
- nftables
- SSH
- tcpdump
- conntrack
- Custom monitoring programs

### Limitations

When placed behind the BUFFALO router, OpenWrt's WAN will be the BUFFALO's LAN, not the OCN line.

Therefore, the following cannot be tested as in production:

- IPv6 IPoE connection by OpenWrt itself
- IPv6 info retrieval from OCN
- OCN Virtual Connect
- MAP-E parameter retrieval/calculation
- IPv4 over IPv6
- Operation of port sets allocated by MAP-E

These require **direct WAN connection testing**.

## 7. OCN Virtual Connect / MAP-E Research Results

OpenWrt has a `map` package that handles MAP-E / MAP-T / Lightweight 4over6, and it supports x86_64.

Additionally, there are actual examples of using OCN Virtual Connect with OpenWrt, so feasibility is high.

However,

> OpenWrt supports MAP-E = It will work perfectly with standard OCN settings

is not necessarily true.

The following MAP-E information must be correctly retrieved, calculated, and configured for OCN:

- IPv4 address
- IPv6 prefix
- BR address
- EA bits
- PSID
- Usable port sets

Furthermore, in Japanese MAP-E environments, there are implementation examples where the standard OpenWrt `map.sh` processing needs adjustment.

Therefore, the main verification point for this project is not just being able to access IPv4 websites, but **confirming whether multiple allocated port ranges are correctly used by NAT**.

## 8. Recommended Testing Procedure

### Phase 1 - Behind BUFFALO

Build the basic OpenWrt functions without stopping the home network.

Items to confirm:

- OpenWrt boot
- NIC recognition
- WAN / LAN
- DHCP
- DNS
- NAT
- nftables
- SSH
- tcpdump

### Phase 2A - Direct WAN Connection / IPv6 IPoE

Temporarily bypass the BUFFALO router.

```text
ONU
 |
OpenWrt
 |
Test PC
```

Do not configure MAP-E yet; confirm IPv6 only.

```bash
ip -6 addr
ip -6 route
```

Items to confirm:

- IPv6 address acquisition
- IPv6 prefix
- IPv6 default route
- IPv6 internet communication

### Phase 2B - MAP-E Parameters

Retrieve and calculate MAP-E parameters for OCN using the acquired IPv6 information.

```text
IPv6 prefix
      |
      v
MAP-E parameters
      |
      +-- IPv4 address
      +-- BR address
      +-- EA bits
      +-- PSID
      +-- port set
```

Verify against values confirmed on the BUFFALO router.

Expected examples:

```text
IPv4 address
153.243.46.0

Port sets
1392-1407
2416-2431
3440-3455
...
```

### Phase 2C - IPv4 over IPv6

Enable MAP-E.

```text
LAN Device
  |
 IPv4
  |
OpenWrt
  |
 NAT
  |
MAP-E
  |
IPv4 in IPv6
  |
 OCN
  |
IPv4 Internet
```

Confirm that IPv4 internet communication is established.

### Phase 2D - Port Set Verification

Just being able to access a website is not enough.

Verify that multiple allocated port ranges are actually usable with NAT.

### Phase 3 - Monitoring

Gradually add the following:

- conntrack
- vnStat
- Custom Rust router-agent
- Prometheus compatible metrics
- Grafana
- Flow analysis like ntopng

### Phase 4 - Advanced

Add the following as needed:

- VLAN
- IoT network isolation
- Guest Wi-Fi isolation
- Server VLAN
- Suricata
- eBPF

## 9. Command Candidates for Direct WAN Connection Testing

```bash
ip addr
ip route
ip -6 addr
ip -6 route

# Monitor traffic on interface
tcpdump -i <WAN interface>

# Firewall / NAT
nft list ruleset

# Connection tracking
conntrack -L
```

## 10. Risk Assessment

| Item | Risk | Mitigation |
|---|---|---|
| OpenWrt x86_64 | Low | Pre-check NIC compatibility of the mini PC |
| IPv6 IPoE | Low-Med | Early verification via direct WAN connection |
| OCN MAP-E | Med | Most important. Real-device testing down to parameters/port sets |
| Home internet downtime | Med | Short tests with the ability to quickly revert to BUFFALO |
| Custom monitoring | Low | Isolate from routing base and implement gradually |

## 11. TODO

- [x] Check mini PC model/CPU (Shuttle DS57U / Intel Celeron 3205U)
- [ ] Check mini PC RAM capacity
- [x] Check manufacturer/chip model of the 2 LAN NICs (Intel i211 / Intel i218LM)
- [ ] Check mini PC storage type/capacity
- [ ] Check OpenWrt x86_64 image/driver compatibility with DS57U (Intel i211 / i218LM)
- [ ] Perform early direct WAN connection testing with OCN after basic OpenWrt configuration

## 12. Current Decision

**Proceed with OpenWrt x86_64 as the primary candidate.**

The biggest uncertainty is **OCN Virtual Connect (MAP-E)**.

Therefore, before building all router features, perform direct WAN connection testing in this order to confirm feasibility early on:

1. IPv6 IPoE
2. MAP-E parameters
3. IPv4 over IPv6
4. Port sets

After establishing an OCN connection on OpenWrt, gradually add the custom Rust `router-agent`, Web UI, MCP, and packet analysis/visualization features.

## References

- OpenWrt: https://openwrt.org/
- OpenWrt map package: https://openwrt.org/packages/pkgdata/map
- OCN Support: https://support.ocn.ne.jp/
- OpenWrt Japanese IPoE / MAP-E implementation examples: https://github.com/fakemanhk/openwrt-jp-ipoe
