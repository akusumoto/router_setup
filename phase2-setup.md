# Phase 2 実施手順 — OCN直結でIPv6 IPoE / MAP-Eを検証する

更新日: 2026-09-21
状態: **計画のみ。Phase 2の配線変更、設定変更、実機試験は未実施。**

## 1. 目的と完了条件

Phase 1で確認したShuttle DS57UのOpenWrtを、一時的にBUFFALO配下からONU直結へ切り替え、次の順に検証する。家庭LAN全体の移行やBUFFALOのAP化はこの手順に含めない。

| 段階 | 実施内容 | 完了条件 |
|---|---|---|
| 2A | ONU直結でIPv6 IPoE | OpenWrt自身にグローバルIPv6、デフォルト経路、外部IPv6疎通がある |
| 2B | MAP-E情報の取得・照合 | 実測またはOCNが提示するIPv6プレフィックス、IPv4ルール、BR、EA bits、PSID/offset、ポートセットの出典と値を記録できる |
| 2C | IPv4 over IPv6 | MAP-E経由でテストPCのIPv4通信が成立し、WAN上でIPv4-in-IPv6を観測できる |
| 2D | ポートセット | 複数の割当ポート範囲がNATに設定され、制御可能な外部観測点から実際の利用も確認できる |

2AのIPv6成功だけでMAP-E成功とは判定しない。2CのWeb閲覧だけで2D完了とは判定しない。OCNは対応端末を前提にIPv4 over IPv6の利用を案内しているため、OpenWrtでのMAP-Eは実機検証が必要である。[OCN IPv6インターネット接続](https://support.ocn.ne.jp/personal/purpose/detail/pid2900000jzj/)

## 2. Phase 1から引き継ぐ実測値

以下は[Phase 1の記録](phase1-setup.md)にある値であり、ONU直結後も同じ値になるという意味ではない。

| 項目 | Phase 1で確認した状態 |
|---|---|
| 本体 / OS | Shuttle DS57U、OpenWrt 25.12.5 x86/64、ext4 |
| 下側の青いケーブル | `eth0` / Intel i211 / WAN。現在はBUFFALOのLANへ接続 |
| 上側の白いケーブル | `eth1` / Intel i218-LM / `br-lan` / テストPCへ接続 |
| OpenWrt LAN | `192.168.1.1/24`、SSH・LuCI利用可能 |
| Phase 1のWAN | `192.168.11.108/24`、ゲートウェイ `192.168.11.1` |
| IPv6設定 | `network.wan6.device='eth0'`、`network.wan6.proto='dhcpv6'` |
| ストレージ | root 98.3 MiB、Phase 1末時点で空き約72.1 MiB |
| 既存バックアップ | `backups/phase1-baseline.tar.gz`、SHA-256 `dce1e58a40a79eb93c53b1500b616bfd6007987f8992fc04076fee28e715e7bf` |

2026-09-21にPC上のバックアップファイルとSHA-256の一致を再確認した。`backups/` はGit管理対象外で、バックアップには認証情報が含まれる。

## 3. 共通準備と復旧経路

### 3.1 配線、接続、作業記録

作業前にONU、BUFFALO、DS57U、テストPCの電源とケーブル位置を記録する。白いLANケーブルと `192.168.1.1` の管理経路は維持する。青いWANケーブルだけを、2AでBUFFALOのLANからONUへ移す。ONU側の端末変更がすぐ反映されない場合は、OCN/NTT機器の説明に従ってリンク状態を確認し、必要ならBUFFALOへ戻して復旧する。無根拠にIPv4アドレスやMAPルールを固定しない。

```text
通常時: ONU -> BUFFALO -> [青・下側 eth0] DS57U [白・上側 eth1] -> テストPC
試験時: ONU -----------> [青・下側 eth0] DS57U [白・上側 eth1] -> テストPC
```

試験中、BUFFALO配下の家庭内端末は通常のインターネット経路を失う可能性がある。PCは有線LAN側 `192.168.1.x` からOpenWrtへ接続し、Wi-Fi側の経路でテスト結果を誤認しないよう、送信元インターフェースを明示する。ONUのポートを空けるため、現在ONUとBUFFALOのWANをつなぐケーブルをONU側で抜き、そのONUポートへ青いケーブルのBUFFALO側の端を差し替える。

### 3.2 バックアップ、空き容量、パッケージ

Phase 1の設定が残っていることとroot空き容量を確認する。SSHは `.local-ssh/id_ed25519_v2` を使い、複数コマンドは同じセッションで実行する。PCから次のコマンドで接続し、以下のルーター用コマンドをそのセッション内で順に実行する。

```powershell
ssh -i .local-ssh/id_ed25519_v2 -o IdentitiesOnly=yes root@192.168.1.1
```

```sh
date -Iseconds
cat /etc/openwrt_release
uci show network
uci show firewall
df -h /
sysupgrade -l
umask 077
mkdir -p /root/phase2-prep
cp -p /etc/config/network /root/phase2-prep/network
cp -p /etc/config/firewall /root/phase2-prep/firewall
cp -p /etc/config/dhcp /root/phase2-prep/dhcp
sysupgrade -b /tmp/phase2-before-wan.tar.gz
sha256sum /tmp/phase2-before-wan.tar.gz
```

PCへバックアップをコピーし、PCとルーターのSHA-256が一致することを確認する。Phase 1でOpenWrtにSFTPサーバーがなかったため、Windowsの `scp` では `-O` を使う。[OpenWrtのバックアップ手順](https://openwrt.org/docs/guide-user/troubleshooting/backup_restore)

```powershell
scp -O -i .local-ssh/id_ed25519_v2 -o BatchMode=yes root@192.168.1.1:/tmp/phase2-before-wan.tar.gz backups/
certutil -hashfile backups\phase2-before-wan.tar.gz SHA256
```

MAP-Eの `map` パッケージは、まだBUFFALO経由でIPv4インターネットを使える間に入手・導入する。まずパッケージの存在と必要容量を確認し、導入後もMAPインターフェースは作成しない。OpenWrt 25.12ではパッケージ管理に `apk` を使う。[OpenWrt apk](https://openwrt.org/docs/guide-user/additional-software/apk)、[OpenWrt 25.12.5のMAP実装](https://raw.githubusercontent.com/openwrt/openwrt/v25.12.5/package/network/ipv6/map/files/map.sh)

```sh
apk update
apk search map
apk add map
apk info -e map
command -v mapcalc
test -f /lib/netifd/proto/map.sh
df -h /
uci -q get network.wan6.iface_map
ubus call network.interface dump
```

`apk search map` で対象パッケージを特定できない、依存関係が解決しない、または空き容量が足りない場合は導入を止める。`apk upgrade` で全パッケージを更新しない。2Aでは自動生成されたMAPインターフェースがないことを確認する。`iface_map` が有効な場合は、現設定と自動設定の動作を調べてから2Aへ進む。[OpenWrt IPv6設定](https://openwrt.org/docs/guide-user/network/ipv6/configuration)

### 3.3 BUFFALO側の比較資料

配線を変える前に、BUFFALOの接続状態画面で現在のIPv4アドレス、IPv6プレフィックス、利用可能ポート範囲、接続方式を記録する。OCNマイページでIPoEの提供状況も確認する。 `router-project.md` にある `153.243.46.0` と `1392-1407`、`2416-2431`、`3440-3455` は過去の画面例であり、Phase 2の設定値として転記しない。[OCNの提供状況確認](https://support.ocn.ne.jp/hikari/faq/detail/pid2300000h6p/)

## 4. Phase 2A — ONU直結でIPv6 IPoE

### 4.1 配線変更

ルーターの設定を変更する前に、ONUとBUFFALOのWANをつなぐ既存ケーブルをONU側で外す。次に青い下側WANケーブルのBUFFALO側の端をONUへ移す。白い上側LANケーブルはテストPCへ接続したままにする。PCから `192.168.1.1` へのSSH/LuCIを確認する。Phase 1の `wan6` は既に `eth0` のDHCPv6なので、まず設定を変えずに観測する。IPv4 DHCPの `wan` がONU直結でIPv4を取得できなくても、この段階の失敗とはしない。

### 4.2 ルーターでの観測

```sh
cat /sys/class/net/eth0/carrier
ubus call network.interface.wan6 status
ip -6 addr show dev eth0
ip -6 route
logread -e odhcp6c
ping -6 -c 4 2606:4700:4700::1111
nslookup openwrt.org
```

RA、DHCPv6、IPv6通信を観察するときは、別のSSHセッションで次を起動し、必要なパケットを見た後にCtrl-Cで止める。個人用プレフィックスや通信相手が含まれるため、保存するpcapは `backups/` などGit管理外に置く。

```sh
tcpdump -ni eth0 -vv 'icmp6 or (udp port 546 or udp port 547)'
```

記録するのは `wan6` の `up`、取得したグローバルIPv6アドレス、プレフィックス長と委譲プレフィックスの有無、IPv6デフォルト経路、DNS、外部IPv6 ping、時刻である。WANにグローバルアドレスがあってもLANへプレフィックス委譲がない場合、テストPCのIPv6通信ができるとは限らない。2Aの必須判定はOpenWrt自身のIPv6で行い、LAN側IPv6は別途記録する。[OpenWrt IPv6設定](https://openwrt.org/docs/guide-user/network/ipv6/configuration)

OCNの[IPoE接続環境確認サイト](https://v6test.ocn.ne.jp/)も、実際に試験経路を通る端末から確認する。PCにWi-Fiなど別の出口がある場合、その結果をOpenWrt経由の証拠として扱わない。

## 5. Phase 2B — MAP-E情報の取得と計算

MAP-EはIPv6プレフィックス、IPv4ルール、EA bits、PSID/offset、BRなどから共有IPv4アドレスと許可ポートを決める。DHCPv6のSoftwire46オプションで情報が届く方式もRFC 7598で定義されているが、このOCN回線で何が届くかは未測定である。[RFC 7597](https://www.rfc-editor.org/rfc/rfc7597)、[RFC 7598](https://www.rfc-editor.org/rfc/rfc7598)

次の表を実測値またはOCNから確認できた値で埋める。空欄が残るうちはMAP-E設定を適用しない。

| 項目 | 実測値 | 取得元・時刻 |
|---|---|---|
| `wan6` のグローバルIPv6 / 長さ | 未測定 |  |
| 委譲プレフィックス / 長さ | 未測定 |  |
| MAPルールのIPv6プレフィックス / 長さ | 未測定 |  |
| MAPルールのIPv4プレフィックス / 長さ | 未測定 |  |
| EA bits | 未測定 |  |
| PSID長、PSID、offset | 未測定 |  |
| BR IPv6アドレス | 未測定 |  |
| 導出IPv4アドレス | 未測定 |  |
| 許可ポート範囲の一覧 | 未測定 |  |

DHCPv6の受信情報、`ubus call network.interface.wan6 status`、`logread -e odhcp6c`、BUFFALOの同時期の表示を照合する。BRやルールを推測で埋めない。OpenWrtの `mapcalc` は `<interface|*> <rule1> [rule2] ...` を受け取り、導出IPv4アドレス、PSID、ポートセットなどを表示する。[OpenWrt mapcalcのソース](https://raw.githubusercontent.com/openwrt/openwrt/v25.12.5/package/network/ipv6/map/src/mapcalc.c)

すべての値の出典を確認してから、ルール文字列を作り、まず **読み取り専用の計算だけ** 行う。以下の山括弧部分は実測値への置換が必要。ルールに明示する追加項目が必要なら、OCNから確認できた内容と `mapcalc` の受理項目に合わせて記録する。

```sh
MAP_RULE='type=map-e,ipv6prefix=<RULE_V6>,prefix6len=<V6_LEN>,ipv4prefix=<RULE_V4>,prefix4len=<V4_LEN>,ealen=<EA_BITS>,offset=<OFFSET>,br=<BR_V6>'
mapcalc wan6 "$MAP_RULE"
```

`RULE_BMR`、`RULE_1_IPV4ADDR`、`RULE_1_PSIDLEN`、`RULE_1_PORTSETS`、`RULE_1_BR` を記録し、同時期のBUFFALO表示と矛盾がないか調べる。プレフィックスが変わった場合は、Phase 1で控えたIPv4アドレスやポート範囲と一致しない可能性がある。`RULE_BMR` が空、`NO_MATCHING_PD`、または計算エラーの場合は設定を進めず、プレフィックスとルールの出典を見直す。[OpenWrt mapcalcのソース](https://raw.githubusercontent.com/openwrt/openwrt/v25.12.5/package/network/ipv6/map/src/mapcalc.c)

## 6. Phase 2C — MAP-EでIPv4 over IPv6

2Bの値が確定し、`mapcalc` の結果を確認した後でのみ設定する。次は **`MAP_RULE` に検証済みの完全なルール文字列を再入力した場合の手順**。シェルを開き直した場合、2Bで設定した変数は残らない。Phase 1のUCIでは `firewall.@zone[1].name='wan'` だったが、適用直前に必ず再確認する。

```sh
: "${MAP_RULE:?2Bで検証したMAP_RULEを設定する}"
test "$(uci get firewall.@zone[1].name)" = wan || exit 1
uci -q get network.map && exit 1
uci set network.map='interface'
uci set network.map.proto='map'
uci set network.map.maptype='map-e'
uci set network.map.tunlink='wan6'
uci set network.map.zone='wan'
uci set network.map.rule="$MAP_RULE"
uci add_list firewall.@zone[1].network='map'
uci changes
```

`uci changes` を確認し、LANの `br-lan`、`eth1`、`192.168.1.1/24` が変更されないことを確かめる。問題がなければ:

```sh
uci commit network
uci commit firewall
/etc/init.d/firewall restart
ifup map
ubus call network.interface.map status
ip -4 addr
ip -4 route
nft list ruleset
logread -e map
```

OpenWrt 25.12.5の `map.sh` は `map-e` でIPv4-in-IPv6トンネルとIPv4デフォルト経路を設定し、計算したポートセットに応じたSNAT情報をnetifdへ渡す。実際に生成されたインターフェース、経路、nftablesルールが一致することを確認する。[OpenWrt map.sh](https://raw.githubusercontent.com/openwrt/openwrt/v25.12.5/package/network/ipv6/map/files/map.sh)

テストPCの有線IPv4を確認し、送信元を指定してIPv4のDNS、ping、HTTPSを試す。WAN側で `tcpdump -ni eth0 'ip6 proto 4'` を動かし、PCからIPv4通信を発生させてIPv4-in-IPv6を観察する。PCのWi-Fi経由通信を成功と誤認しない。

```powershell
ipconfig /all
nslookup openwrt.org 192.168.1.1
ping -4 -S <TEST_PC_LAN_IP> -n 4 1.1.1.1
curl.exe --noproxy * --interface <TEST_PC_LAN_IP> -4 --connect-timeout 5 --max-time 15 -sSI https://openwrt.org/
```

MAPインターフェースが `up` でも、実際のIPv4通信、DNS、トンネルの観測がそろわなければ2Cは未完了とする。

## 7. Phase 2D — 割当ポートセットの実利用

まず `mapcalc` の `RULE_1_PORTSETS` と `nft list ruleset` のSNAT範囲を比較する。次に有線テストPCから制御可能な外部サーバーへ複数のTCP/UDP通信を発生させ、外部サーバーが見た公開IPv4アドレスと送信元ポート、ルーターの `conntrack` 出力を照合する。

```sh
conntrack -L
nft list ruleset
tcpdump -ni eth0 'ip6 proto 4'
```

外部観測点で各割当範囲の使用例が確認でき、範囲外ポートが使われていないことを記録する。自然な通信で一部の範囲しか使われなかった場合は「未観測」とし、2Dを完了扱いにしない。外部サーバーを用意できない場合も、nftablesの設定確認と実通信確認を分けて記録する。必要なら割当内ポートへの外部からの到達性を別試験として実施する。

## 8. 失敗時の復旧

### 配線だけを戻す

まず青い下側WANケーブルのONU側の端をBUFFALOのLANへ戻し、外しておいたONU-BUFFALO WANケーブルをONUへ再接続する。白いLANケーブルは動かさない。`eth0` がBUFFALOから再び `192.168.11.x` を取得し、PCからIPv4/DNS/HTTPSが復旧したことを確認する。

```sh
ifup wan
ifup wan6
ubus call network.interface.wan status
ip route
ping -c 4 192.168.11.1
ping -c 4 1.1.1.1
```

### MAP設定を元に戻す

2Cで設定を変更した場合は、3.2で保存した `/root/phase2-prep/network`、`firewall`、`dhcp` を確認してから復元する。実行前に現在のファイルと保存ファイルを `diff` で比べ、Phase 1以降に別の意図した変更があれば考慮する。

```sh
diff -u /root/phase2-prep/network /etc/config/network
diff -u /root/phase2-prep/firewall /etc/config/firewall
cp -p /root/phase2-prep/network /etc/config/network
cp -p /root/phase2-prep/firewall /etc/config/firewall
cp -p /root/phase2-prep/dhcp /etc/config/dhcp
ubus call network reload
/etc/init.d/firewall restart
ubus call network.interface.wan status
```

SSHが切れた場合は白いLANケーブルのPCから `192.168.1.1` へ再接続する。設定ファイルが失われている場合は、PC上の `backups/phase2-before-wan.tar.gz` またはPhase 1バックアップを使い、内容を確認してから[OpenWrtの復元手順](https://openwrt.org/docs/guide-user/troubleshooting/backup_restore)に従う。

## 9. 実施記録テンプレート

Phase 2は未実施。各段階を実行したら、その日の節に **実行コマンド、出力、ファイル内容、配線、時刻、判定、復旧結果** を追記する。推定値を実測値として記入しない。

| 項目 | 記録する内容 |
|---|---|
| 日時 | JSTとルーターの `date -Iseconds` |
| 配線 | 青/白ケーブルの接続先、BUFFALO/ONUの状態 |
| 設定差分 | `uci changes`、`uci show network/firewall/dhcp` |
| IPv6 | `ubus`、アドレス、プレフィックス、経路、疎通 |
| MAP-E | ルールの出典、`mapcalc` 全出力、BR、導出IPv4、PSID、ポート範囲 |
| IPv4 / NAT | PCの送信元、経路、HTTPS、トンネル、`nft`、`conntrack`、外部側ログ |
| 成果物 | バックアップ、pcap、ハッシュ、PC上の保存先 |
| 判定 | 2A/2B/2C/2Dの各完了条件と未確認点 |

### チェックリスト

- [ ] Phase 2直前の設定バックアップをPCへ保存し、ハッシュを照合した
- [ ] BUFFALOの現在のIPv4/IPv6とポート範囲を記録した
- [ ] `map` パッケージと空き容量を確認した
- [ ] 青いWANケーブルをONUへ接続し、白いLAN管理経路を維持した
- [ ] 2A: OpenWrt自身のIPv6アドレス、経路、外部疎通を確認した
- [ ] 2B: MAP-Eパラメータの出典と `mapcalc` の結果を記録した
- [ ] 2C: IPv4 over IPv6通信とWAN上のカプセル化を確認した
- [ ] 2D: 複数ポート範囲の設定と実利用を確認した
- [ ] 失敗時はBUFFALO経由へ戻し、IPv4/DNS/管理アクセスを再確認した

## 10. 参照資料

- [OCN IPv6インターネット接続](https://support.ocn.ne.jp/personal/purpose/detail/pid2900000jzj/) — IPoE提供状況、対応端末、OCNの接続判定。
- [OpenWrt IPv6 configuration](https://openwrt.org/docs/guide-user/network/ipv6/configuration) — `wan6`、DHCPv6、プレフィックス委譲とMAP自動設定オプション。
- [OpenWrt 25.12.5 MAP実装](https://raw.githubusercontent.com/openwrt/openwrt/v25.12.5/package/network/ipv6/map/files/map.sh) / [mapcalc](https://raw.githubusercontent.com/openwrt/openwrt/v25.12.5/package/network/ipv6/map/src/mapcalc.c) — UCI項目、トンネル、ポートセット計算。
- [OpenWrt apk](https://openwrt.org/docs/guide-user/additional-software/apk) / [バックアップと復元](https://openwrt.org/docs/guide-user/troubleshooting/backup_restore)。
- [RFC 7597](https://www.rfc-editor.org/rfc/rfc7597) / [RFC 7598](https://www.rfc-editor.org/rfc/rfc7598) — MAP-EとDHCPv6 Softwire46オプション。
