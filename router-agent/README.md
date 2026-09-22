# router-agent

Phase 3B's first slice is a Rust CLI that emits one read-only JSON snapshot of
the local OpenWrt router. It has no listener, daemon, MCP server, UCI mutation,
subprocess execution, packet capture, or forwarding control.

On OpenWrt x86/64:

```sh
router-agent
router-agent --interface eth0 --interface br-lan
```

The snapshot contains the collection time, hostname, kernel release, uptime,
load average, memory total/available, all local IPv4 addresses, conntrack entry
count, and selected interface byte/packet/error/drop counters. Local IPv4
addresses are read from `/proc/net/fib_trie`; they are intentionally not labelled
with an interface in this first dependency-free slice. Missing scalar kernel
values are represented as JSON `null`; a snapshot still succeeds rather than
fabricating a value.

Only interface names matching `[A-Za-z0-9_.-]+` are accepted. This prevents a
CLI argument from escaping the intended `/sys/class/net/<name>/statistics`
directory. The default interfaces are `eth0` and `br-lan`.

Build a deployable static Linux binary from Windows:

```powershell
cargo build --release --target x86_64-unknown-linux-musl
```

The target must be installed first with `rustup target add
x86_64-unknown-linux-musl`. Deployment and service installation are deliberate
Phase 3B steps and are documented in `../phase3-monitoring.md`.
