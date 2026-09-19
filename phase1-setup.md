# Phase 1 実施手順 — BUFFALO配下でOpenWrt基本機能を構築

更新日: 2026-09-14

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
- USBメモリ
- キーボード / ディスプレイ
- テスト用PC
- LANケーブル 2本以上

未確認:

- RAM容量
- 内蔵ストレージ種類・容量

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

DS57UをLinux Live USBで起動し、OpenWrtイメージを内蔵ドライブへ `dd` で書き込む。

**対象デバイス名を間違えると別ドライブを消去するため要注意。**

例:

```bash
lsblk
```

対象が `/dev/sda` であることを確認した場合のみ:

```bash
gunzip -c openwrt-*-x86-64-generic-ext4-combined-efi.img.gz \
  | sudo dd of=/dev/sda bs=4M status=progress conv=fsync
```

`/dev/sda` は例であり、実機で必ず確認する。

### 5.3 初回起動

- OpenWrtを書き込んだ内蔵ストレージから起動
- コンソールにOpenWrtのログインプロンプトが出ることを確認
- 起動失敗時はBIOSのUEFI / Legacy設定と使用イメージを確認

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

OpenWrt側では:

```bash
ubus call dhcp ipv4leases
```

環境によっては以下でも確認する。

```bash
cat /tmp/dhcp.leases
```

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

- [ ] RAM容量を確認した
- [ ] ストレージ種類・容量を確認した
- [ ] OpenWrt x86_64を書き込んだ
- [ ] OpenWrtが内蔵ストレージから起動した
- [ ] Intel i211を認識した
- [ ] Intel i218LMを認識した
- [ ] 物理LANポートとLinuxインターフェースの対応を記録した
- [ ] WAN / LANの物理ポートを固定した
- [ ] rootパスワードを設定した
- [ ] LAN側PCへDHCPでアドレスを配布できた
- [ ] WANがBUFFALOから `192.168.11.x` を取得した
- [ ] OpenWrt自身からIPv4 Internetへ通信できた
- [ ] テストPCからIPv4 Internetへ通信できた
- [ ] DNS名前解決が動作した
- [ ] `nft list ruleset` を確認した
- [ ] WAN側からLuCI / SSHが開いていないことを確認した
- [ ] `tcpdump` でLAN/WAN通信を観測した
- [ ] `conntrack` でLAN端末の通信を確認した
- [ ] `uci show` / `ubus` で状態を取得した
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
