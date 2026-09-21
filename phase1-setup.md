# Phase 1 Implementation Procedure — Building OpenWrt Basic Functions Under BUFFALO

Last updated: 2026-09-21

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

For this DS57U, the Live environment booted in Legacy BIOS mode, and **`openwrt-25.12.5-x86-64-generic-ext4-combined.img.gz`** (without `-efi`) was used. The initial boot results are recorded in Section 5.3.

#### 2026-09-21 Re-check (without re-writing)

The following command was run on the image left on the PC:

```powershell
certutil -hashfile binary\openwrt-25.12.5-x86-64-generic-ext4-combined.img.gz SHA256
```

```text
23e2538e8ab0eb52dfed1c65d608ecdb71ffd432dd54885da138ae67cd9e4461
```

This matches the Legacy BIOS SHA-256 above. The current state was re-checked on the router using read-only commands.

```sh
test -d /sys/firmware/efi && echo UEFI || echo 'Legacy BIOS'
cat /etc/openwrt_release
cat /sys/block/sda/device/model
cat /proc/partitions
df -h /
mount | grep ' on / '
```

```text
Legacy BIOS
DISTRIB_RELEASE='25.12.5'
DISTRIB_REVISION='r33051-f5dae5ece4'
DISTRIB_TARGET='x86/64'
DISTRIB_ARCH='x86_64'
SanDisk SDSSDHP1
   8        0  125034840 sda
   8        1      16384 sda1
   8        2     106496 sda2
/dev/root                98.3M     24.2M     72.1M  25% /
/dev/root on / type ext4 (rw,noatime)
```

Excerpts from the output show OpenWrt is running, recognizes internal `/dev/sda`, and root is ext4. Past `dd` standard output wasn't saved, and since we didn't re-write to disk, bytes written and speeds aren't logged.

### 5.3 Initial Boot

- Boot from the internal storage where OpenWrt is installed
- Verify the OpenWrt login prompt appears on the console
- If boot fails, check the BIOS UEFI/Legacy setting and the image used

Console excerpt during actual initial boot (confirmed 2026-09-20):

```text
BusyBox v1.37.0 (2026-06-29 12:59:20 UTC) built-in shell (ash)

  _______                     ________        __
 |       |.-----.-----.-----.|  |  |  |.----.|  |_
 |   -   ||  _  |  -__|     ||  |  |  ||   _||   _|
 |_______||   __|_____|__|__||________||__|  |____|
          |__| W I R E L E S S   F R E E D O M
 -----------------------------------------------------
OpenWrt 25.12.5, r33051-f5dae5ece4 Dave's Guitar

=== WARNING! =============================================
There is no root password defined on this device!
Use the "passwd" command to set up a new password
in order to prevent unauthorized SSH logins.
==========================================================

OpenWrt recently switched to the "apk" package manager!
opkg install <pkg>  -> apk add <pkg>
opkg update         -> apk update

root@OpenWrt:~#
```

This confirms OpenWrt 25.12.5 booted and reached the root shell. Initially, no root password was set, but later checks showed a root password hash in `/etc/shadow` (the hash itself is not recorded).

Output from SSH re-check on 2026-09-21:

```text
# uname -a
Linux OpenWrt 6.12.94 #0 SMP Mon Jun 29 12:59:20 2026 x86_64 GNU/Linux
# grep -m 1 'model name' /proc/cpuinfo
model name      : Intel(R) Celeron(R) 3205U @ 1.50GHz
# grep MemTotal /proc/meminfo
MemTotal:        8039660 kB
```

---

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

Record the results. On 2026-09-21, based on user-provided rear photos, the layout was mapped in ASCII. The orientation has USB ports above Ethernet ports, and the power plug at the bottom.

```text
                 DS57U rear panel
        +----------------------------------+
        |          [USB] [USB]             |
        |                                  |
        |  +-------------+                 |
        |  | upper RJ45  |--- white -----> Test PC
        |  +-------------+                 eth1 / LAN
        |  +-------------+                 |
        |  | lower RJ45  |--- blue ------> BUFFALO LAN
        |  +-------------+                 eth0 / WAN
        |          (power plug)            |
        +----------------------------------+
```

| Rear physical socket | Inserted cable | Connected to | Linux interface | NIC / Role |
|---|---|---|---|---|
| Upper | White | Test PC | `eth1` | Intel i218-LM / LAN (`br-lan`) |
| Lower | Blue | BUFFALO LAN | `eth0` | Intel i211 / WAN |

On 2026-09-21, photos confirmed the white cable in the upper port and blue cable in the lower port. The user confirmed the blue cable goes to BUFFALO and white to the test PC. OpenWrt's `uci show network` shows `network.wan.device='eth0'`, `network.@device[0].ports='eth1'`, and the PC communicated at LAN `192.168.1.239` with WAN at BUFFALO `192.168.11.108`. Physical sockets were mapped from these observations and connections. Cable unplug/plug carrier tests were not performed.

NICs and roles confirmed on device (2026-09-20):

| Linux interface | PCI ID | NIC | Current role |
|---|---|---|---|
| `eth0` | `8086:1539` | Intel i211 | WAN, connected to BUFFALO LAN |
| `eth1` | `8086:15a2` | Intel i218-LM | LAN, member of `br-lan` |

PCI IDs were cross-referenced with Linux [igb](https://github.com/torvalds/linux/blob/master/drivers/net/ethernet/intel/igb/e1000_hw.h) and [e1000e](https://github.com/torvalds/linux/blob/master/drivers/net/ethernet/intel/e1000e/hw.h) definitions. The two physical sockets are arranged vertically, not horizontally.

Read-only re-check on 2026-09-21:

```sh
ip link
for n in eth0 eth1; do
  echo "$n carrier=$(cat /sys/class/net/$n/carrier) mac=$(cat /sys/class/net/$n/address) pci=$(readlink -f /sys/class/net/$n/device) vendor=$(cat /sys/class/net/$n/device/vendor) device=$(cat /sys/class/net/$n/device/device)"
done
uci show network
```

```text
eth0: <BROADCAST,MULTICAST,UP,LOWER_UP>  mac=80:ee:73:ab:4a:f0
eth1: <BROADCAST,MULTICAST,UP,LOWER_UP>  master br-lan  mac=80:ee:73:ab:4a:f1
eth0 carrier=1 pci=.../0000:02:00.0 vendor=0x8086 device=0x1539
eth1 carrier=1 pci=.../0000:00:19.0 vendor=0x8086 device=0x15a2
network.@device[0].name='br-lan'
network.@device[0].ports='eth1'
network.wan.device='eth0'
network.wan.proto='dhcp'
```

Excerpts show link status and roles for both NICs. Upper/lower physical socket positions are recorded in the ASCII diagram and cable destinations above.

Once verified, stick a physical label on the chassis.

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
ssh root@192.168.1.1
```

After first login, **you must set a root password**.

### 2026-09-21 LAN Management Re-check

Excerpt from `ipconfig /all` on the test PC's wired adapter:

```text
DHCP Enabled . . . . . . . . . . . : Yes
IPv4 Address. . . . . . . . . . . . : 192.168.1.239
Subnet Mask . . . . . . . . . . . . : 255.255.255.0
Default Gateway . . . . . . . . . . : 192.168.1.1
DHCP Server . . . . . . . . . . . . : 192.168.1.1
DNS Servers . . . . . . . . . . . . : fd57:3a20:c1d6::1, 192.168.1.1
```

Connected to root shell via `ssh -tt -i .local-ssh/id_ed25519_v2 -o BatchMode=yes -o ConnectTimeout=5 root@192.168.1.1`. The PC also ran `Test-NetConnection -ComputerName 192.168.1.1 -Port 80 -InformationLevel Detailed` and `-Port 443`, both resulting in `SourceAddress: 192.168.1.239`, `TcpTestSucceeded: True`. This shows SSH and LuCI TCP ports are reachable from the LAN.

Without outputting the password value, checked it was set on the router:

```sh
awk -F: '$1=="root" {print ($2 == "" || $2 == "!" || $2 == "*" ? "root password missing or locked" : "root password hash present")}' /etc/shadow
```

```text
root password hash present
```

This re-check just observed existing LAN DHCP leases without plugging/unplugging physical cables.

---

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

### 2026-09-21 WAN Configuration Re-check

```sh
uci show network
ubus call network.interface.wan status
ip -4 addr show dev eth0
ip route
```

```text
network.@device[0].ports='eth1'
network.lan.device='br-lan'
network.lan.ipaddr='192.168.1.1/24'
network.wan.device='eth0'
network.wan.proto='dhcp'
network.wan6.device='eth0'
network.wan6.proto='dhcpv6'

WAN status: "up": true, "l3_device": "eth0", "proto": "dhcp"
WAN ipv4-address: 192.168.11.108/24
WAN route nexthop: 192.168.11.1
WAN dns-server: 192.168.11.1

inet 192.168.11.108/24 brd 192.168.11.255 scope global eth0
default via 192.168.11.1 dev eth0  src 192.168.11.108
192.168.1.0/24 dev br-lan scope link  src 192.168.1.1
192.168.11.0/24 dev eth0 scope link  src 192.168.11.108
```

`ubus` JSON output excerpted. WAN obtained IPv4, gateway, and DNS from BUFFALO via DHCP, while LAN sits on a separate `192.168.1.0/24` network.

---

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

### 2026-09-21 Connectivity Re-check

Ran on router:

```sh
ping -c 4 192.168.11.1
ping -c 4 1.1.1.1
nslookup openwrt.org
```

```text
192.168.11.1: 4 packets transmitted, 4 packets received, 0% packet loss
round-trip min/avg/max = 0.641/0.667/0.710 ms
1.1.1.1: 4 packets transmitted, 4 packets received, 0% packet loss
round-trip min/avg/max = 8.712/9.220/9.953 ms
Server: 127.0.0.1:53
Name: openwrt.org
Address: 64.226.122.113
Address: 2a03:b0c0:3:d0::1a51:c001
```

Ran on test PC specifying the wired LAN address:

```powershell
ping -4 -S 192.168.1.239 -n 2 -w 1000 1.1.1.1
tracert -4 -d -h 3 -w 1000 1.1.1.1
nslookup openwrt.org 192.168.1.1
curl.exe --noproxy * --interface 192.168.1.239 --connect-timeout 5 --max-time 12 -sSI https://openwrt.org/
```

```text
Ping: Sent = 2, Received = 2, Lost = 0; 13-14 ms
tracert hop 1: 192.168.1.1
tracert hop 2: 192.168.11.1
tracert hop 3: 153.128.214.14
nslookup server: OpenWrt.lan (192.168.1.1)
nslookup openwrt.org: 64.226.122.113, 2a03:b0c0:3:d0::1a51:c001
curl: HTTP/1.1 200 OK
```

Necessary lines extracted from long outputs. Because the PC also had Wi-Fi connected, wired addresses were specified in `ping` and `curl`, and the first 2 hops were verified with `tracert`.

---

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

### 2026-09-21 DHCP Re-check

```sh
cat /tmp/dhcp.leases
uci show dhcp.lan
```

```text
1789958349 10:ff:e0:4d:2b:90 192.168.1.239 akirawin11 01:10:ff:e0:4d:2b:90
dhcp.lan.interface='lan'
dhcp.lan.start='100'
dhcp.lan.limit='150'
dhcp.lan.leasetime='12h'
dhcp.lan.dhcpv4='server'
```

Windows `ipconfig /all` showed wired adapter `DHCP Enabled: Yes`, `IPv4 Address: 192.168.1.239`, `Default Gateway: 192.168.1.1`, `DHCP Server: 192.168.1.1`, `DNS Servers: 192.168.1.1`. Leases were cross-referenced from both sides without renewing.

---

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

### 2026-09-21 Firewall / NAT Re-check

```sh
uci show firewall
nft list chain inet fw4 input_wan
nft list chain inet fw4 forward_lan
nft list chain inet fw4 srcnat_wan
```

```text
firewall.@zone[1].name='wan'
firewall.@zone[1].input='REJECT'
firewall.@zone[1].forward='DROP'
firewall.@zone[1].masq='1'
firewall.@forwarding[0].src='lan'
firewall.@forwarding[0].dest='wan'

input_wan: jump reject_from_wan
forward_lan: jump accept_to_wan
srcnat_wan: meta nfproto ipv4 masquerade
```

Outputs excerpted. Standard DHCP and ICMP allowed rules remain on WAN, meaning not all protocols are outright blocked on WAN input.

Executed the following from the test PC's BUFFALO Wi-Fi address `192.168.11.109`:

```powershell
Test-NetConnection -ComputerName 192.168.11.108 -Port 22 -InformationLevel Detailed
Test-NetConnection -ComputerName 192.168.11.108 -Port 80 -InformationLevel Detailed
Test-NetConnection -ComputerName 192.168.11.108 -Port 443 -InformationLevel Detailed
```

All 3 returned `InterfaceAlias: Wi-Fi`, `SourceAddress: 192.168.11.109`, `PingSucceeded: True`, `TcpTestSucceeded: False`. In contrast, OpenWrt LAN address `192.168.1.1` TCP 80/443 showed `TcpTestSucceeded: True` from wired PC `192.168.1.239`, and SSH login succeeded. Confirmed management TCP is rejected on WAN and accessible on LAN.

---

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

### 2026-09-20 Implementation Log

Connected to SSH as `root@192.168.1.1` using `.local-ssh/id_ed25519_v2` and ran commands in the same session. Excerpts omitted `apk add` dependency lines.

```text
# df -h /
Filesystem                Size      Used Available Use% Mounted on
/dev/root                98.3M     22.7M     73.6M  24% /

# apk update
OK: 11238 distinct packages available

# apk add tcpdump conntrack
(7/9) Installing conntrack (1.4.8-r1)
(9/9) Installing tcpdump (4.99.6-r1)
OK: 20.7 MiB in 191 packages

# df -h /
Filesystem                Size      Used Available Use% Mounted on
/dev/root                98.3M     24.2M     72.1M  25% /
```

9 packages including `conntrack` dependencies (like `kmod-nf-conntrack-netlink`) were successfully installed. `ethtool` and `pciutils` were not installed this time.

Re-checked installation on 2026-09-21.

```sh
command -v tcpdump
command -v conntrack
apk info -e tcpdump conntrack
df -h /
```

```text
/usr/bin/tcpdump
/usr/sbin/conntrack
tcpdump
conntrack
/dev/root                98.3M     24.2M     72.1M  25% /
```

---

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

### 2026-09-20 Implementation Log

Sent a HEAD request to `https://openwrt.org/` from the test PC's wired IPv4 address `192.168.1.239`. The same request fixing destination IP to `64.226.122.113` was executed while capturing on LAN and WAN respectively. Both returned `HTTP/1.1 200 OK`. Packets below omit TCP sequence numbers.

```powershell
curl.exe --noproxy * --interface 192.168.1.239 --resolve openwrt.org:443:64.226.122.113 --connect-timeout 5 --max-time 15 -sSI https://openwrt.org/
```

```text
# tcpdump -ni br-lan -c 4 'tcp and host 64.226.122.113 and port 443'
listening on br-lan, link-type EN10MB (Ethernet), snapshot length 262144 bytes
14:56:20.748027 IP 192.168.1.239.50276 > 64.226.122.113.443: Flags [S]
14:56:21.008745 IP 64.226.122.113.443 > 192.168.1.239.50276: Flags [S.]
4 packets captured
0 packets dropped by kernel

# tcpdump -ni eth0 -c 4 'tcp and host 64.226.122.113 and port 443'
listening on eth0, link-type EN10MB (Ethernet), snapshot length 262144 bytes
14:56:39.371633 IP 192.168.11.108.50298 > 64.226.122.113.443: Flags [S]
14:56:39.625188 IP 64.226.122.113.443 > 192.168.11.108.50298: Flags [S.]
4 packets captured
0 packets dropped by kernel
```

Separately, `ping -n 2 -w 1000 1.1.1.1` from test PC replied 2/2. Observed ICMP requests `192.168.1.239 > 1.1.1.1` on `br-lan`, and `192.168.11.108 > 1.1.1.1` on `eth0`. These demonstrate IPv4 NAT from LAN to WAN.

---

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

### 2026-09-20 Implementation Log

```text
# conntrack -L -p icmp
icmp 1 17 src=192.168.1.239 dst=1.1.1.1 type=8 code=0 id=1 packets=4 bytes=240 src=1.1.1.1 dst=192.168.11.108 type=0 code=0 id=1 packets=4 bytes=240 mark=0 use=1
conntrack v1.4.8 (conntrack-tools): 1 flow entries have been shown.

# conntrack -C
62
```

Started `conntrack -E -p tcp -s 192.168.1.239 -o timestamp`, then executed the HTTPS request above on the test PC. Output showed 6 events: `SYN_SENT` → `SYN_RECV` → `ESTABLISHED` → `TIME_WAIT`, confirming source `192.168.1.239:50265`, dest `64.226.122.113:443`, and reply source `192.168.11.108:50265`. Logged `6 flow events have been shown` at the end. The count `62` represents all active connections, not just the test PC.

---

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

### 2026-09-20 Observation Results

Below are excerpts of addresses and routes. Expirations and some `unreachable` routes are omitted.

```text
# ip -6 addr show dev eth0
inet6 2400:4050:cb80:1700:82ee:73ff:feab:4af0/64 scope global dynamic noprefixroute
inet6 fe80::82ee:73ff:feab:4af0/64 scope link

# ip -6 addr show dev br-lan
inet6 fd57:3a20:c1d6::1/60 scope global noprefixroute
inet6 fe80::82ee:73ff:feab:4af1/64 scope link

# ip -6 route
default from 2400:4050:cb80:1700::/64 via fe80::6ae1:dcff:fe37:1d10 dev eth0 metric 512
2400:4050:cb80:1700::/64 dev eth0 metric 256
fd57:3a20:c1d6::/64 dev br-lan metric 1024
```

These show addresses/routes under BUFFALO, and do not prove OCN IPoE works with direct ONU connection.

---

## 17. Configuration Backup

Upon completing Phase 1, back up the config.

```bash
sysupgrade -b /tmp/phase1-baseline.tar.gz
```

Copy it to the PC.

```bash
scp root@192.168.1.1:/tmp/phase1-baseline.tar.gz .
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

### 2026-09-20 Implementation Log

Created backups and ref files on the router.

```bash
sysupgrade -b /tmp/phase1-baseline.tar.gz
uci show > /tmp/phase1-uci.txt
ip addr > /tmp/phase1-ip-addr.txt
ip route > /tmp/phase1-ip-route.txt
ip -6 route > /tmp/phase1-ip6-route.txt
nft list ruleset > /tmp/phase1-nft.txt
sha256sum /tmp/phase1-baseline.tar.gz
```

```text
Sun Sep 20 14:54:40 GMT 2026 upgrade: Saving config files...
/tmp/phase1-baseline.tar.gz: 8497 bytes
SHA-256: dce1e58a40a79eb93c53b1500b616bfd6007987f8992fc04076fee28e715e7bf
```

On the PC, initially tried `scp -i .local-ssh/id_ed25519_v2 -o BatchMode=yes root@192.168.1.1:/tmp/phase1-* backups/` but failed with `ash: /usr/libexec/sftp-server: not found`. Because OpenWrt lacks an SFTP server, used legacy SCP to copy the 6 files.

```powershell
scp -O -i .local-ssh/id_ed25519_v2 -o BatchMode=yes root@192.168.1.1:/tmp/phase1-* backups/
certutil -hashfile backups\phase1-baseline.tar.gz SHA256
tar -tzf backups\phase1-baseline.tar.gz
```

PC's `backups/phase1-baseline.tar.gz` was 8497 bytes, and SHA-256 matched the router. Verified `etc/config/network`, `etc/config/firewall`, `etc/config/dhcp`, `etc/dropbear/authorized_keys`, and `etc/shadow` in the archive. Saved ref files: `phase1-uci.txt` (8147 bytes), `phase1-ip-addr.txt` (1385 bytes), `phase1-ip-route.txt` (167 bytes), `phase1-ip6-route.txt` (371 bytes), `phase1-nft.txt` (5846 bytes). `backups/` is ignored in `.gitignore`. Since the archive holds credentials, contents are not listed here.

Contents of `phase1-ip-route.txt`:

```text
default via 192.168.11.1 dev eth0  src 192.168.11.108
192.168.1.0/24 dev br-lan scope link  src 192.168.1.1
192.168.11.0/24 dev eth0 scope link  src 192.168.11.108
```

---

## 18. Phase 1 Completion Checklist

Results of actual device check on 2026-09-20 and read-only re-check on 2026-09-21:

- OpenWrt 25.12.5 (x86/64, ext4) booted on DS57U. Internal SSD is `/dev/sda` (approx. 119.2 GiB), with root partition at approx. 98.3 MiB. Capacity expansion for future packages or `router-agent` will be reviewed separately.
- `eth0` as WAN fetched `192.168.11.108/24` from BUFFALO via DHCP. Gateway and DNS are `192.168.11.1`. `eth1` belongs to `br-lan`, LAN is `192.168.1.1/24`.
- Test PC fetched `192.168.1.239` via DHCP. Route from PC to `1.1.1.1` goes `192.168.1.1` → `192.168.11.1`. Confirmed IPv4 comms and `openwrt.org` DNS resolution.
- `nft list ruleset` succeeded, confirming WAN input drop and IPv4 masquerade. Confirmed PC address `192.168.11.109` on BUFFALO side could not connect to TCP 22/80/443 on the OpenWrt WAN address.
- Fetched states with `uci show network/firewall/dhcp` and `ubus call network.interface.wan/lan status`. On 2026-09-20 installed `tcpdump` and `conntrack`, verified LAN/WAN HTTPS, ICMP, NAT'd addresses and TCP tracking events.
- Copied backup and 5 ref files to PC's `backups/`, verified SHA-256 and archive contents. On 2026-09-21, logged rear ASCII diagram, upper white cable as `eth1`, and lower blue cable as `eth0`.

As of 2026-09-21, all 20 checklist items are confirmed and logged. Physical label attachment is unconfirmed.

- [x] Confirmed RAM capacity
- [x] Confirmed storage type/capacity
- [x] Wrote OpenWrt x86_64
- [x] OpenWrt booted from internal storage
- [x] Recognized Intel i211
- [x] Recognized Intel i218LM
- [x] Recorded mapping between physical LAN ports and Linux interfaces
- [x] Fixed physical ports for WAN / LAN
- [x] Set root password
- [x] Distributed address to LAN side PC via DHCP
- [x] WAN obtained `192.168.11.x` from BUFFALO
- [x] OpenWrt itself communicated to IPv4 Internet
- [x] Test PC communicated to IPv4 Internet
- [x] DNS name resolution worked
- [x] Confirmed `nft list ruleset`
- [x] Confirmed LuCI / SSH are not open from WAN side
- [x] Observed LAN/WAN traffic with `tcpdump`
- [x] Confirmed LAN device traffic with `conntrack`
- [x] Retrieved state using `uci show` / `ubus`
- [x] Saved Phase 1 backup to PC

---

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
