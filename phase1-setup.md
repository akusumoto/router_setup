# Phase 1 Implementation Procedure — Building OpenWrt Basic Functions Under BUFFALO

Rebuild manual. Execution evidence: [Phase 1 history](docs/history/phase1-setup.md).

## 1. Objective of Phase 1

Without stopping the existing home network, install OpenWrt on the Shuttle DS57U and verify that basic routing, management, and observation functions work.

At this stage, **we do not perform actual testing of OCN Virtual Connect / IPv6 IPoE / MAP-E**.
Those will be verified during the WAN direct connection test in Phase 2.

Completion conditions for Phase 1:

- OpenWrt boots from the DS57U's internal storage
- Recognizes the two wired NICs (Intel i211 / i218LM)
- Can identify which physical port corresponds to which Linux interface
- Can connect WAN to BUFFALO's LAN and obtain an IPv4 address via DHCP
- Can distribute addresses via DHCP to the test PC on the LAN side
- Test PC on the LAN side can connect to the IPv4 internet
- DNS is available
- OpenWrt can be managed via SSH / LuCI
- Can observe traffic using nftables / tcpdump / conntrack
- A configuration backup is taken upon completing Phase 1

---

## 2. Phase 1 Network Topology

```text
Internet
   |
NTT / OCN
   |
 ONU
   |
BUFFALO WSR-6000AX8
  LAN: 192.168.11.1/24
   |
   | BUFFALO LAN port
   |
[WAN]
Shuttle DS57U
OpenWrt
[LAN]
   |
Test PC
```

In Phase 1, there will be a double router / double NAT configuration.

```text
Internet
   |
BUFFALO NAT
   |
192.168.11.0/24
   |
OpenWrt NAT
   |
192.168.1.0/24
   |
Test PC
```

OpenWrt's LAN will use the default `192.168.1.1/24`.

Since the BUFFALO side is `192.168.11.0/24`, the networks do not overlap.

---

## 3. Hardware Used

- Shuttle DS57U
- Intel Celeron 3205U
- Intel i211 Gigabit Ethernet
- Intel i218LM Gigabit Ethernet
- Realtek RTL8188EE
  - Not used this time
- RAM: Approx. 8 GB (OpenWrt shows `MemTotal: 8039660 kB`, approx. 7.67 GiB)
- Internal Storage: SanDisk SATA SSD, approx. 119.2 GiB (nominally 128 GB class)
- USB flash drive
- Keyboard / Display
- Test PC
- 2+ LAN cables

Before writing OpenWrt, ensure there is no required data on the internal storage.

---

## 4. OpenWrt Image

We will use the stable release of OpenWrt x86_64.

Since this project will later install the Rust-based router-agent and additional packages, the basic policy is to use the **ext4 combined image**.

If UEFI boot is available in DS57U's BIOS settings:

```text
generic-ext4-combined-efi.img.gz
```

If Legacy BIOS boot is used:

```text
generic-ext4-combined.img.gz
```

Prioritize `combined-efi` if UEFI is available.

For the target part of the filename, choose **`x86-64`**. `x86-legacy` is for older 32-bit PCs and will not be used for the DS57U in this procedure.

### Why choose ext4?

- Easy to expand the root filesystem later
- Easier to make room for Rust binaries and analysis tools

Note:

- Unlike the SquashFS version, the ext4 version lacks the benefits of a read-only root for Factory Reset / Failsafe
- Configuration backups must be stored externally

---

## 5. Installing OpenWrt

### 5.1 Obtain the Image

Download the stable x86/64 image from the official OpenWrt website.

After downloading, confirm that the SHA-256 matches the published hash.

Example:

```bash
sha256sum openwrt-*-x86-64-generic-ext4-combined-efi.img.gz
```

On Windows, use PowerShell:

```powershell
Get-FileHash .\openwrt-*-x86-64-generic-ext4-combined-efi.img.gz -Algorithm SHA256
```

### 5.2 Write to Internal Storage

Use one of the following methods.

#### Method A: Connect internal drive to another PC and write

This is simpler if the SSD/HDD can be removed.

Write the `.img.gz` or extracted `.img` to the target drive using Rufus, balenaEtcher, etc.

#### Method B: Write from Linux Live USB

The following is an example using an Ubuntu Desktop Live USB. **Writing to internal storage will erase existing partitions and data.** Ensure there is no necessary data before writing.

1. Download the [Ubuntu Desktop ISO](https://ubuntu.com/download/desktop) on another PC, and follow the [official Ubuntu guide](https://ubuntu.com/desktop/docs/en/latest/how-to/create-a-bootable-usb-stick/) to write it to a USB drive using Rufus, etc. This erases data on the USB drive.
2. Connect a display, keyboard, and the Live USB to the DS57U. If you want to download the OpenWrt image within the Live environment, connect the DS57U's wired port to the BUFFALO's LAN.
3. Select USB from the DS57U boot menu and start **Try Ubuntu**. Do not install Ubuntu to the internal storage.
4. Verify the boot mode in the terminal. Check DS57U BIOS settings if necessary.

   ```bash
   test -d /sys/firmware/efi && echo UEFI || echo 'Legacy BIOS'
   ```

5. Retrieve the **ext4 combined** image matching the boot mode from the [OpenWrt x86/64 download list](https://downloads.openwrt.org/releases/25.12.5/targets/x86/64/). Below is an example for OpenWrt 25.12.5 UEFI. Saving to `/tmp` is temporary within the Live environment and vanishes upon reboot.

   ```bash
   cd /tmp
   IMAGE=openwrt-25.12.5-x86-64-generic-ext4-combined-efi.img.gz
   curl -fLO "https://downloads.openwrt.org/releases/25.12.5/targets/x86/64/$IMAGE"
   sha256sum "$IMAGE"
   ```

   The SHA-256 for UEFI is `c8ee59ce7b0f635a6b50c1b7307b07ee7785214a6faf2af42280dd4ef4310290`. For Legacy BIOS, change the file to `IMAGE=openwrt-25.12.5-x86-64-generic-ext4-combined.img.gz` and verify with SHA-256 `23e2538e8ab0eb52dfed1c65d608ecdb71ffd432dd54885da138ae67cd9e4461`. **Do not write if they don't match.** If using a different version, align the URL, filename, and published SHA-256.

6. Identify the internal storage device name.

   ```bash
   lsblk -o NAME,SIZE,MODEL,TRAN,TYPE,MOUNTPOINTS
   ```

   Identify the internal storage by capacity and model to distinguish it from the Live USB. The target is the entire disk (e.g., `/dev/sda`, `/dev/nvme0n1`), not a partition (e.g., `/dev/sda1`). **Stop if you cannot identify it.** Unmount any mounted partitions on the target disk before writing.

7. Write to the confirmed internal disk after a file extraction test. Replace `/dev/REPLACE_WITH_INTERNAL_DISK` with the disk name from step 6. Do not blindly assume it's `/dev/sda`.

   ```bash
   gzip -t "$IMAGE"
   set -o pipefail
   gzip -dc "$IMAGE" | sudo dd of=/dev/REPLACE_WITH_INTERNAL_DISK bs=4M status=progress conv=fsync
   sync
   ```

   Do not execute `dd` if `gzip -t` fails. Confirm `dd` completes without errors, shut down, remove the Live USB, and boot from internal storage.

### 5.3 Initial Boot

- Boot from the internal storage where OpenWrt is installed
- Verify the OpenWrt login prompt appears on the console
- If boot fails, check the BIOS UEFI/Legacy setting and the image used


## 6. NIC Recognition Check

Do not assume which Linux interface corresponds to i211 and i218LM at first.

Check the following on the console:

```bash
ip link
```

If necessary:

```bash
ls -l /sys/class/net/
```

Link status can be checked with:

```bash
cat /sys/class/net/<interface>/carrier
```

- `1`: Link up
- `0`: Link down

Plug a LAN cable into only one port, plug/unplug it, and observe which interface changes status.

Add `ethtool` / `pciutils` later if needed to check NIC drivers and PCI info.

Example port mapping for this DS57U (verify again before use):

| Physical port | Interface | NIC | Role |
|---|---|---|---|
| Upper, white cable | `eth1` | Intel i218-LM | LAN / `br-lan` |
| Lower, blue cable | `eth0` | Intel i211 | WAN |

Once verified, record the physical mapping in history and label the chassis.

```text
WAN
LAN
```

**It is not strictly necessary to use i211 for WAN and i218LM for LAN.**
Fix roles after confirming stable recognition on the actual device.

---

## 7. Initial Connection to LAN Side

Do not connect to BUFFALO yet.

```text
DS57U LAN
   |
Test PC
```

Connect the test PC to the intended LAN port.

OpenWrt default LAN address:

```text
192.168.1.1
```

Ensure the test PC gets an address like this via DHCP:

```text
192.168.1.x/24
Gateway: 192.168.1.1
```

Browser:

```text
http://192.168.1.1/
```

SSH:

```bash
ssh -i .local-ssh/id_ed25519_v2 -o IdentitiesOnly=yes root@192.168.1.1
```

After first login, **you must set a root password**.

## 8. WAN Configuration

Next, connect BUFFALO's LAN port to OpenWrt's intended WAN port.

```text
BUFFALO LAN
   |
OpenWrt WAN
```

WAN should be **DHCP Client**.

Expected state:

```text
OpenWrt WAN
IPv4: 192.168.11.x
Gateway: 192.168.11.1
```

Check in LuCI:

```text
Network
  -> Interfaces
     -> WAN
```

Or via CLI:

```bash
ubus call network.interface.wan status
```

Or:

```bash
ip addr
ip route
```

Confirm the default route points towards BUFFALO.

Example:

```text
default via 192.168.11.1 ...
```

## 9. Basic Connectivity Check

### 9.1 From OpenWrt itself to BUFFALO

```bash
ping -c 4 192.168.11.1
```

### 9.2 From OpenWrt itself to IPv4 Internet

```bash
ping -c 4 1.1.1.1
```

### 9.3 DNS

```bash
nslookup openwrt.org
```

### 9.4 Check from Test PC

From the Test PC:

```text
Gateway -> OpenWrt
        -> BUFFALO
        -> Internet
```

Confirm communication flows in this order.

Check points:

- Website browsing
- IPv4 connectivity
- DNS resolution

## 10. DHCP Check

Confirm DHCP is running on OpenWrt's LAN side.

Release/renew address on test PC, and ensure it gets:

```text
IP address : 192.168.1.x
Gateway    : 192.168.1.1
DNS        : via OpenWrt
```

On OpenWrt, check the dnsmasq lease file:

```bash
cat /tmp/dhcp.leases
```

On OpenWrt 25.12.5, `ubus call dhcp ipv4leases` returned `Method not found`. Check available methods via `ubus -v list dhcp`.

## 11. Firewall / NAT Check

Check OpenWrt Firewall rules.

```bash
nft list ruleset
```

In Phase 1, don't proactively alter rules; verify default LAN -> WAN forwarding / masquerading works.

Crucial checks:

- Can communicate from LAN to WAN
- Cannot inadvertently access LuCI from WAN side
- Cannot inadvertently access SSH from WAN side

Verify from another terminal on the BUFFALO side that management interfaces and SSH are not exposed on the OpenWrt WAN address.

## 12. Installing Observation Tools

OpenWrt 25.12+ uses `apk` for package management.

Update package list:

```bash
apk update
```

tcpdump:

```bash
apk add tcpdump
```

conntrack:

```bash
apk add conntrack
```

If necessary:

```bash
apk add ethtool pciutils
```

## 13. tcpdump Check

Use interface names confirmed on the device.

WAN side:

```bash
tcpdump -ni <WAN-interface>
```

LAN side:

```bash
tcpdump -ni <LAN-interface>
```

Specific host only:

```bash
tcpdump -ni <LAN-interface> host 192.168.1.<test-pc>
```

DNS only:

```bash
tcpdump -ni any port 53
```

Access a website on the test PC, and confirm packets are observed on both LAN and WAN sides.

## 14. conntrack Check

```bash
conntrack -L
```

Access a website on the test PC and verify connection entries are generated.

To check count only:

```bash
conntrack -C
```

In Phase 1, it's sufficient to confirm that "LAN device traffic is NAT'd and traceable with conntrack".

## 15. UCI / ubus Check

Retrieve settings:

```bash
uci show network
uci show firewall
uci show dhcp
```

WAN status:

```bash
ubus call network.interface.wan status
```

LAN status:

```bash
ubus call network.interface.lan status
```

Here, we observe the info that the future Rust `router-agent` should fetch.

Implementing `router-agent` is not mandatory in Phase 1.

---

## 16. About IPv6

While IPv6 info might be visible under BUFFALO, in Phase 1 **it is not used to evaluate OCN IPoE / OCN Virtual Connect success**.

It's fine to observe it:

```bash
ip -6 addr
ip -6 route
```

However,

```text
IPv6 communication succeeded under BUFFALO
```

is distinct from

```text
OpenWrt can establish OCN IPv6 IPoE directly connected to ONU
```

The latter will be tested in Phase 2.

## 17. Configuration Backup

Upon completing Phase 1, back up the config.

```bash
sysupgrade -b /tmp/phase1-baseline.tar.gz
```

Copy it to the PC.

```bash
scp -O -i .local-ssh/id_ed25519_v2 root@192.168.1.1:/tmp/phase1-baseline.tar.gz backups/
```

Additionally, save the following for reference:

```bash
uci show > /tmp/phase1-uci.txt
ip addr > /tmp/phase1-ip-addr.txt
ip route > /tmp/phase1-ip-route.txt
ip -6 route > /tmp/phase1-ip6-route.txt
nft list ruleset > /tmp/phase1-nft.txt
```

Copy these to the PC as well.

## 18. Phase 1 Acceptance

For each rebuild, record fresh results for the completion conditions in Section 1, including physical NIC mapping, root authentication, LAN DHCP, WAN DHCP, client IPv4/DNS, WAN management rejection, captures/conntrack, and an externally saved hash-verified backup. Use the history for actual checked boxes.


## 19. What We Don't Do in Phase 1

The following are postponed to Phase 2 or later.

- Directly connecting OpenWrt to ONU
- Actual OCN IPv6 IPoE verification
- OCN Virtual Connect configuration
- Retrieving / calculating MAP-E parameters
- MAP-E port set verification
- Changing BUFFALO to AP mode
- Moving the whole home LAN to OpenWrt
- Configuring from router-agent
- Router operations via MCP

The goal for Phase 1 is that "OpenWrt runs securely as a normal IPv4 router and we can observe its internals."
