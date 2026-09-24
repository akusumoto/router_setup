# Custom Router Performance Evaluation Test Plan

Last updated: 2026-09-21

## 1. Objective

Evaluate the performance of the custom OpenWrt router not only based on simple file transfer speeds but also from the following perspectives:

- Maximum throughput
- Latency (RTT)
- Jitter
- Packet loss
- Responsiveness under high load
- Bidirectional communication performance
- Small packet processing performance
- DNS response performance
- NAT / Firewall processing performance
- CPU / Memory / IRQ load
- Performance differences when MAP-E, router-agent, and monitoring functions are added in the future

As a crucial policy, **measure internet line performance** and **router performance itself** separately.

## 2. Comparison Targets

At a minimum, ensure the following can be compared:

```text
A. Direct connection between PCs
B. Via BUFFALO router
C. OpenWrt Phase 1
D. OpenWrt + nftables
E. OpenWrt + monitoring
F. OpenWrt + router-agent
G. OpenWrt + MAP-E
```

Measure A through F using only the home LAN as much as possible to exclude internet-side factors.

## 3. Basic Test Topology

```text
PC-A
  |
WAN side
  |
OpenWrt
  |
LAN side
  |
PC-B
```

Set one side as `iperf3 server` and the other as `iperf3 client`.

## 4. Mandatory Test Items

### 4.1 Idle RTT

```bash
ping -c 100 <peer-ip>
```

Record:
- min
- avg
- max
- stddev
- packet loss

Compare:
- Direct PC connection
- Via BUFFALO
- Via OpenWrt

### 4.2 TCP Single Stream

Server:

```bash
iperf3 -s
```

Client:

```bash
iperf3 -c <server-ip> -t 30
```

Record:
- throughput
- retransmits
- CPU usage

### 4.3 TCP Multiple Streams

```bash
iperf3 -c <server-ip> -P 4 -t 30
iperf3 -c <server-ip> -P 8 -t 30
```

Record:
- Total throughput
- Variation per stream
- CPU usage

### 4.4 Bidirectional Communication

```bash
iperf3 -c <server-ip> --bidir -t 30
```

Record:
- Down throughput
- Up throughput
- CPU usage
- RTT changes

### 4.5 High Load RTT / Bufferbloat

Terminal 1:

```bash
iperf3 -c <server-ip> -P 4 -t 60
```

Terminal 2:

```bash
ping <server-ip>
```

Record:
- Idle RTT
- avg RTT during load
- max RTT during load
- packet loss

If it worsens to tens or hundreds of ms under load, suspect bufferbloat.

### 4.6 UDP Throughput

```bash
iperf3 -c <server-ip> -u -b 100M -t 30
iperf3 -c <server-ip> -u -b 500M -t 30
```

Record:
- achieved bandwidth
- jitter
- lost/total datagrams
- loss %

### 4.7 Small Packet Performance

Representative sizes:

```text
64 bytes
128 bytes
256 bytes
512 bytes
1500 bytes
```

The objective is to check PPS performance, which is not visible in Mbps. On the DS57U, check the load on the Celeron 3205U when processing large amounts of small packets.

### 4.8 Packet Loss / Jitter

Key records:
- packet loss
- jitter
- RTT stddev
- max RTT

### 4.9 DNS Response

```bash
dig openai.com
```

Or:

```bash
nslookup openai.com
```

If possible, separate the following:

```text
Cold cache
Warm cache
```

Record:
- Query time
- Success / Failure
- DNS used

## 5. NAT / Firewall Performance

Run `iperf3` in a normal router configuration and compare the following:

```text
Basic routing
↓
nftables / NAT enabled
↓
Monitoring added
↓
router-agent added
```

Record:
- throughput
- RTT
- CPU
- conntrack count

## 6. Connection Tracking

```bash
conntrack -L
conntrack -C
```

Verify:
- Connection count
- Increase under high load
- Abnormal stagnation
- Whether NAT traffic is properly tracked

## 7. CPU / Memory / IRQ Monitoring

### CPU

```bash
top
```

Verify:
- CPU usage
- load average
- softirq load

### Memory

```bash
free
cat /proc/meminfo
```

### NIC IRQ

```bash
cat /proc/interrupts
```

### Network Statistics

```bash
ip -s link
```

Verify:
- RX/TX packets
- dropped
- errors
- overruns

## 8. Internet Side Performance

Conduct separately from the home LAN testing.

Verify:
- Download
- Upload
- RTT
- jitter
- packet loss

Candidates:
- Speedtest
- ping
- External iperf3 server

Since the following external factors are included, treat this separately from the standalone router evaluation:

```text
OCN
NTT network
Route congestion
Measurement server congestion
Time of day
```

## 9. Additional Checks After MAP-E Implementation

Compare:

```text
IPv6 native
IPv4 over MAP-E
```

Verify:
- TCP throughput
- UDP throughput
- idle RTT
- load RTT
- CPU
- packet loss
- conntrack
- Behavior when using port sets

## 10. Comparison After router-agent Implementation

```text
router-agent stopped
router-agent running
router-agent high-frequency monitoring
```

Record:
- throughput
- RTT
- CPU
- memory
- packet loss

## 11. Recommended 8-Item Baseline

1. TCP 1 stream throughput
2. TCP 4 stream throughput
3. TCP bidirectional throughput
4. Idle RTT
5. Load RTT
6. UDP jitter / packet loss
7. CPU usage
8. Internet throughput / RTT

Use this as a simple regression test after configuration changes.

## 12. Measurement Result Format

| Test | Throughput | RTT avg | RTT max | Jitter | Loss | CPU |
|---|---:|---:|---:|---:|---:|---:|
| TCP 1 stream | - | - | - | - | - | - |
| TCP 4 stream | - | - | - | - | - | - |
| TCP 8 stream | - | - | - | - | - | - |
| TCP bidir | - | - | - | - | - | - |
| UDP 100M | - | - | - | - | - | - |
| UDP 500M | - | - | - | - | - | - |
| Idle latency | - | - | - | - | - | - |
| Load latency | - | - | - | - | - | - |
| DNS cold | - | - | - | - | - | - |
| DNS warm | - | - | - | - | - | - |

Additional records:

```text
Router:
OpenWrt version:
Kernel:
CPU:
RAM:
NIC:
WAN interface:
LAN interface:
nftables:
router-agent:
MAP-E:
Test date:
Test duration:
Notes:
```

## 13. Codex Implementation Policy

Assumed structure:

```text
performance-test/
├── README.md
├── client/
│   └── run-tests.sh
├── router/
│   └── collect-router-stats.sh
├── results/
│   └── YYYYMMDD-HHMM/
│       ├── iperf3.json
│       ├── ping.txt
│       ├── cpu.txt
│       ├── interrupts.txt
│       ├── ip-link.txt
│       └── result.md
└── scripts/
    └── generate-report.*
```

Requirements for Codex:

- Make each test re-runnable under the same conditions
- Save JSON output for `iperf3` if possible
- Simultaneously collect router-side statistics
- Do not alter existing network settings
- Tests must be read-only by default
- Save measurement results into time-stamped directories
- Do not overwrite existing results
- Summarize results into Markdown
- Enable comparison between BUFFALO / OpenWrt / post MAP-E implementation

## 14. TODO

- [ ] Check if 2 test PCs can be prepared on the LAN
- [ ] Install iperf3 on each PC
- [ ] Install tcpdump / conntrack, etc., on OpenWrt
- [ ] Obtain the first OpenWrt baseline upon Phase 1 completion
- [ ] Obtain a baseline with the current BUFFALO router as much as possible
- [ ] Create automated test scripts with Codex
- [ ] Finalize the result save format
- [ ] Re-run the same tests after implementing MAP-E
- [ ] Re-compare before and after router-agent implementation

## 15. Real Internet Comparison Test Between BUFFALO and OpenWrt

### 15.1 Objective

Compare the real internet performance on the same OCN line between the currently used **BUFFALO WSR-6000AX8** and the post-switch **Shuttle DS57U / OpenWrt**.

In the comparison, evaluate not only simple maximum speeds but also the following:

- IPv4 effective speed
- IPv6 effective speed
- Idle latency
- High load latency
- Jitter
- Packet loss
- DNS response
- IPv4 over IPv6 / MAP-E health

### 15.2 Comparison Setup

Environment A:

```text
ONU
 |
BUFFALO WSR-6000AX8
 |
Test PC
```

Environment B:

```text
ONU
 |
Shuttle DS57U
OpenWrt
 |
Test PC
```

Keep the following identical whenever possible:

- Same test PC
- Same LAN cables
- Same measurement targets
- Same Speedtest server
- Same test scripts
- Similar time of day
- Same number of iterations
- Test using wired LAN

Do not include Wi-Fi performance in this comparison.

### 15.3 Evaluate IPv4 / IPv6 Separately

In the OCN environment, evaluate the following separately:

```text
IPv6
OpenWrt / BUFFALO
       |
       v
OCN IPv6 IPoE
       |
       v
IPv6 Internet
```

```text
IPv4
OpenWrt / BUFFALO
       |
       v
OCN Virtual Connect / MAP-E
       |
       v
IPv4 Internet
```

Do not mix IPv4 and IPv6; measure explicitly where possible.

Example:

```bash
ping -4 <test-host>
ping -6 <test-host>
```

### 15.4 Comparison Items

| Item | BUFFALO | OpenWrt |
|---|---:|---:|
| IPv4 Download | - | - |
| IPv4 Upload | - | - |
| IPv6 Download | - | - |
| IPv6 Upload | - | - |
| IPv4 Idle RTT | - | - |
| IPv6 Idle RTT | - | - |
| IPv4 Load RTT | - | - |
| IPv6 Load RTT | - | - |
| IPv4 Jitter | - | - |
| IPv6 Jitter | - | - |
| IPv4 Packet loss | - | - |
| IPv6 Packet loss | - | - |
| DNS cold | - | - |
| DNS warm | - | - |

On the OpenWrt side, additionally record:

- CPU usage
- load average
- conntrack count
- interface drop/error
- softirq
- MAP-E status

### 15.5 Speedtest

For real internet bandwidth measurements, fix the same Speedtest server if possible.

Run at least 3 times in each environment.

Record:

- Download
- Upload
- Idle latency
- Latency during Download load
- Latency during Upload load
- jitter
- packet loss (if retrievable)
- Server used
- Measurement time

Save not just single values but also:

```text
minimum
median
maximum
```

In particular, use the **median** as the representative value.

### 15.6 External RTT

Measure IPv4 / IPv6 against the same external destinations.

Example:

```bash
ping -4 -c 100 <test-host>
ping -6 -c 100 <test-host>
```

Record:

- min
- avg
- max
- stddev
- packet loss

Use at least a few different external destinations to avoid being affected by just one specific route.

### 15.7 High Load Latency

Run ping concurrently with speed measurements or large transfers.

```text
Terminal A
Speedtest / Large Transfer

Terminal B
ping -4 <test-host>

Terminal C
ping -6 <test-host>
```

Specifically compare the following:

```text
Idle RTT
       ↓
RTT during Download load
       ↓
RTT during Upload load
```

The objective is to check if there are differences in bufferbloat or queuing delays between BUFFALO and OpenWrt.

### 15.8 DNS Comparison

Measure multiple times against the same domain.

Check targets:

```text
Cold cache
Warm cache
```

Since OpenWrt and BUFFALO may have different DNS caching behaviors, record both.

### 15.9 MAP-E Feature Comparison

Use the OCN Virtual Connect info currently confirmed on the BUFFALO router as the expected values after switching to OpenWrt.

Confirmed examples:

```text
IPv4 address
153.243.46.0

Port sets
1392-1407
2416-2431
3440-3455
...
```

Verify the following on OpenWrt:

- OCN Virtual Connect is established successfully
- IPv4 address matches the expected value
- MAP-E parameters are correct
- Usable port sets match expected values
- IPv4 communication is normal
- Multiple allocated port ranges can be used
- IPv6 native and IPv4 over IPv6 communication can be used simultaneously

Because values might not perfectly match the BUFFALO router if ISP assignments change, compare against the "BUFFALO baseline at that time".

### 15.10 Variation by Time of Day

Internet performance includes factors beyond the router, so obtain measurements at multiple times of day if possible.

Example:

```text
Morning
Daytime
Evening
Late night
```

However, since switching frequently between BUFFALO and OpenWrt heavily affects the home network, prioritize running continuous measurements at a single proximate time for the initial comparison.

### 15.11 Recommended Execution Order

```text
1. Obtain baseline on BUFFALO
2. Save results and timestamp
3. Physically switch to OpenWrt
4. Verify IPv6 IPoE / MAP-E health
5. Run the same tests on OpenWrt
6. Automatically compare with BUFFALO results
```

If connection issues occur on OpenWrt, do not continue performance testing; prioritize reverting to BUFFALO and investigating the cause.

### 15.12 Result Storage Structure

```text
results/
├── buffalo/
│   └── YYYYMMDD-HHMM/
│       ├── environment.txt
│       ├── speedtest/
│       ├── ping-ipv4.txt
│       ├── ping-ipv6.txt
│       ├── dns.txt
│       └── result.md
│
└── openwrt/
    └── YYYYMMDD-HHMM/
        ├── environment.txt
        ├── speedtest/
        ├── ping-ipv4.txt
        ├── ping-ipv6.txt
        ├── dns.txt
        ├── router-stats/
        └── result.md
```

Comparison report:

```text
results/comparisons/
└── buffalo-vs-openwrt-YYYYMMDD.md
```

### 15.13 Implementation Requirements for Codex

Automated comparison tests must fulfill the following:

- Use the exact same client-side test on both BUFFALO and OpenWrt
- Explicitly separate IPv4 and IPv6
- Run each measurement at least 3 times generally
- Save raw data
- Calculate minimum / median / maximum
- Log measurement targets and Speedtest servers used
- Log test start and end times
- Do not overwrite existing results
- Simultaneously fetch CPU, conntrack, and interface statistics on the OpenWrt side
- Explicitly exclude internal info from comparison if it cannot be retrieved from BUFFALO
- Do not change router settings for the sake of the test
- Save reasons and partial results upon failure
- Generate a final `buffalo-vs-openwrt-*.md` comparison report

### 15.14 Notes on Comparison

Real internet performance is affected by:

- OCN side load
- NTT network congestion
- External routes
- Speedtest servers
- Time of day
- Connected CDNs
- MAP-E side equipment

Therefore, do not judge the superiority or inferiority of router performance solely based on a few percent speed difference.

If a significant difference emerges, isolate the cause by combining LAN performance tests and OpenWrt CPU / interface statistics.

## 16. Initial Real Internet Route Test — 2026-09-22

### 16.1 Scope and topology

This was a read-only initial test of the two routes that were simultaneously available from the same PC after Phase 1:

```text
Route A (BUFFALO): PC Wi-Fi 192.168.11.109 -> BUFFALO 192.168.11.1 -> ONU -> Internet
Route B (OpenWrt): PC Ethernet 192.168.1.239 -> OpenWrt 192.168.1.1
                    -> OpenWrt WAN 192.168.11.108 -> BUFFALO 192.168.11.1
                    -> ONU -> Internet
```

This is not an equal wired-router comparison. Route A used Wi-Fi, while Route B used Ethernet and double NAT through OpenWrt and BUFFALO. The results only describe these current routes.

The Windows route table contained both IPv4 default routes. The OpenWrt route had metric 25 and the BUFFALO route had metric 30. Each IPv4 test was explicitly bound to the corresponding PC source address.

Only the BUFFALO Wi-Fi interface had a global IPv6 address and IPv6 default route. The OpenWrt Phase 1 Ethernet interface had ULA addresses but no IPv6 default route, so no Route B IPv6 internet comparison was attempted.

### 16.2 IPv4 path and public-address check

Command form:

```powershell
curl.exe -4 --interface <source-ip> --connect-timeout 10 --max-time 20 -sS https://cloudflare.com/cdn-cgi/trace
```

Observed result:

| Route | Source address | HTTP result | Public IPv4 | Cloudflare location |
|---|---|---|---|---|
| BUFFALO | 192.168.11.109 | Success | 153.243.46.0 | NRT |
| OpenWrt | 192.168.1.239 | Success | 153.243.46.0 | NRT |

Both source-bound paths reached the internet and used the same public IPv4 address.

### 16.3 Idle IPv4 RTT

Successful command form:

```powershell
ping.exe -4 -S <source-ip> -n 30 1.1.1.1
```

| Route | Sent/received | Loss | Minimum | Average | Maximum |
|---|---:|---:|---:|---:|---:|
| BUFFALO | 30/30 | 0% | 6 ms | 6 ms | 7 ms |
| OpenWrt | 30/30 | 0% | 6 ms | 6 ms | 22 ms |

The Windows summary does not provide RTT standard deviation. One OpenWrt-path sample was 22 ms and one was 14 ms; the remaining samples were 6–7 ms.

Failed attempt before the successful run:

```powershell
rtk proxy ping.exe -4 -S <source-ip> -n 30 -w 2000 1.1.1.1
```

This did not execute the ping because the local `rtk` PowerShell shim interpreted `-w` as an ambiguous PowerShell parameter. Removing the optional `-w` flag corrected the invocation.

### 16.4 Initial download samples

Each run downloaded 25,000,000 bytes from Cloudflare's speed endpoint and discarded the body. Runs were sequential, and the source address selected the route.

Successful command form:

```powershell
curl.exe --ipv4 --interface <source-ip> --connect-timeout 10 --max-time 120 `
  --output NUL --silent --show-error `
  --write-out "code=%{http_code} bytes=%{size_download} time=%{time_total} speed_Bps=%{speed_download}" `
  "https://speed.cloudflare.com/__down?bytes=25000000"
```

| Route | Run 1 | Run 2 | Run 3 | Median |
|---|---:|---:|---:|---:|
| BUFFALO | 240.49 Mbps | 377.30 Mbps | 426.20 Mbps | 377.30 Mbps |
| OpenWrt | 88.78 Mbps | 88.61 Mbps | 82.93 Mbps | 88.61 Mbps |

All six requests returned HTTP 200 and exactly 25,000,000 bytes. These short 25 MB transfers are preliminary samples, not maximum-line-rate certification.

The first download attempt used curl's short `-o NUL` form and did not execute because the local `rtk` PowerShell shim interpreted `-o` as an ambiguous PowerShell parameter. Replacing it with `--output NUL` corrected the invocation.

### 16.5 OpenWrt observations and cause of the throughput ceiling

Router inspection used SSH with `.local-ssh/id_ed25519_v2`. A persistent session was used for each related command series. No router configuration was changed.

Observed WAN status:

```text
up: true
device: eth0
protocol: DHCP
IPv4 address: 192.168.11.108/24
default gateway: 192.168.11.1
DNS server: 192.168.11.1
conntrack count after the transfer tests: 82
```

Observed link state from `/sys/class/net`:

| Interface | Role | Speed | Duplex | Carrier | RX errors/drops | TX errors/drops |
|---|---|---:|---|---:|---:|---:|
| eth0 | WAN to BUFFALO | 1000 Mbps | full | 1 | 0 / 0 | 0 / 4 |
| eth1 | LAN to test PC | 100 Mbps | full | 1 | 0 / 0 | 0 / 0 |

The approximately 83–89 Mbps OpenWrt-path result is consistent with the observed 100 Mbps negotiation on `eth1`. Therefore this run does **not** demonstrate an OpenWrt routing or CPU limit. The LAN cable, PC NIC negotiation, and `eth1` negotiation must be corrected to 1000/full before a meaningful throughput comparison.

The first router statistics attempt also showed two non-measurement failures: `ethtool` produced no matching speed/duplex/link lines, and this BusyBox `ip` implementation rejected `ip -s link`. Direct read-only `/sys/class/net/<interface>/...` values were then used successfully.

### 16.6 DNS attempt

Two attempts to automate three timed `Resolve-DnsName` queries per router failed locally because nested PowerShell and `cmd.exe` quoting was parsed incorrectly. No DNS query timing is recorded from those attempts. DNS cold/warm comparison remains pending and must use a checked script rather than an inline nested command.

### 16.7 Result and next action

- [x] Confirm both current IPv4 routes can reach the internet independently when bound to their source addresses.
- [x] Record an initial 30-packet idle RTT sample for each route.
- [x] Record three initial 25 MB download samples for each route.
- [x] Inspect OpenWrt WAN status, conntrack count, physical link speed, duplex, carrier, and error/drop counters.
- [x] Correct the OpenWrt LAN `eth1` link from 100/full to 1000/full. The Shuttle-to-GS305v3 cable was replaced on 2026-09-22.
- [x] Repeat the same source-bound download and RTT tests after link correction. See Section 17.
- [ ] Implement reproducible DNS cold/warm timing.

## 18. BAFFALO-to-ONU Cat6A Replacement: Real-Internet Retest — 2026-09-25

### 18.1 Scope and topology

The user replaced the BAFFALO-to-ONU Ethernet cable from Cat6 to Cat6A before this retest. No router configuration was changed. This is a source-bound real-internet test, not a controlled cable certification test: it confirms the paths were usable after the replacement, but does not by itself prove that Cat6A caused a speed change versus the previous cable.

At the time of the test, the Windows host had both wired paths active:

```text
AX88179 USB 3.0 adapter, 192.168.11.20 -> BAFFALO, 192.168.11.1
Realtek PCIe GbE adapter, 192.168.1.157 -> OpenWrt LAN, 192.168.1.1
OpenWrt eth0, 192.168.11.108 -> BAFFALO, 192.168.11.1
```

The Windows IPv4 route table contained defaults of equal metric 25 for both source addresses. Every HTTP request below therefore explicitly used `--interface <source IPv4>`; this avoids treating the selected default route as evidence of the tested path.

### 18.2 Commands and path/latency results

Commands were executed in this order. `rtk proxy cmd.exe /c` was used because the wrapper otherwise parses curl and ping flags. Both commands exited `0`.

```powershell
rtk proxy cmd.exe /c "curl.exe --ipv4 --interface 192.168.11.20 --connect-timeout 10 --max-time 20 --silent --show-error https://cloudflare.com/cdn-cgi/trace"
rtk proxy cmd.exe /c "curl.exe --ipv4 --interface 192.168.1.157 --connect-timeout 10 --max-time 20 --silent --show-error https://cloudflare.com/cdn-cgi/trace"
rtk proxy cmd.exe /c "ping.exe -4 -S 192.168.11.20 -n 30 -w 2000 1.1.1.1"
rtk proxy cmd.exe /c "ping.exe -4 -S 192.168.1.157 -n 30 -w 2000 1.1.1.1"
```

Both Cloudflare traces reported the same public IPv4 address, `153.243.13.0`, and NRT. The exact ping summaries were:

| Bound route | Sent/received/lost | RTT min/avg/max |
|---|---:|---:|
| BAFFALO, `192.168.11.20` | 30 / 30 / 0 (0%) | 3 / 3 / 6 ms |
| OpenWrt, `192.168.1.157` | 30 / 30 / 0 (0%) | 4 / 4 / 5 ms |

### 18.3 Download throughput

The target was the same 25,000,000-byte Cloudflare object used by the earlier conditions. The first BAFFALO request and five alternating requests all returned HTTP `200` and exactly `25000000` bytes. The six curl commands exited `0`.

```powershell
rtk proxy cmd.exe /c "curl.exe --ipv4 --interface <source-ip> --connect-timeout 10 --max-time 120 --output NUL --silent --show-error --write-out \"route=<route> code=%{http_code} bytes=%{size_download} time=%{time_total} speed_Bps=%{speed_download}\n\" \"https://speed.cloudflare.com/__down?bytes=25000000\""
```

The commands were run in the following sequence: BAFFALO run 1, OpenWrt run 1, BAFFALO run 2, OpenWrt run 2, BAFFALO run 3, OpenWrt run 3.

| Bound route | Run 1 | Run 2 | Run 3 | Median |
|---|---:|---:|---:|---:|
| BAFFALO, AX88179 USB 3.0 | 502.92 Mbps | 311.83 Mbps | 395.35 Mbps | **395.35 Mbps** |
| OpenWrt, Realtek PCIe | 487.00 Mbps | 481.89 Mbps | 480.10 Mbps | **481.89 Mbps** |

Raw successful curl observations:

```text
route=BUFFALO run=1 code=200 bytes=25000000 time=0.397683 speed_Bps=62864456
route=OpenWrt run=1 code=200 bytes=25000000 time=0.410682 speed_Bps=60874795
route=BUFFALO run=2 code=200 bytes=25000000 time=0.641372 speed_Bps=38979060
route=OpenWrt run=2 code=200 bytes=25000000 time=0.415034 speed_Bps=60236319
route=BUFFALO run=3 code=200 bytes=25000000 time=0.505887 speed_Bps=49418346
route=OpenWrt run=3 code=200 bytes=25000000 time=0.416583 speed_Bps=60012338
```

Mbps is `speed_Bps * 8 / 1,000,000`. The BAFFALO series varied substantially, so its median rather than its best result is used for comparison.

### 18.4 OpenWrt health evidence

A persistent SSH session to `root@192.168.1.1` using `.local-ssh/id_ed25519_v2` collected read-only state before and after the transfers. The router clock recorded `2026-09-24 16:10:45 GMT` before the test and `16:12:43 GMT` after it (2026-09-25 JST). The WAN DHCP state was up on `eth0` with `192.168.11.108/24`, default gateway/DNS `192.168.11.1`.

```text
                     Before                 After
eth0 / eth1          1000/full, carrier 1   1000/full, carrier 1
eth0 errors/drops    RX 0/0, TX 0/4          RX 0/0, TX 0/4
eth1 errors/drops    RX 0/0, TX 0/0          RX 0/0, TX 0/0
load average         0.01 0.00 0.00          0.00 0.00 0.00
conntrack count      132                     121
```

Observed result: the Cat6A replacement is followed by successful real-internet transfers on both paths, low-loss/low-latency pings, and no new OpenWrt interface errors or drops. The current samples do not establish an improvement over the 2026-09-22 USB 3.0 medians (566.50/566.67 Mbps), because Internet endpoints and time-of-day vary and there was no immediately-before Cat6 baseline under otherwise identical conditions. A controlled same-host/same-NIC retest and a BAFFALO WAN-port link/status observation would be needed to attribute a difference to this cable.
- [x] Perform a wired BUFFALO-versus-OpenWrt comparison. See Section 17 Conditions B and C; the paths used different PC NICs, so it is not yet a same-adapter comparison.

## 17. Real Internet Retests by Physical Connection Condition — 2026-09-22

### 17.1 Purpose and shared procedure

Sections 17 through 19 were consolidated because the route-selection and measurement procedure was unchanged. The variables were physical connection conditions:

1. Replacement of the Shuttle `eth1` LAN cable, changing the link from 100/full to 1000/full.
2. Replacement of BUFFALO Wi-Fi with an AX88179 wired connection.
3. Movement of the AX88179 adapter from a USB 2.0 port to a USB 3.0 port.

The following procedure was shared unless a condition-specific note says otherwise:

- Wi-Fi source when enabled: `192.168.11.109`.
- BUFFALO wired AX88179 source: `192.168.11.128`.
- OpenWrt wired Realtek source: `192.168.1.239`.
- BUFFALO gateway: `192.168.11.1`.
- OpenWrt gateway: `192.168.1.1`.
- IPv4 requests were explicitly bound to the applicable source address.
- Path check: source-bound request to `https://cloudflare.com/cdn-cgi/trace`.
- Idle RTT: `ping.exe -4 -S <source-ip> -n 30 1.1.1.1`.
- Download: 25,000,000 bytes from `https://speed.cloudflare.com/__down?bytes=25000000`.
- OpenWrt state was collected through persistent SSH sessions using `.local-ssh/id_ed25519_v2`.
- No router configuration was changed.

All successful path checks reported public IPv4 `153.243.46.0` at Cloudflare location `NRT`.

### 17.2 Conditions and comparative results

| Condition | BUFFALO client path | OpenWrt LAN link | BUFFALO median | OpenWrt median | Interpretation |
|---|---|---:|---:|---:|---|
| Initial, Section 16 | Wi-Fi | 100/full | 377.30 Mbps | 88.61 Mbps | OpenWrt was limited by the 100 Mbps Link A negotiation. |
| A: Link A cable replaced | Wi-Fi | 1000/full | 353.48 Mbps | 513.34 Mbps | The OpenWrt 100 Mbps ceiling disappeared. |
| B: BUFFALO wired, AX88179 on USB 2.0 | Wired, 1 Gbps Ethernet negotiation | 1000/full | 278.90 Mbps | 527.44 Mbps | BUFFALO-side result showed a stable approximately 280 Mbps ceiling. |
| C: BUFFALO wired, AX88179 on USB 3.0 | Wired, 1 Gbps Ethernet negotiation | 1000/full | 566.50 Mbps | 566.67 Mbps | The USB-side ceiling disappeared; the two route medians were effectively equal. |

The condition changes identify two independent physical bottlenecks:

- Replacing the Shuttle-to-GS305v3 cable changed OpenWrt `eth1` from 100/full to 1000/full and raised the OpenWrt median from 88.61 to 513.34 Mbps.
- Moving the same AX88179 adapter from USB 2.0 to USB 3.0 raised the BUFFALO wired median from 278.90 to 566.50 Mbps.

The results do not support attributing the earlier BUFFALO under-400 Mbps result to Wi-Fi alone. The subsequent USB 2.0 wired result was slower than Wi-Fi, while the USB 3.0 wired result was substantially faster.

### 17.3 Idle RTT by condition

| Condition | BUFFALO path min/avg/max | OpenWrt path min/avg/max | Loss |
|---|---:|---:|---:|
| Initial, Section 16 | 6/6/7 ms, Wi-Fi | 6/6/22 ms | 0% both |
| A: Link A cable replaced | 6/6/7 ms, Wi-Fi | 6/6/6 ms | 0% both |
| B: AX88179 on USB 2.0 | 8/8/20 ms, wired | 6/6/12 ms | 0% both |
| C: AX88179 on USB 3.0 | 8/8/9 ms, wired | 6/6/6 ms | 0% both |

The wired paths used different PC NICs: AX88179 USB for BUFFALO and onboard Realtek for OpenWrt. The RTT difference therefore cannot be attributed solely to the routers.

### 17.4 Condition A — replacement of the OpenWrt Link A cable

Physical change:

```text
Shuttle eth1 -> replacement cable -> NETGEAR GS305v3
```

The user observed:

```console
root@OpenWrt:~# cat /sys/class/net/eth1/speed
1000
```

Each request returned HTTP 200 and exactly 25,000,000 bytes:

| Route | Run 1 | Run 2 | Run 3 | Median |
|---|---:|---:|---:|---:|
| BUFFALO Wi-Fi | 399.55 Mbps | 353.48 Mbps | 342.60 Mbps | 353.48 Mbps |
| OpenWrt wired | 513.34 Mbps | 397.77 Mbps | 543.40 Mbps | 513.34 Mbps |

Raw curl observations:

```text
route=BUFFALO run=1 code=200 bytes=25000000 time=0.500571 speed_Bps=49943264
route=BUFFALO run=2 code=200 bytes=25000000 time=0.565803 speed_Bps=44185224
route=BUFFALO run=3 code=200 bytes=25000000 time=0.583780 speed_Bps=42824571
route=OpenWrt run=1 code=200 bytes=25000000 time=0.389610 speed_Bps=64167060
route=OpenWrt run=2 code=200 bytes=25000000 time=0.502805 speed_Bps=49721262
route=OpenWrt run=3 code=200 bytes=25000000 time=0.368052 speed_Bps=67925553
```

This confirmed that the original OpenWrt ceiling was caused by Link A negotiating at 100 Mbps.

### 17.5 Condition B — wired BUFFALO through AX88179 on USB 2.0

Wi-Fi was disconnected. Windows reported both Ethernet adapters at 1 Gbps. The first three runs were grouped by route; the next three were alternated. All twelve requests returned HTTP 200 and exactly 25,000,000 bytes.

| Route | Run 1 | Run 2 | Run 3 | Run 4 | Run 5 | Run 6 | Median |
|---|---:|---:|---:|---:|---:|---:|---:|
| BUFFALO wired | 258.39 | 293.23 | 281.02 | 279.88 | 277.92 | 275.12 | **278.90 Mbps** |
| OpenWrt wired | 492.79 | 537.48 | 567.34 | 531.16 | 494.62 | 523.72 | **527.44 Mbps** |

Raw curl speeds in bytes per second:

```text
BUFFALO: 32298197, 36653236, 35127851, 34985390, 34739833, 34390591
OpenWrt: 61598354, 67185337, 70917760, 66394890, 61827012, 65465419
```

Windows reporting `1 Gbps` established Ethernet negotiation but did not establish the USB bus rate. The stable approximately 280 Mbps ceiling led to the USB 2.0 hypothesis.

A read-only PowerShell attempt to inspect AX88179 parent/location metadata failed because nested quoting caused `Format-Table` to reject `-Wrap`. No USB bus-speed evidence came from that command.

An attempt to obtain longer samples using `bytes=100000000` also failed: all six requests returned HTTP 403 with a one-byte body in 0.028–0.045 seconds. These endpoint rejections were not treated as throughput measurements.

### 17.6 Condition C — same AX88179 moved to USB 3.0

Wi-Fi remained disconnected. Addresses, routes, and reported 1 Gbps Ethernet link speeds were unchanged. Requests alternated between the two routes.

Valid HTTP 200 results:

| Route | Run 1 | Run 2 | Run 3 | Run 4 | Run 5 | Valid median |
|---|---:|---:|---:|---:|---:|---:|
| BUFFALO wired, USB 3.0 | 481.48 | 604.01 | 618.72 | 529.00 | - | **566.50 Mbps** |
| OpenWrt wired | 616.70 | 483.58 | 566.67 | 481.98 | 584.53 | **566.67 Mbps** |

BUFFALO had four valid samples and OpenWrt had five because Cloudflare began rate-limiting the sequence.

Raw valid curl observations:

```text
route=OpenWrt-wired run=1 code=200 bytes=25000000 time=0.324313 speed_Bps=77086975
route=BUFFALO-wired-USB3 run=1 code=200 bytes=25000000 time=0.415390 speed_Bps=60184839
route=OpenWrt-wired run=2 code=200 bytes=25000000 time=0.413586 speed_Bps=60447212
route=BUFFALO-wired-USB3 run=2 code=200 bytes=25000000 time=0.331120 speed_Bps=75501784
route=OpenWrt-wired run=3 code=200 bytes=25000000 time=0.352939 speed_Bps=70834372
route=BUFFALO-wired-USB3 run=3 code=200 bytes=25000000 time=0.323249 speed_Bps=77340238
route=OpenWrt-wired run=4 code=200 bytes=25000000 time=0.414956 speed_Bps=60247641
route=BUFFALO-wired-USB3 run=4 code=200 bytes=25000000 time=0.378078 speed_Bps=66124446
route=OpenWrt-wired run=5 code=200 bytes=25000000 time=0.342158 speed_Bps=73066086
```

Rate-limited requests:

```text
route=BUFFALO-wired-USB3 run=5 code=429 bytes=1 time=0.049956
route=OpenWrt-wired run=6 code=429 bytes=1 time=0.041718
route=BUFFALO-wired-USB3 run=6 code=429 bytes=1 time=0.045823
```

The HTTP 429 responses were excluded and were not immediately retried.

Moving the adapter to USB 3.0 removed the approximately 280 Mbps ceiling. The controlled before/after change strongly supports the USB 2.0 bus as the limiting factor in Condition B.

### 17.7 OpenWrt post-test health snapshots

These values were collected after each transfer series, not concurrently, so they are health snapshots rather than peak-load measurements.

| Condition | Timestamp | eth0 | eth1 | eth1 errors/drops | Conntrack | Load average |
|---|---|---|---|---:|---:|---|
| A: cable replaced | 2026-09-22 01:46:30 JST | 1000/full | 1000/full | 0 / 0 | 74 | 0.00 0.00 0.00 |
| B: AX88179 on USB 2.0 | 2026-09-22 02:08:56 JST | 1000/full | 1000/full | 0 / 0 | 81 | 0.00 0.00 0.00 |
| C: AX88179 on USB 3.0 | 2026-09-22 02:14:27 JST | 1000/full | 1000/full | 0 / 0 | 107 | 0.05 0.01 0.00 |

In every snapshot, both interfaces had carrier, full duplex, zero RX errors/drops, and zero TX errors. The four cumulative `eth0` TX drops remained unchanged. The Condition A memory snapshot was 8,039,660 KiB total, 55,932 KiB used, 7,904,420 KiB available, with no swap.

### 17.8 Conclusions and remaining work

- [x] Replace the faulty/unsuitable Shuttle-to-GS305v3 cable and restore OpenWrt `eth1` to 1000/full.
- [x] Confirm the original OpenWrt approximately 89 Mbps ceiling disappears at 1000/full.
- [x] Replace BUFFALO Wi-Fi with a 1 Gbps wired client connection.
- [x] Identify and remove the AX88179 USB 2.0 throughput ceiling by moving it to USB 3.0.
- [x] Observe effectively equal USB 3.0 BUFFALO and OpenWrt medians: 566.50 and 566.67 Mbps.
- [ ] Repeat with the same PC Ethernet adapter moved between routers for a strict same-NIC comparison.
- [ ] Use controlled LAN `iperf3` to isolate router forwarding from internet and endpoint variability.
- [ ] Use longer-duration measurements from a suitable endpoint and collect CPU statistics concurrently.
- [ ] Implement reproducible DNS cold/warm timing.

## 19. Downlink and Uplink Retest — 2026-09-25

This retest was deliberately limited to source-bound throughput. It did not collect route traces, pings, interface counters, or router health snapshots. The same active wired source addresses as Section 18 were used: BAFFALO `192.168.11.20` and OpenWrt `192.168.1.157`.

### 19.1 Method and command outcomes

Three 25,000,000-byte downloads per route were alternated, using:

```powershell
rtk proxy cmd.exe /c "curl.exe --ipv4 --interface <source-ip> --connect-timeout 10 --max-time 120 --output NUL --silent --show-error --write-out \"route=<route>-down run=<n> code=%{http_code} bytes=%{size_download} time=%{time_total} speed_Bps=%{speed_download}\n\" \"https://speed.cloudflare.com/__down?bytes=25000000\""
```

Three 25,000,000-byte synthetic-zero uploads per route were alternated, using:

```powershell
rtk proxy cmd.exe /c "powershell -NoProfile -Command \"$b = New-Object byte[] 25000000; [Console]::OpenStandardOutput().Write($b,0,$b.Length)\" | curl.exe --ipv4 --interface <source-ip> --connect-timeout 10 --max-time 120 --output NUL --silent --show-error --data-binary @- --write-out \"route=<route>-up run=<n> code=%{http_code} bytes=%{size_upload} time=%{time_total} speed_Bps=%{speed_upload}\n\" \"https://speed.cloudflare.com/__up\""
```

All twelve measured curl invocations exited `0`, returned HTTP `200`, and transferred exactly `25000000` bytes. A prior 10,000,000-byte BAFFALO upload validation also returned HTTP `200` (1.246334 seconds, 8023544 B/s); it is not included in the results below.

### 19.2 Results

Mbps is `speed_Bps * 8 / 1,000,000`; the bold figure is the median of the three valid samples.

| Bound route | Downlink runs (Mbps) | Downlink median | Uplink runs (Mbps) | Uplink median |
|---|---:|---:|---:|---:|
| BAFFALO, AX88179 USB 3.0 | 244.40, 575.11, 413.05 | **413.05 Mbps** | 132.25, 94.71, 113.63 | **113.63 Mbps** |
| OpenWrt, Realtek PCIe | 588.87, 520.08, 497.39 | **520.08 Mbps** | 96.10, 105.69, 101.11 | **101.11 Mbps** |

Raw results, in execution order:

```text
route=BUFFALO-down run=1 code=200 bytes=25000000 time=0.818326 speed_Bps=30550283
route=OpenWrt-down run=1 code=200 bytes=25000000 time=0.339637 speed_Bps=73608432
route=BUFFALO-down run=2 code=200 bytes=25000000 time=0.347763 speed_Bps=71888452
route=OpenWrt-down run=2 code=200 bytes=25000000 time=0.384558 speed_Bps=65010037
route=BUFFALO-down run=3 code=200 bytes=25000000 time=0.484200 speed_Bps=51631770
route=OpenWrt-down run=3 code=200 bytes=25000000 time=0.402098 speed_Bps=62174361
route=BUFFALO-up run=1 code=200 bytes=25000000 time=1.512274 speed_Bps=16531428
route=OpenWrt-up run=1 code=200 bytes=25000000 time=2.081247 speed_Bps=12012040
route=BUFFALO-up run=2 code=200 bytes=25000000 time=2.111795 speed_Bps=11838281
route=OpenWrt-up run=2 code=200 bytes=25000000 time=1.892336 speed_Bps=13211198
route=BUFFALO-up run=3 code=200 bytes=25000000 time=1.760111 speed_Bps=14203673
route=OpenWrt-up run=3 code=200 bytes=25000000 time=1.977992 speed_Bps=12639093
```

The two routes are not a strict router-only comparison because they use different PC NICs and the OpenWrt path traverses BAFFALO upstream. The sample sets show real internet throughput at this time, not a sustained-line-rate guarantee.
