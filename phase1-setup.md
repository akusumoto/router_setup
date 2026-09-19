# Phase 1 実施手順 — BUFFALO配下でOpenWrt基本機能を構築

更新日: 2026-09-20

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

結果を記録する。

```text
DS57U 物理ポートA -> Linux interface: __________ -> Intel __________
DS57U 物理ポートB -> Linux interface: __________ -> Intel __________
```

実機で確認したNICと役割（2026-09-20）:

| Linuxインターフェース | PCI ID | NIC | 現在の役割 |
|---|---|---|---|
| `eth0` | `8086:1539` | Intel i211 | WAN、BUFFALO LANへ接続 |
| `eth1` | `8086:15a2` | Intel i218-LM | LAN、`br-lan` のメンバー |

PCI IDの型番対応はLinuxの[igb](https://github.com/torvalds/linux/blob/master/drivers/net/ethernet/intel/igb/e1000_hw.h)と[e1000e](https://github.com/torvalds/linux/blob/master/drivers/net/ethernet/intel/e1000e/hw.h)の定義で照合した。筐体の左右どちらの物理ソケットが `eth0` / `eth1` かは、まだ位置を記録していない。

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

---

## 18. Phase 1 完了チェックリスト

2026-09-20の実機確認結果:

- OpenWrt 25.12.5（x86/64、ext4）がDS57Uで起動。内蔵SSDは `/dev/sda`（約119.2 GiB）で、現在のrootパーティションは約98.3 MiB。将来の追加パッケージや `router-agent` に向けた容量拡張は別途検討する。
- `eth0` がWANとしてBUFFALOから `192.168.11.108/24` をDHCP取得。デフォルトゲートウェイとDNSは `192.168.11.1`。`eth1` が `br-lan` に属し、LANは `192.168.1.1/24`。
- テストPCはDHCPで `192.168.1.239` を取得。PCから `1.1.1.1` への経路は `192.168.1.1` → `192.168.11.1` の順で、IPv4疎通と `openwrt.org` のDNS名前解決を確認した。
- `nft list ruleset` が成功し、WAN側の入力拒否とIPv4 masqueradeを確認。BUFFALO側のPCアドレス `192.168.11.109` からOpenWrt WANアドレスのTCP 22/80/443へ接続できないことも確認した。
- `uci show network/firewall/dhcp` と `ubus call network.interface.wan/lan status` で状態を取得。`tcpdump` と `conntrack` のコマンドはまだない。

- [x] RAM容量を確認した
- [x] ストレージ種類・容量を確認した
- [x] OpenWrt x86_64を書き込んだ
- [x] OpenWrtが内蔵ストレージから起動した
- [x] Intel i211を認識した
- [x] Intel i218LMを認識した
- [ ] 物理LANポートとLinuxインターフェースの対応を記録した
- [x] WAN / LANの物理ポートを固定した
- [x] rootパスワードを設定した
- [x] LAN側PCへDHCPでアドレスを配布できた
- [x] WANがBUFFALOから `192.168.11.x` を取得した
- [x] OpenWrt自身からIPv4 Internetへ通信できた
- [x] テストPCからIPv4 Internetへ通信できた
- [x] DNS名前解決が動作した
- [x] `nft list ruleset` を確認した
- [x] WAN側からLuCI / SSHが開いていないことを確認した
- [ ] `tcpdump` でLAN/WAN通信を観測した
- [ ] `conntrack` でLAN端末の通信を確認した
- [x] `uci show` / `ubus` で状態を取得した
- [ ] Phase 1バックアップをPCへ保存した

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
