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
