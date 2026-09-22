# DS57U System Partition Expansion

Last updated: 2026-09-23  
Status: **Completed successfully on 2026-09-23 JST. `/dev/sda2` and its mounted ext4 filesystem now use the available internal SSD capacity; LAN/WAN connectivity recovered after the documented two reboots.**

## Objective

Expand the DS57U OpenWrt ext4 root partition to consume the unallocated space on its internal SSD. This work affects the boot disk and requires two reboots; it is separate from Phase 2 MAP-E testing and Phase 3 monitoring.

## Verified Starting State

The following read-only inspection ran on 2026-09-22 `16:30:03+00:00` (2026-09-23 JST) through the normal topology `ONU -> BUFFALO -> DS57U eth0`, with the PC connected through `eth1`:

```sh
cat /proc/cmdline
mount | grep ' on / '
df -h /
cat /proc/partitions
ls -l /dev/sda /dev/sda1 /dev/sda2
command -v fdisk parted sfdisk resize2fs losetup
```

Relevant results:

```text
BOOT_IMAGE=/boot/vmlinuz root=PARTUUID=682d2ae8-02 rootwait ...
/dev/root on / type ext4 (rw,noatime)
/dev/root  98.3M total  25.0M used  71.3M available
sda   125034840 KiB  (approximately 119.2 GiB)
sda1      16384 KiB
sda2     106496 KiB
```

The root partition is therefore `sda2`, selected by `PARTUUID=682d2ae8-02`, and it is the final currently listed partition on the 119.2 GiB SATA disk. The installed image is the x86 ext4 layout, so enlarging `sda2` into the remaining unallocated tail does not require moving another partition. `fdisk`, `parted`, `sfdisk`, and `resize2fs` were absent at inspection; `blkid` and `losetup` package metadata is available.

## Controlled Procedure

Follow the current OpenWrt x86/ext4 root-expansion procedure: install `parted`, `losetup`, `resize2fs`, and `blkid`; retrieve and inspect the official `expand-root.sh`; source it to create the two UCI-default scripts; then invoke `70-rootpt-resize`. The first script expands the last root partition and reboots. On the next boot, `80-rootfs-resize` grows ext4 and reboots again.

Before any package or partition change, create a new `sysupgrade` backup, copy it with `scp -O`, and require a matching SHA-256 on the PC. The PC must remain cabled to `eth1`; the normal path can take several minutes to return after each reboot. Do not interrupt either reboot or power off the DS57U.

After each reboot, verify SSH access, `cat /proc/partitions`, `df -h /`, the root mount, `block info` or `blkid`, `ubus call network.interface.wan status`, `ubus call network.interface.lan status`, and IPv4 reachability through the existing BUFFALO path. The completion condition is a root filesystem close to the available disk size, normal LAN/WAN recovery, and both resize marker files present.

## Risk and Recovery

The action changes the partition table of the boot disk and reboots twice. A failed boot requires local console/Live-USB recovery and restoration from the verified backup; do not attempt to rewrite the whole disk remotely. Since the root is on SATA `/dev/sda` rather than NVMe, the NVMe-specific warning in the OpenWrt procedure does not apply.

## Execution Log

### 2026-09-23 — Read-only verification

No package, partition, filesystem, service, network configuration, or reboot action was performed in this initial inspection. `block` and `fdisk` commands were absent; this confirmed that the supported toolchain had to be installed before the procedure could run.

### 2026-09-23 — Expansion (executed)

The normal topology remained `ONU -> BUFFALO -> DS57U eth0`, with the PC attached through `eth1`. No direct-ONU/MAP-E test occurred. The pre-change router time was `2026-09-22T16:31:30+00:00` (2026-09-23 JST). The official OpenWrt x86/ext4 expansion procedure was used: [Expanding root partition and filesystem](https://openwrt.org/docs/guide-user/advanced/expand_root).

The following commands were run in a single persistent SSH session, in the stated order. Each exited `0` unless otherwise specified:

```sh
umask 077
sysupgrade -b /tmp/storage-before-expand.tar.gz; echo BACKUP_EXIT=$?
sha256sum /tmp/storage-before-expand.tar.gz
apk add parted losetup resize2fs blkid; echo APK_ADD_EXIT=$?
df -h /
wget -U '' -O /tmp/expand-root.sh 'https://openwrt.org/_export/code/docs/guide-user/advanced/expand_root?codeblock=3'; echo WGET_EXIT=$?
sha256sum /tmp/expand-root.sh
sed -n '1,260p' /tmp/expand-root.sh
. /tmp/expand-root.sh; echo SOURCE_EXIT=$?
sed -n '1,240p' /etc/uci-defaults/70-rootpt-resize
sed -n '1,240p' /etc/uci-defaults/80-rootfs-resize
tail -n 4 /etc/sysupgrade.conf
blkid /dev/sda2
parted -s /dev/sda unit s print free
sh /etc/uci-defaults/70-rootpt-resize
```

The backup command returned `BACKUP_EXIT=0` with SHA-256 `55329de40e53a7473e34534410ff005ae27cba4ff5bebf087adc8170ac31c116`. It was copied before package installation with the following PC commands, and `certutil` produced the same hash:

```powershell
scp -O -i .local-ssh/id_ed25519_v2 -o IdentitiesOnly=yes -o BatchMode=yes root@192.168.1.1:/tmp/storage-before-expand.tar.gz backups/
certutil -hashfile backups\storage-before-expand.tar.gz SHA256
```

`backups/storage-before-expand.tar.gz` is intentionally untracked because it can contain credentials.

`apk add` installed `blkid-2.41.5-r1`, `losetup-2.41.5-r1`, `parted-3.6-r2`, `resize2fs-1.47.3-r1`, and their dependencies. The pre-expansion root then had `69.7M` free. The downloaded official script had SHA-256 `4ac1431a833c37e0a8f298f9d50eeeddf35ec0b8513a296892ec6ad6a9d93aba`; it was reviewed before sourcing. It created `70-rootpt-resize`, `80-rootfs-resize`, and the two matching `/etc/sysupgrade.conf` entries.

Immediately before the resize, the dynamically resolved root mapping was `/dev/sda2`; `blkid` confirmed ext4 `PARTUUID="682d2ae8-02"`. `parted` reported an MBR disk with `sda2` at sectors `33792s`–`246783s` and a contiguous free tail `246784s`–`250069679s`. This matches the completion precondition: root was the final partition and no partition movement was needed.

Running `70-rootpt-resize` closed SSH as expected because it changed the root partition then rebooted. SSH did not accept connections during the first two reconnect attempts. It returned after the two scripted reboot stages; at the final check, `/proc/uptime` was `60.13` seconds and both marker files existed:

```text
/etc/rootpt-resize
/etc/rootfs-resize
```

Post-reboot verification commands and results:

```sh
parted -s /dev/sda unit s print free
df -h /
mount | grep ' on / '
blkid /dev/sda2
ubus call network.interface.wan status
ubus call network.interface.lan status
ip route
ping -c 4 192.168.11.1
ping -c 4 1.1.1.1
ping -6 -c 4 2606:4700:4700::1111
uci changes
```

```text
Partition 2: 33792s–250069679s (250035888s), ext4
/dev/root on / type ext4 (rw,noatime)
/dev/root  117.7G total  26.6M used  117.7G available  0% used
PARTUUID=682d2ae8-02 (unchanged)
wan: up, eth0, 192.168.11.108/24, default via 192.168.11.1
lan: up, br-lan, 192.168.1.1/24
192.168.11.1: 4/4 replies, 0% loss, 0.548/0.581/0.640 ms
1.1.1.1: 4/4 replies, 0% loss, 5.855/6.334/7.004 ms
2606:4700:4700::1111: 4/4 replies, 0% loss, 6.337/7.967/8.667 ms
uci changes: no output
```

| Step | Result | Verdict |
|---|---|---|
| Disk/root mapping | `/dev/sda2`, ext4 root, final partition | Pass |
| Free tail | Partition 2 expanded through sector `250069679` | Pass |
| Backup | Router/PC SHA-256 matched before the change | Pass |
| Root filesystem | 98.3 MiB to 117.7 GiB | Pass |
| Reboots and markers | Both scripted stages completed; both markers present | Pass |
| Network recovery | LAN, BUFFALO gateway, IPv4, and IPv6 checks passed | Pass |

### 2026-09-23 — Duplicate `/boot` display diagnosis (read-only)

After expansion, `df -h` showed `/dev/sda1` twice at `/boot`. Read-only inspection at router time `2026-09-22T16:41:07+00:00` showed that this is not a second boot partition or duplicated data:

```text
/proc/mounts:
/dev/sda1 /boot ext4 rw,noatime 0 0
/dev/sda1 /boot ext4 rw,noatime 0 0

/proc/self/mountinfo:
20 13 8:1 /     /boot rw,noatime - ext4 /dev/sda1 rw
21 20 8:1 /boot /boot rw,noatime - ext4 /dev/sda1 rw
```

Both entries are device `8:1` (`/dev/sda1`). Mount ID 21 has parent 20 and source root `/boot`, which means the already mounted `/boot` was mounted again onto the same target. `/etc/fstab` contains only its comment header and `uci show fstab` returned `Entry not found`, excluding a persistent fstab/UCI duplicate rule. The likely cause is the official expansion helper's `mount_root done` call in each of its two reboot-stage scripts. The duplicate consumes no additional disk space and does not mean an additional partition exists. No unmount was performed; a single reboot will normally reconstruct the mount table cleanly, while removing the top mount manually is a separate, unnecessary live-state change.
