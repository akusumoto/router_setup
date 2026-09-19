# 自作ルーター構築 技術検討メモ

更新日: 2026-09-13

## 1. 目的

LANポートを2個備えた小型PCをルーター化し、ルーターへ直接ログインして以下を行える環境を構築する。

- ネットワーク状況の監視
- パケットキャプチャ・解析
- ルーティング、Firewall、NATの観察
- 自作プログラムによる監視・解析機能の追加

現状は **NTTフレッツ + OCN** を利用し、BUFFALO WSR-6000AX8がルーターとして動作している。接続方式は **OCNバーチャルコネクト** で、IPv6 IPoEとIPv4 over IPv6を利用している。

## 2. 現在のネットワーク

```text
NTT フレッツ / OCN
        |
     ONU/回線終端
        |
BUFFALO WSR-6000AX8
        |
     家庭内LAN
```

確認済み情報:

| 項目 | 内容 |
|---|---|
| ルーター | BUFFALO WSR-6000AX8 |
| 接続方式 | OCNバーチャルコネクト |
| IPv6 | IPoE |
| IPv4 | IPv4 over IPv6 |
| LAN | 192.168.11.0/24、ルーター 192.168.11.1 |

BUFFALOの状態画面では、IPv4アドレス `153.243.46.0` と、`1392-1407`、`2416-2431`、`3440-3455` など複数の利用可能ポート範囲が表示されている。

これらは、自作ルーターでMAP-Eを構成した際の照合用期待値として利用できる。

## 3. 技術スタック

現時点では **OpenWrt x86_64** を第一候補とする。

| 領域 | 技術 | 方針 |
|---|---|---|
| Router OS | OpenWrt x86_64 | 第一候補 |
| Firewall / NAT | nftables | Linux標準機構を直接観察・制御 |
| IPv6 | OCN IPv6 IPoE | WAN直結で早期検証 |
| IPv4 | OCN Virtual Connect / MAP-E | 最大の技術リスク。要実機検証 |
| CLI | SSH / iproute2 | ルーターへ直接ログイン |
| Packet capture | tcpdump / libpcap | 初期の解析手段 |
| Connection monitoring | conntrack / vnStat | 接続・通信量監視 |
| Custom backend | Rust | 自作router-agent / API / MCP実装の第一候補 |
| Frontend | React / TypeScript | 自作監視Web UI候補 |
| Metrics | Prometheus互換 + Grafana | 後期フェーズで追加 |
| IDS | Suricata | 将来候補 |


## 3.1 使用予定ハードウェア

自作ルーター用PCとして **Shuttle DS57U** を使用する。

確認済み構成:

| 項目 | 内容 | 方針 |
|---|---|---|
| 本体 | Shuttle DS57U | 採用 |
| CPU | Intel Celeron 3205U / 2コア / 1.5GHz | OpenWrt、通常のルーティング、監視用途には十分と見込む |
| 有線LAN 1 | Intel i211 Gigabit Ethernet | WAN候補 |
| 有線LAN 2 | Intel i218LM Gigabit Ethernet | LAN候補 |
| 無線LAN | Realtek RTL8188EE | 今回は使用しない |
| RAM | 未確認 | 要確認 |
| ストレージ | 未確認 | 要確認 |

有線LANは2ポートともIntel製NICのため、OpenWrt/Linuxでの利用に適していると見込む。

無線LANの Realtek RTL8188EE は2.4GHz帯の旧世代Wi-Fiアダプタであり、本プロジェクトでは使用しない。Wi-Fiは既存のBUFFALOルーターをAPモードで利用する方針とする。

想定する最終構成:

```text
ONU / 回線終端
      |
Intel NIC 1 (WAN)
      |
Shuttle DS57U / OpenWrt
      |
Intel NIC 2 (LAN)
      |
    Switch
      |
      +-- 有線端末
      +-- BUFFALO (AP mode)
              |
             Wi-Fi
```

## 4. OpenWrtを選ぶ理由

- WAN/LAN、DHCP、DNS、Firewall、NAT、IPv6など、ルーターとして必要な基盤が揃っている。
- LinuxベースなのでSSHでログインし、`ip`、`nft`、`tcpdump`、`conntrack` などを直接利用できる。
- x86_64小型PCで利用できる。
- MAP-Eを扱うOpenWrtの `map` パッケージが存在する。
- 自作プログラムを実行できる。
- 将来的に自作監視UIやパケット解析機能を追加しやすい。

## 5. OpenWrt上での自作プログラム

OpenWrt上で自作プログラムを実行できる。

ただし、一般的なUbuntu/Debian向けLinuxバイナリが必ずそのまま動くわけではない。OpenWrtは軽量環境で、`musl libc` などを利用するため、基本的には **OpenWrt SDK / toolchainを使って対象アーキテクチャ向けにクロスコンパイルする**。

```text
開発PC
  |-- Rust / C++ / C / Go 等
  |-- OpenWrt SDK / toolchain
  |
  +--> OpenWrt x86_64向けビルド
             |
             +--> SCP またはパッケージ化
                       |
                       v
                 自作OpenWrtルーター
```

自作 `router-agent` の実装言語は **Rust** を第一候補とする。

将来的には以下のような構成を想定する。

```text
ブラウザ / AI / Codex
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

パケット解析は、まず `tcpdump` / `libpcap` から始める。必要に応じて以下も検討する。

- AF_PACKET
- Netfilter / NFQUEUE
- eBPF


### router-agent / MCP 方針

`router-agent` は既製ソフトではなく、本プロジェクトで新規実装するOpenWrt向け管理エージェントとする。実装言語は **Rust**。

初期段階では読み取り専用で開始し、AIからルーター状態を安全に取得できることを優先する。将来的にはMCPサーバー機能を追加し、AI / Codexから構造化されたToolとしてルーターを診断・操作できるようにする。

想定する読み取り系Toolの例:

- `get_wan_status`
- `get_ipv6_status`
- `get_mape_status`
- `get_routes`
- `get_connections`
- `get_firewall_rules`
- `get_interface_stats`

構成イメージ:

```text
AI / Codex
    |
   MCP
    |
Rust router-agent
    |
    +-- UCI       : OpenWrt設定
    +-- ubus      : OpenWrtの現在状態・サービス操作
    +-- Netlink   : Linuxネットワーク情報
    +-- nftables  : Firewall / NAT
    +-- libpcap   : パケット取得・解析
```

設定変更系Toolは後から段階的に追加する。AIへrootシェルを直接開放するのではなく、許可した操作だけを `router-agent` 経由で提供する。設定変更時は、検証・バックアップ・適用・疎通確認・失敗時ロールバックを行える設計を目指す。

Rustを採用する理由:

- 常駐デーモンとしてメモリ安全性を重視できる
- Netlink、libpcap、nftables等の低レイヤー処理と相性が良い
- 非同期I/OやAPIサーバー実装に対応しやすい
- OpenWrt x86_64向けに単一バイナリとして配布しやすい
- 将来eBPF等へ発展させる場合にも相性が良い

## 6. BUFFALO配下でのテスト

初期段階では以下の構成にする。

```text
ONU
 |
BUFFALO
 |
自作OpenWrt
 |
テストLAN
```

この状態で確認できるもの:

- OpenWrt起動
- NIC認識
- WAN / LAN
- DHCP
- DNS
- NAT
- nftables
- SSH
- tcpdump
- conntrack
- 自作監視プログラム

### 制限

BUFFALO配下では、OpenWrtのWAN側はOCN回線ではなくBUFFALOのLANになる。

そのため、以下は本番同等には検証できない。

- OpenWrt自身によるIPv6 IPoE接続
- OCNからのIPv6情報取得
- OCNバーチャルコネクト
- MAP-Eパラメータ取得・計算
- IPv4 over IPv6
- MAP-Eで割り当てられたポートセットの動作

この部分は **WAN直結試験が必要**。

## 7. OCNバーチャルコネクト / MAP-E 調査結果

OpenWrtにはMAP-E / MAP-T / Lightweight 4over6を扱う `map` パッケージがあり、x86_64も対象となっている。

また、OpenWrtでOCNバーチャルコネクトを利用した実例が存在するため、実現可能性は高い。

ただし、

> OpenWrtがMAP-Eをサポートしている = OCNで標準設定だけで完全に動作する

とは限らない。

OCN向けに以下のMAP-E情報を正しく取得・計算・設定する必要がある。

- IPv4アドレス
- IPv6プレフィックス
- BRアドレス
- EA bits
- PSID
- 利用可能ポートセット

また、日本のMAP-E環境ではOpenWrt標準MAP処理の `map.sh` を調整している実装例もある。

そのため、単にIPv4 Webサイトへアクセスできることだけでなく、**複数の割当ポート範囲が正しくNATで利用されるか**まで確認する。

これを本プロジェクトの主要検証項目とする。

## 8. 推奨する検証手順

### Phase 1 - BUFFALO配下

家庭ネットワークを止めずにOpenWrtの基本機能を構築する。

確認対象:

- OpenWrt起動
- NIC認識
- WAN / LAN
- DHCP
- DNS
- NAT
- nftables
- SSH
- tcpdump

### Phase 2A - WAN直結 / IPv6 IPoE

BUFFALOを一時的に外す。

```text
ONU
 |
OpenWrt
 |
テスト用PC
```

まずMAP-Eは設定せず、IPv6だけ確認する。

```bash
ip -6 addr
ip -6 route
```

確認項目:

- IPv6アドレス取得
- IPv6プレフィックス
- IPv6 default route
- IPv6インターネット通信

### Phase 2B - MAP-Eパラメータ

取得したIPv6情報からOCN用MAP-Eパラメータを取得・計算する。

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

BUFFALOで確認済みの値と照合する。

期待値の例:

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

MAP-Eを有効化する。

```text
LAN端末
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

IPv4インターネット通信が成立することを確認する。

### Phase 2D - ポートセット検証

単にWebサイトへアクセスできるだけでは不十分。

複数の割当ポート範囲が実際にNATで利用可能か確認する。

### Phase 3 - モニタリング

以下を段階的に追加する。

- conntrack
- vnStat
- 自作Rust router-agent
- Prometheus互換metrics
- Grafana
- ntopng等のフロー解析

### Phase 4 - 発展

必要に応じて以下を追加する。

- VLAN
- IoTネットワーク分離
- Guest Wi-Fi分離
- Server VLAN
- Suricata
- eBPF

## 9. WAN直結時の確認コマンド候補

```bash
ip addr
ip route
ip -6 addr
ip -6 route

# インターフェース上の通信観察
tcpdump -i <WAN interface>

# Firewall / NAT
nft list ruleset

# Connection tracking
conntrack -L
```

## 10. リスク評価

| 項目 | リスク | 対応 |
|---|---|---|
| OpenWrt x86_64 | 低 | 小型PCのNIC互換性を事前確認 |
| IPv6 IPoE | 低〜中 | WAN直結で早期検証 |
| OCN MAP-E | 中 | 最重要。パラメータ・ポートセットまで実機検証 |
| 家庭回線停止 | 中 | BUFFALOをすぐ戻せる状態で短時間試験 |
| 自作監視機能 | 低 | ルーティング基盤と分離して段階導入 |

## 11. TODO

- [x] 小型PCの機種・CPUを確認する（Shuttle DS57U / Intel Celeron 3205U）
- [ ] 小型PCのRAM容量を確認する
- [x] 2個のLAN NICのメーカー／チップ型番を確認する（Intel i211 / Intel i218LM）
- [ ] 小型PCのストレージ種類・容量を確認する
- [ ] DS57U（Intel i211 / i218LM）でOpenWrt x86_64のイメージ／ドライバ互換性を確認する
- [ ] OpenWrt基本構成後、早期にOCN WAN直結試験を実施する

## 12. 現時点の判断

**OpenWrt x86_64を第一候補として進める。**

最大の不確定要素は **OCNバーチャルコネクト（MAP-E）**。

そのため、ルーターの全機能を作り込む前に、

1. IPv6 IPoE
2. MAP-Eパラメータ
3. IPv4 over IPv6
4. ポートセット

の順でWAN直結試験を行い、実現可能性を早期に確定する。

OpenWrtでOCN接続が成立した後、自作Rust `router-agent`、Web UI、MCP、パケット解析・可視化機能を段階的に追加する。

## 参考情報

- OpenWrt: https://openwrt.org/
- OpenWrt map package: https://openwrt.org/packages/pkgdata/map
- OCNサポート: https://support.ocn.ne.jp/
- OpenWrt Japanese IPoE / MAP-E implementation examples: https://github.com/fakemanhk/openwrt-jp-ipoe
