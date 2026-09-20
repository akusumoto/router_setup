# Phase 1 実施手順 — BUFFALO配下でOpenWrt基本機能を構築

更新日: 2026-09-21

## 1. Phase 1 の目的

家庭の既存ネットワークを止めずに、Shuttle DS57UへOpenWrtを導入し、基本的なルーター機能と管理・観測機能が動作することを確認する。

この段階では **OCNバーチャルコネクト / IPv6 IPoE / MAP-Eの本番動作確認は行わない**。
それらはPhase 2のWAN直結試験で確認する。

Phase 1 の完了条件:

- OpenWrtがDS57Uの内蔵ストレージから起動する
- Intel i211 / i218LM の2つの有線NICを認識する
- どちらの物理ポートがどのLinuxインターフェースか特定できる
- WANをBUFFALOのLANへ接続してIPv4 DHCPでアドレスを取得できる
- LAN側テストPCへDHCPでアドレスを配布できる
- LAN側PCからIPv4インターネットへ接続できる
- DNSが利用できる
- SSH / LuCIからOpenWrtを管理できる
- nftables / tcpdump / conntrackで通信を観測できる
- Phase 1完了時点の設定バックアップを取得する

---

## 2. Phase 1 のネットワーク構成

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
   | BUFFALO LANポート
   |
[WAN]
Shuttle DS57U
OpenWrt
[LAN]
   |
テスト用PC
```

Phase 1では二重ルーター / 二重NATになる。

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

OpenWrtのLANは、初期状態の `192.168.1.1/24` をそのまま利用する。

BUFFALO側が `192.168.11.0/24` のため、ネットワークは重複しない。

---

## 3. 使用ハードウェア

- Shuttle DS57U
- Intel Celeron 3205U
- Intel i211 Gigabit Ethernet
- Intel i218LM Gigabit Ethernet
- Realtek RTL8188EE
  - 今回は使用しない
- RAM: 約8 GB（OpenWrtの `MemTotal: 8039660 kB`、約7.67 GiB）
- 内蔵ストレージ: SanDisk SATA SSD、約119.2 GiB（公称128 GB級）
- USBメモリ
- キーボード / ディスプレイ
- テスト用PC
- LANケーブル 2本以上

OpenWrtを書き込む前に、内蔵ストレージ上の必要なデータがないことを必ず確認する。

---

## 4. OpenWrtイメージ

OpenWrt x86_64 の安定版を使用する。

このプロジェクトでは、Rust製router-agentや追加パッケージを後から導入するため、基本方針として **ext4 combined image** を使用する。

DS57UのBIOS設定でUEFI起動を利用できる場合:

```text
generic-ext4-combined-efi.img.gz
```

Legacy BIOS起動を利用する場合:

```text
generic-ext4-combined.img.gz
```

UEFIが利用できるなら `combined-efi` を優先する。

ファイル名のターゲット部分は **`x86-64`** を選ぶ。`x86-legacy` は古い32-bit PC向けであり、この手順のDS57U用イメージとして使わない。

### ext4を選ぶ理由

- root filesystemを後から拡張しやすい
- Rustバイナリや解析ツールを追加する余地を作りやすい

注意:

- ext4版はSquashFS版と異なり、read-only rootを利用したFactory Reset / Failsafeの利点がない
- 設定バックアップを必ず外部へ保存する

---

## 5. OpenWrtのインストール

### 5.1 イメージを取得

OpenWrt公式サイトからx86/64の安定版イメージを取得する。

ダウンロード後、公開されているSHA-256と一致することを確認する。

例:

```bash
sha256sum openwrt-*-x86-64-generic-ext4-combined-efi.img.gz
```

Windowsの場合はPowerShellで:

```powershell
Get-FileHash .\openwrt-*-x86-64-generic-ext4-combined-efi.img.gz -Algorithm SHA256
```

### 5.2 内蔵ストレージへ書き込む

方法は以下のどちらか。

#### 方法A: 内蔵ドライブを別PCへ接続して書き込む

SSD/HDDを取り外せる場合はこちらが単純。

Rufus、balenaEtcher等で `.img.gz` または展開した `.img` を対象ドライブへ書き込む。

#### 方法B: Linux Live USBから書き込む

以下はUbuntu DesktopのLive USBを使う例。**内蔵ストレージへの書き込みは既存のパーティションとデータを消去する。** 書き込み前に必要なデータがないことを確認する。

1. 別のPCで[Ubuntu DesktopのISO](https://ubuntu.com/download/desktop)をダウンロードし、[Ubuntu公式の手順](https://ubuntu.com/desktop/docs/en/latest/how-to/create-a-bootable-usb-stick/)に従ってRufusなどでUSBメモリへ書き込む。この操作でUSBメモリ上のデータは消える。
2. DS57Uへディスプレイ、キーボード、Live USBを接続する。OpenWrtイメージをLive環境でダウンロードするなら、DS57Uの有線ポートをBUFFALOのLANへ接続しておく。
3. DS57Uの起動メニューからUSBを選び、Ubuntuの **Try Ubuntu** を起動する。Ubuntuを内蔵ストレージへインストールしない。
4. ターミナルで起動方式を確認する。必要ならDS57UのBIOS設定も確認する。

   ```bash
   test -d /sys/firmware/efi && echo UEFI || echo 'Legacy BIOS'
   ```

5. OpenWrt公式の[x86/64ダウンロード一覧](https://downloads.openwrt.org/releases/25.12.5/targets/x86/64/)から、起動方式に合う **ext4 combined** イメージを取得する。以下はOpenWrt 25.12.5のUEFI用の例。`/tmp` への保存はLive環境内の一時保存であり、再起動すると消える。

   ```bash
   cd /tmp
   IMAGE=openwrt-25.12.5-x86-64-generic-ext4-combined-efi.img.gz
   curl -fLO "https://downloads.openwrt.org/releases/25.12.5/targets/x86/64/$IMAGE"
   sha256sum "$IMAGE"
   ```

   UEFI用のSHA-256は `c8ee59ce7b0f635a6b50c1b7307b07ee7785214a6faf2af42280dd4ef4310290`。Legacy BIOS用は `IMAGE=openwrt-25.12.5-x86-64-generic-ext4-combined.img.gz` に変更して取得し、SHA-256 `23e2538e8ab0eb52dfed1c65d608ecdb71ffd432dd54885da138ae67cd9e4461` と照合する。**一致しなければ書き込まない。** 別のバージョンを使う場合は、URL、ファイル名、公開SHA-256を同じバージョンで揃える。

6. 内蔵ストレージのデバイス名を確認する。

   ```bash
   lsblk -o NAME,SIZE,MODEL,TRAN,TYPE,MOUNTPOINTS
   ```

   容量とモデル名で内蔵ストレージを特定し、Live USBと区別する。対象はディスク全体（例: `/dev/sda`、`/dev/nvme0n1`）であり、パーティション（例: `/dev/sda1`）ではない。**特定できなければ作業を止める。** 対象ディスクのパーティションがマウントされている場合は、書き込み前にアンマウントする。

7. ファイルの展開テスト後、確認した内蔵ディスクへ書き込む。`/dev/REPLACE_WITH_INTERNAL_DISK` は、手順6で確認したディスク名に置き換える。`/dev/sda` と決め打ちしない。

   ```bash
   gzip -t "$IMAGE"
   set -o pipefail
   gzip -dc "$IMAGE" | sudo dd of=/dev/REPLACE_WITH_INTERNAL_DISK bs=4M status=progress conv=fsync
   sync
   ```

   `gzip -t` に失敗した場合は `dd` を実行しない。`dd` の完了とエラーがないことを確認してからシャットダウンし、Live USBを抜いて内蔵ストレージから起動する。

今回のDS57UではLive環境がLegacy BIOSモードで起動し、OpenWrtの書き込みには **`openwrt-25.12.5-x86-64-generic-ext4-combined.img.gz`**（`-efi` なし）を使用した。初回起動の結果は次の5.3節に記録する。

#### 2026-09-21 再確認（書き込みの再実行なし）

PCに残っている使用イメージについて、次のコマンドを実行した。

```powershell
certutil -hashfile binary\openwrt-25.12.5-x86-64-generic-ext4-combined.img.gz SHA256
```

```text
23e2538e8ab0eb52dfed1c65d608ecdb71ffd432dd54885da138ae67cd9e4461
```

これは上記のLegacy BIOS用SHA-256と一致する。ルーターでは読み取り専用のコマンドで現在の状態を再確認した。

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

出力は該当行の抜粋。現在OpenWrtが起動し、内蔵 `/dev/sda` を認識し、rootがext4であることを確認した。過去の `dd` 標準出力は保存されておらず、ディスクの書き込みを再実行していないため、書き込みバイト数や当時の速度は追記しない。

### 5.3 初回起動

- OpenWrtを書き込んだ内蔵ストレージから起動
- コンソールにOpenWrtのログインプロンプトが出ることを確認
- 起動失敗時はBIOSのUEFI / Legacy設定と使用イメージを確認

実機の初回起動時に表示されたコンソールの抜粋（2026-09-20確認）:

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

この表示でOpenWrt 25.12.5の起動とrootシェルへの到達を確認できた。初回表示ではrootパスワード未設定だったが、その後の確認では `/etc/shadow` にrootのパスワードハッシュが存在した（ハッシュ自体は記録しない）。

2026-09-21にSSHで再確認した出力:

```text
# uname -a
Linux OpenWrt 6.12.94 #0 SMP Mon Jun 29 12:59:20 2026 x86_64 GNU/Linux
# grep -m 1 'model name' /proc/cpuinfo
model name      : Intel(R) Celeron(R) 3205U @ 1.50GHz
# grep MemTotal /proc/meminfo
MemTotal:        8039660 kB
```

---

## 6. NIC認識確認

最初は、i211とi218LMがどのLinuxインターフェース名に対応するかを決め打ちしない。

コンソールで以下を確認する。

```bash
ip link
```

必要に応じて:

```bash
ls -l /sys/class/net/
```

リンク状態は以下で確認できる。

```bash
cat /sys/class/net/<interface>/carrier
```

- `1`: Link up
- `0`: Link down

LANケーブルを片方のポートだけに挿し、抜き差ししながらどのインターフェースの状態が変わるか確認する。

必要なら後から `ethtool` / `pciutils` を追加してNICドライバやPCI情報も確認する。

結果を記録する。2026-09-21にユーザー提供の背面写真で確認した配置をASCII図にした。図はUSB端子がEthernet端子の上、電源プラグが下に見える向き。

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

| 背面の物理ソケット | 挿さっているケーブル | 接続先 | Linuxインターフェース | NIC / 役割 |
|---|---|---|---|---|
| 上側 | 白 | テストPC | `eth1` | Intel i218-LM / LAN（`br-lan`） |
| 下側 | 青 | BUFFALOのLAN | `eth0` | Intel i211 / WAN |

2026-09-21、提供された写真で白ケーブルが上側、青ケーブルが下側に挿さっていることを確認した。ユーザーが青ケーブルはBUFFALO、白ケーブルはテストPCへ接続していると確認した。OpenWrtの `uci show network` は `network.wan.device='eth0'`、`network.@device[0].ports='eth1'` を示し、PCはLAN側 `192.168.1.239`、WANはBUFFALO側 `192.168.11.108` で通信できた。この観察と接続先の確認から物理ソケットを対応付けた。ケーブルの抜き差しによるcarrier変化試験は実施していない。

実機で確認したNICと役割（2026-09-20）:

| Linuxインターフェース | PCI ID | NIC | 現在の役割 |
|---|---|---|---|
| `eth0` | `8086:1539` | Intel i211 | WAN、BUFFALO LANへ接続 |
| `eth1` | `8086:15a2` | Intel i218-LM | LAN、`br-lan` のメンバー |

PCI IDの型番対応はLinuxの[igb](https://github.com/torvalds/linux/blob/master/drivers/net/ethernet/intel/igb/e1000_hw.h)と[e1000e](https://github.com/torvalds/linux/blob/master/drivers/net/ethernet/intel/e1000e/hw.h)の定義で照合した。図の向きでは2つの物理ソケットは左右ではなく上下に並んでいる。

2026-09-21の読み取り専用の再確認:

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

出力は確認対象の抜粋。両NICのリンクと設定上の役割を確認した。物理ソケットの上下位置は上記のASCII図とケーブル接続先で記録した。

確認後、筐体へ物理ラベルを貼る。

```text
WAN
LAN
```

**i211を必ずWAN、i218LMを必ずLANにする必要はない。**
実機で安定して認識することを確認した上で役割を固定する。

---

## 7. LAN側への初回接続

まずBUFFALOとは接続しない。

```text
DS57U LAN
   |
Test PC
```

テストPCをLAN予定ポートへ接続する。

OpenWrtの初期LANアドレス:

```text
192.168.1.1
```

テストPCがDHCPで以下のようなアドレスを取得することを確認する。

```text
192.168.1.x/24
Gateway: 192.168.1.1
```

ブラウザ:

```text
http://192.168.1.1/
```

SSH:

```bash
ssh root@192.168.1.1
```

初回ログイン後、**rootパスワードを必ず設定する**。

### 2026-09-21 LAN管理の再確認

テストPCの有線アダプターで `ipconfig /all` を実行した該当行:

```text
DHCP Enabled . . . . . . . . . . . : Yes
IPv4 Address. . . . . . . . . . . . : 192.168.1.239
Subnet Mask . . . . . . . . . . . . : 255.255.255.0
Default Gateway . . . . . . . . . . : 192.168.1.1
DHCP Server . . . . . . . . . . . . : 192.168.1.1
DNS Servers . . . . . . . . . . . . : fd57:3a20:c1d6::1, 192.168.1.1
```

PCから `.local-ssh/id_ed25519_v2` を使った `ssh -tt -i .local-ssh/id_ed25519_v2 -o BatchMode=yes -o ConnectTimeout=5 root@192.168.1.1` でrootシェルへ接続した。さらにPCで `Test-NetConnection -ComputerName 192.168.1.1 -Port 80 -InformationLevel Detailed` と `-Port 443` を実行し、両方とも `SourceAddress: 192.168.1.239`、`TcpTestSucceeded: True` だった。これはLAN側からSSHとLuCIのTCPポートへ到達できることを示す。

ルーターではパスワード値を出力せず、次のコマンドで設定済みであることだけ確認した。

```sh
awk -F: '$1=="root" {print ($2 == "" || $2 == "!" || $2 == "*" ? "root password missing or locked" : "root password hash present")}' /etc/shadow
```

```text
root password hash present
```

この再確認では物理ケーブルを抜き差しせず、LAN側の既存DHCPリースを観察した。

---

## 8. WANの設定

次にBUFFALOのLANポートとOpenWrtのWAN予定ポートを接続する。

```text
BUFFALO LAN
   |
OpenWrt WAN
```

WANは **DHCP Client** とする。

期待する状態:

```text
OpenWrt WAN
IPv4: 192.168.11.x
Gateway: 192.168.11.1
```

LuCIでは以下を確認する。

```text
Network
  -> Interfaces
     -> WAN
```

CLIでは:

```bash
ubus call network.interface.wan status
```

または:

```bash
ip addr
ip route
```

デフォルトルートがBUFFALO側へ向いていることを確認する。

例:

```text
default via 192.168.11.1 ...
```

### 2026-09-21 WAN設定の再確認

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

`ubus` のJSONは項目を抜粋して表示した。WANがBUFFALOからDHCPでIPv4アドレス、ゲートウェイ、DNSを取得しており、LANは別の `192.168.1.0/24` である。

---

## 9. 基本疎通確認

### 9.1 OpenWrt自身からBUFFALOへ

```bash
ping -c 4 192.168.11.1
```

### 9.2 OpenWrt自身からIPv4 Internetへ

```bash
ping -c 4 1.1.1.1
```

### 9.3 DNS

```bash
nslookup openwrt.org
```

### 9.4 テストPCから確認

テストPCから:

```text
Gateway -> OpenWrt
        -> BUFFALO
        -> Internet
```

の順に通信できることを確認する。

確認項目:

- Webサイト閲覧
- IPv4疎通
- DNS名前解決

### 2026-09-21 疎通の再確認

ルーターで実行:

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

テストPCで有線LANのアドレスを指定して実行:

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

上記は長い出力から判定に必要な行を抜粋した。PCにはWi-Fiも接続されているため、`ping` と `curl` で有線アドレスを明示し、`tracert` の先頭2ホップも確認した。

---

## 10. DHCP確認

OpenWrt LAN側でDHCPが動作していることを確認する。

テストPCで一度アドレスを再取得し、

```text
IP address : 192.168.1.x
Gateway    : 192.168.1.1
DNS        : OpenWrt経由
```

となることを確認する。

OpenWrt側ではdnsmasqのリースファイルを確認する。

```bash
cat /tmp/dhcp.leases
```

OpenWrt 25.12.5の実機では `ubus call dhcp ipv4leases` は `Method not found` となった。利用可能な`dhcp`メソッドは `ubus -v list dhcp` で確認できる。

### 2026-09-21 DHCPの再確認

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

Windowsの `ipconfig /all` では有線アダプターの `DHCP Enabled: Yes`、`IPv4 Address: 192.168.1.239`、`Default Gateway: 192.168.1.1`、`DHCP Server: 192.168.1.1`、`DNS Servers: 192.168.1.1` を確認した。リースを再取得する操作は実施せず、現在のリースを両側から照合した。

---

## 11. Firewall / NAT確認

OpenWrtのFirewallルールを確認する。

```bash
nft list ruleset
```

Phase 1ではルールを積極的に変更せず、まずデフォルトのLAN -> WAN転送 / masqueradingが動くことを確認する。

重要な確認:

- LANからWANへ通信できる
- WAN側からLuCIへ不用意にアクセスできない
- WAN側からSSHへ不用意にアクセスできない

BUFFALO側の別端末からOpenWrt WANアドレスに対して管理画面やSSHが開いていないことも確認する。

### 2026-09-21 Firewall / NATの再確認

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

`nft` と `uci` の出力は判定に必要な行を抜粋した。WAN側の標準的なDHCP、ICMPなどの許可ルールは残っており、WAN入力が全プロトコルで一律に遮断されるという意味ではない。

テストPCのBUFFALO側Wi-Fiアドレス `192.168.11.109` から、以下をそれぞれ実行した。

```powershell
Test-NetConnection -ComputerName 192.168.11.108 -Port 22 -InformationLevel Detailed
Test-NetConnection -ComputerName 192.168.11.108 -Port 80 -InformationLevel Detailed
Test-NetConnection -ComputerName 192.168.11.108 -Port 443 -InformationLevel Detailed
```

3回とも `InterfaceAlias: Wi-Fi`、`SourceAddress: 192.168.11.109`、`PingSucceeded: True`、`TcpTestSucceeded: False` だった。対照として、OpenWrt LANアドレス `192.168.1.1` のTCP 80/443は有線PC `192.168.1.239` から `TcpTestSucceeded: True` で、SSHログインも成功した。WAN側の管理用TCP接続が拒否され、LAN側では管理できることを確認した。

---

## 12. 観測ツールの導入

OpenWrt 25.12以降はパッケージ管理に `apk` を利用する。

パッケージ一覧更新:

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

必要に応じて:

```bash
apk add ethtool pciutils
```

### 2026-09-20 実施記録

SSHは `.local-ssh/id_ed25519_v2` で `root@192.168.1.1` に接続し、以下のルーターコマンドを同じセッションで実行した。出力は要点の抜粋で、`apk add` の依存パッケージの行は省略した。

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

`conntrack` の依存パッケージ（`kmod-nf-conntrack-netlink` など）を含め計9パッケージが正常に導入された。`ethtool` と `pciutils` は今回導入していない。

2026-09-21に導入状態を再確認した。

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

## 13. tcpdump確認

インターフェース名は実機で確認したものを使用する。

WAN側:

```bash
tcpdump -ni <WAN-interface>
```

LAN側:

```bash
tcpdump -ni <LAN-interface>
```

特定ホストのみ:

```bash
tcpdump -ni <LAN-interface> host 192.168.1.<test-pc>
```

DNSだけ:

```bash
tcpdump -ni any port 53
```

テストPCでWebアクセスし、LAN側とWAN側の両方でパケットが観測できることを確認する。

### 2026-09-20 実施記録

テストPCの有線IPv4アドレス `192.168.1.239` を指定して `https://openwrt.org/` にHEADリクエストを送った。送信先IPを `64.226.122.113` に固定した同じリクエストを、LAN側とWAN側でそれぞれキャプチャ中に実行した。どちらも `HTTP/1.1 200 OK` だった。以下のパケット出力はTCPシーケンス番号などを省いた抜粋。

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

別途、テストPCから `ping -n 2 -w 1000 1.1.1.1` を実行すると2/2応答した。`br-lan` では `192.168.1.239 > 1.1.1.1`、`eth0` では `192.168.11.108 > 1.1.1.1` のICMP要求を観測した。これらはLANからWANへのIPv4アドレス変換も示す。

---

## 14. conntrack確認

```bash
conntrack -L
```

テストPCからWebアクセスし、接続エントリが生成されることを確認する。

件数のみ確認する場合:

```bash
conntrack -C
```

Phase 1では「LAN端末の通信がNATされ、conntrackで追える」ことが確認できればよい。

### 2026-09-20 実施記録

```text
# conntrack -L -p icmp
icmp 1 17 src=192.168.1.239 dst=1.1.1.1 type=8 code=0 id=1 packets=4 bytes=240 src=1.1.1.1 dst=192.168.11.108 type=0 code=0 id=1 packets=4 bytes=240 mark=0 use=1
conntrack v1.4.8 (conntrack-tools): 1 flow entries have been shown.

# conntrack -C
62
```

`conntrack -E -p tcp -s 192.168.1.239 -o timestamp` を起動してからテストPCで上記HTTPSリクエストを実行した。出力には `SYN_SENT` → `SYN_RECV` → `ESTABLISHED` → `TIME_WAIT` の6イベントがあり、接続時の送信元 `192.168.1.239:50265`、宛先 `64.226.122.113:443`、返答先 `192.168.11.108:50265` を確認した。実行終了時の表示は `6 flow events have been shown`。件数 `62` はその時点の全接続数であり、テストPCだけの件数ではない。

---

## 15. UCI / ubus確認

設定取得:

```bash
uci show network
uci show firewall
uci show dhcp
```

WAN状態:

```bash
ubus call network.interface.wan status
```

LAN状態:

```bash
ubus call network.interface.lan status
```

ここで、将来のRust `router-agent` が取得すべき情報を実際に観察しておく。

Phase 1では `router-agent` の実装は必須としない。

---

## 16. IPv6について

BUFFALO配下でもIPv6情報が見える可能性はあるが、Phase 1では **OCN IPoE / OCNバーチャルコネクトの成功判定には使用しない**。

観察目的で以下を確認するのはよい。

```bash
ip -6 addr
ip -6 route
```

ただし、

```text
BUFFALO配下でIPv6通信できた
```

ことと、

```text
OpenWrtがONU直結でOCN IPv6 IPoEを正常に確立できる
```

ことは別である。

後者はPhase 2で検証する。

### 2026-09-20 観察結果

以下はアドレスと経路の抜粋。アドレスの有効期限と一部の `unreachable` 経路は省略した。

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

この出力はBUFFALO配下で観測したアドレスと経路であり、ONU直結時のOCN IPoE動作を示すものではない。

---

## 17. 設定バックアップ

Phase 1が正常に完了したら設定をバックアップする。

```bash
sysupgrade -b /tmp/phase1-baseline.tar.gz
```

PCへコピーする。

```bash
scp root@192.168.1.1:/tmp/phase1-baseline.tar.gz .
```

さらに、確認用として以下も保存しておく。

```bash
uci show > /tmp/phase1-uci.txt
ip addr > /tmp/phase1-ip-addr.txt
ip route > /tmp/phase1-ip-route.txt
ip -6 route > /tmp/phase1-ip6-route.txt
nft list ruleset > /tmp/phase1-nft.txt
```

これらもPC側へコピーする。

### 2026-09-20 実施記録

ルーターでバックアップと確認用ファイルを作成した。

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

PC側では `scp -i .local-ssh/id_ed25519_v2 -o BatchMode=yes root@192.168.1.1:/tmp/phase1-* backups/` を最初に試したが、`ash: /usr/libexec/sftp-server: not found` で失敗した。OpenWrtにSFTPサーバーがないため、次の従来方式SCPで6ファイルをコピーした。

```powershell
scp -O -i .local-ssh/id_ed25519_v2 -o BatchMode=yes root@192.168.1.1:/tmp/phase1-* backups/
certutil -hashfile backups\phase1-baseline.tar.gz SHA256
tar -tzf backups\phase1-baseline.tar.gz
```

PC上の `backups/phase1-baseline.tar.gz` は8497 bytesで、SHA-256はルーター側と一致した。アーカイブの一覧に `etc/config/network`、`etc/config/firewall`、`etc/config/dhcp`、`etc/dropbear/authorized_keys`、`etc/shadow` を確認した。保存した確認用ファイルは `phase1-uci.txt` (8147 bytes)、`phase1-ip-addr.txt` (1385 bytes)、`phase1-ip-route.txt` (167 bytes)、`phase1-ip6-route.txt` (371 bytes)、`phase1-nft.txt` (5846 bytes)。`backups/` は `.gitignore` で除外される。アーカイブには認証情報が含まれるため、内容は本文に記載しない。

`phase1-ip-route.txt` の内容:

```text
default via 192.168.11.1 dev eth0  src 192.168.11.108
192.168.1.0/24 dev br-lan scope link  src 192.168.1.1
192.168.11.0/24 dev eth0 scope link  src 192.168.11.108
```

---

## 18. Phase 1 完了チェックリスト

2026-09-20の実機確認結果と2026-09-21の読み取り専用の再確認:

- OpenWrt 25.12.5（x86/64、ext4）がDS57Uで起動。内蔵SSDは `/dev/sda`（約119.2 GiB）で、現在のrootパーティションは約98.3 MiB。将来の追加パッケージや `router-agent` に向けた容量拡張は別途検討する。
- `eth0` がWANとしてBUFFALOから `192.168.11.108/24` をDHCP取得。デフォルトゲートウェイとDNSは `192.168.11.1`。`eth1` が `br-lan` に属し、LANは `192.168.1.1/24`。
- テストPCはDHCPで `192.168.1.239` を取得。PCから `1.1.1.1` への経路は `192.168.1.1` → `192.168.11.1` の順で、IPv4疎通と `openwrt.org` のDNS名前解決を確認した。
- `nft list ruleset` が成功し、WAN側の入力拒否とIPv4 masqueradeを確認。BUFFALO側のPCアドレス `192.168.11.109` からOpenWrt WANアドレスのTCP 22/80/443へ接続できないことも確認した。
- `uci show network/firewall/dhcp` と `ubus call network.interface.wan/lan status` で状態を取得。2026-09-20に `tcpdump` と `conntrack` を導入し、LAN/WANのHTTPS通信、ICMP通信、NAT後のアドレスとTCP追跡イベントを確認した。
- 設定バックアップと5つの確認用ファイルをPCの `backups/` へコピーし、バックアップのSHA-256とアーカイブ内容を確認した。2026-09-21に背面配置をASCII図で記録し、上側の白いLANケーブルを `eth1`、下側の青いWANケーブルを `eth0` と記録した。

2026-09-21時点でチェックリスト20項目すべてを確認・記録した。物理ラベルの貼付は未確認。

- [x] RAM容量を確認した
- [x] ストレージ種類・容量を確認した
- [x] OpenWrt x86_64を書き込んだ
- [x] OpenWrtが内蔵ストレージから起動した
- [x] Intel i211を認識した
- [x] Intel i218LMを認識した
- [x] 物理LANポートとLinuxインターフェースの対応を記録した
- [x] WAN / LANの物理ポートを固定した
- [x] rootパスワードを設定した
- [x] LAN側PCへDHCPでアドレスを配布できた
- [x] WANがBUFFALOから `192.168.11.x` を取得した
- [x] OpenWrt自身からIPv4 Internetへ通信できた
- [x] テストPCからIPv4 Internetへ通信できた
- [x] DNS名前解決が動作した
- [x] `nft list ruleset` を確認した
- [x] WAN側からLuCI / SSHが開いていないことを確認した
- [x] `tcpdump` でLAN/WAN通信を観測した
- [x] `conntrack` でLAN端末の通信を確認した
- [x] `uci show` / `ubus` で状態を取得した
- [x] Phase 1バックアップをPCへ保存した

---

## 19. Phase 1 ではやらないこと

以下はPhase 2以降へ回す。

- ONUへOpenWrtを直接接続
- OCN IPv6 IPoEの本番確認
- OCNバーチャルコネクト設定
- MAP-Eパラメータ取得 / 計算
- MAP-Eポートセット検証
- BUFFALOのAPモード化
- 家庭LAN全体のOpenWrtへの移行
- router-agentからの設定変更
- MCPによるルーター操作

Phase 1では「OpenWrtが普通のIPv4ルーターとして安全に動き、内部を観測できる」状態をゴールとする。
