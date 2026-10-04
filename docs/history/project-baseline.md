# Project Baseline and Early Decisions

Source: the project notes dated 2026-09-13. These are historical baseline observations and checklist/decision snapshots, not current device proof. Current policy: [router-project.md](../../router-project.md).

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
