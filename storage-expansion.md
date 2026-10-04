# DS57U System Partition Expansion

Rebuild manual. Execution evidence: [storage history](docs/history/storage-expansion.md).

## Preconditions and backup

Expand the OpenWrt ext4 root into the unallocated disk tail before installing
the monitoring stack. This changes the boot disk and reboots twice. Keep the
PC on DS57U `eth1` and retain the working BUFFALO upstream path. Have local
console/Live-USB recovery available.

In a persistent SSH session, identify the root and disk:

```sh
cat /proc/cmdline
mount | grep ' on / '
df -h /
cat /proc/partitions
command -v parted resize2fs losetup blkid
umask 077
sysupgrade -b /tmp/storage-before-expand.tar.gz
sha256sum /tmp/storage-before-expand.tar.gz
```

The existing DS57U used SATA `/dev/sda`, final partition `/dev/sda2`, and ext4.
Resolve the root PARTUUID against the actual partition table on each rebuild.
Stop if root is not ext4, not the last partition, or has no contiguous free tail.
Copy the backup to the PC and require a matching SHA-256 before any changes:

```powershell
rtk proxy scp -O -i .local-ssh/id_ed25519_v2 -o BatchMode=yes root@192.168.1.1:/tmp/storage-before-expand.tar.gz backups/
rtk proxy certutil -hashfile backups/storage-before-expand.tar.gz SHA256
```

## Expansion procedure

Use the [OpenWrt x86/ext4 expansion procedure](https://openwrt.org/docs/guide-user/advanced/expand_root).
The retrieval route below is the one used by this build. Inspect the downloaded
helper before sourcing it, and verify its disk selection and reboot behavior.

```sh
apk add parted losetup resize2fs blkid
wget -U '' -O /tmp/expand-root.sh 'https://openwrt.org/_export/code/docs/guide-user/advanced/expand_root?codeblock=3'
sha256sum /tmp/expand-root.sh
sed -n '1,260p' /tmp/expand-root.sh
```

After review:

```sh
. /tmp/expand-root.sh
sed -n '1,240p' /etc/uci-defaults/70-rootpt-resize
sed -n '1,240p' /etc/uci-defaults/80-rootfs-resize
tail -n 4 /etc/sysupgrade.conf
blkid /dev/sda2
parted -s /dev/sda unit s print free
```

Replace device names with those actually verified. Only after confirming the
final ext4 root partition and free tail, run:

```sh
sh /etc/uci-defaults/70-rootpt-resize
```

SSH disconnects during the first reboot. On the next boot, `80-rootfs-resize`
expands ext4 and reboots again. Do not interrupt power; allow both stages to finish.

## Acceptance and recovery

Reconnect and check:

```sh
cat /proc/partitions
df -h /
mount | grep ' on / '
blkid /dev/sda2
ls -l /etc/rootpt-resize /etc/rootfs-resize
ubus call network.interface.wan status
ubus call network.interface.lan status
ping -c 4 192.168.11.1
ping -c 4 1.1.1.1
```

Require both markers, ext4 root close to available disk capacity, correct root
identity, and recovered LAN/WAN. Example capacity from the 128 GB-class SSD
was `117.7G`; another disk need not match it. Record actual results in history.
A failed boot requires local console/Live-USB recovery and the external backup.
A sysupgrade configuration backup is not a whole-disk/package/application-data
backup. Do not attempt a remote whole-disk rewrite as rollback.
