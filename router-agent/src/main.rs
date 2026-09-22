use std::collections::BTreeSet;
use std::env;
use std::fs;
use std::net::Ipv4Addr;
use std::process;
use std::time::{SystemTime, UNIX_EPOCH};

const DEFAULT_INTERFACES: [&str; 2] = ["eth0", "br-lan"];

#[derive(Clone, Copy)]
struct InterfaceStats {
    rx_bytes: Option<u64>,
    tx_bytes: Option<u64>,
    rx_packets: Option<u64>,
    tx_packets: Option<u64>,
    rx_errors: Option<u64>,
    tx_errors: Option<u64>,
    rx_dropped: Option<u64>,
    tx_dropped: Option<u64>,
}

fn read_trimmed(path: &str) -> Option<String> {
    fs::read_to_string(path)
        .ok()
        .map(|value| value.trim().to_owned())
        .filter(|value| !value.is_empty())
}

fn read_u64(path: &str) -> Option<u64> {
    read_trimmed(path)?.parse().ok()
}

fn json_string(value: &str) -> String {
    let mut escaped = String::with_capacity(value.len() + 2);
    escaped.push('"');
    for character in value.chars() {
        match character {
            '"' => escaped.push_str("\\\""),
            '\\' => escaped.push_str("\\\\"),
            '\n' => escaped.push_str("\\n"),
            '\r' => escaped.push_str("\\r"),
            '\t' => escaped.push_str("\\t"),
            character if character.is_control() => {
                use std::fmt::Write;
                write!(&mut escaped, "\\u{:04x}", character as u32)
                    .expect("writing to String cannot fail");
            }
            character => escaped.push(character),
        }
    }
    escaped.push('"');
    escaped
}

fn json_option_u64(value: Option<u64>) -> String {
    value.map_or_else(|| "null".to_owned(), |number| number.to_string())
}

fn json_string_array(values: &[String]) -> String {
    let mut output = String::from("[");
    for (index, value) in values.iter().enumerate() {
        if index > 0 {
            output.push(',');
        }
        output.push_str(&json_string(value));
    }
    output.push(']');
    output
}

fn parse_uptime_seconds() -> Option<f64> {
    read_trimmed("/proc/uptime")?
        .split_whitespace()
        .next()?
        .parse()
        .ok()
}

fn parse_load_average() -> [Option<f64>; 3] {
    let mut values = [None; 3];
    if let Some(loadavg) = read_trimmed("/proc/loadavg") {
        for (slot, value) in values.iter_mut().zip(loadavg.split_whitespace()) {
            *slot = value.parse().ok();
        }
    }
    values
}

fn meminfo_kib(field: &str) -> Option<u64> {
    let prefix = format!("{field}:");
    read_trimmed("/proc/meminfo")?.lines().find_map(|line| {
        let value = line.strip_prefix(&prefix)?.split_whitespace().next()?;
        value.parse().ok()
    })
}

fn ipv4_local_addresses_from(fib_trie: &str) -> Vec<String> {
    let mut addresses = BTreeSet::new();
    let mut candidate = None;

    for line in fib_trie.lines() {
        let trimmed = line.trim_start();
        if let Some(address) = trimmed.strip_prefix("|-- ") {
            candidate = address
                .parse::<Ipv4Addr>()
                .ok()
                .map(|parsed| parsed.to_string());
        } else if trimmed.contains("host LOCAL") {
            if let Some(address) = candidate.take() {
                addresses.insert(address);
            }
        }
    }

    addresses.into_iter().collect()
}

fn ipv4_local_addresses() -> Vec<String> {
    read_trimmed("/proc/net/fib_trie")
        .map(|contents| ipv4_local_addresses_from(&contents))
        .unwrap_or_default()
}

fn valid_interface_name(name: &str) -> bool {
    !name.is_empty()
        && name.len() <= 15
        && name
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'.' | b'_' | b'-'))
}

fn parse_interfaces() -> Result<Vec<String>, String> {
    let mut interfaces = BTreeSet::new();
    let mut arguments = env::args().skip(1);
    while let Some(argument) = arguments.next() {
        if argument != "--interface" {
            return Err(format!("unknown argument: {argument}"));
        }
        let name = arguments
            .next()
            .ok_or_else(|| "--interface requires a name".to_owned())?;
        if !valid_interface_name(&name) {
            return Err(format!("invalid interface name: {name}"));
        }
        interfaces.insert(name);
    }

    if interfaces.is_empty() {
        interfaces.extend(DEFAULT_INTERFACES.into_iter().map(str::to_owned));
    }
    Ok(interfaces.into_iter().collect())
}

fn interface_stats(name: &str) -> InterfaceStats {
    let base = format!("/sys/class/net/{name}/statistics");
    let stat = |field: &str| read_u64(&format!("{base}/{field}"));
    InterfaceStats {
        rx_bytes: stat("rx_bytes"),
        tx_bytes: stat("tx_bytes"),
        rx_packets: stat("rx_packets"),
        tx_packets: stat("tx_packets"),
        rx_errors: stat("rx_errors"),
        tx_errors: stat("tx_errors"),
        rx_dropped: stat("rx_dropped"),
        tx_dropped: stat("tx_dropped"),
    }
}

fn main() {
    if !cfg!(target_os = "linux") {
        eprintln!("router-agent only runs on Linux/OpenWrt");
        process::exit(2);
    }

    let interfaces = parse_interfaces().unwrap_or_else(|message| {
        eprintln!("router-agent: {message}");
        process::exit(2);
    });
    let timestamp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_secs())
        .unwrap_or(0);
    let loads = parse_load_average();
    let ipv4_addresses = ipv4_local_addresses();
    let mut output = String::from("{");
    output.push_str("\"schema_version\":1,");
    output.push_str(&format!("\"collected_at_unix\":{timestamp},"));
    output.push_str(&format!(
        "\"hostname\":{},\"kernel_release\":{},",
        read_trimmed("/proc/sys/kernel/hostname")
            .map_or_else(|| "null".to_owned(), |value| json_string(&value)),
        read_trimmed("/proc/sys/kernel/osrelease")
            .map_or_else(|| "null".to_owned(), |value| json_string(&value)),
    ));
    output.push_str(&format!(
        "\"uptime_seconds\":{},\"load_average\":[{},{},{}],",
        parse_uptime_seconds().map_or_else(|| "null".to_owned(), |value| value.to_string()),
        loads[0].map_or_else(|| "null".to_owned(), |value| value.to_string()),
        loads[1].map_or_else(|| "null".to_owned(), |value| value.to_string()),
        loads[2].map_or_else(|| "null".to_owned(), |value| value.to_string()),
    ));
    output.push_str(&format!(
        "\"memory_kib\":{{\"total\":{},\"available\":{}}},",
        json_option_u64(meminfo_kib("MemTotal")),
        json_option_u64(meminfo_kib("MemAvailable")),
    ));
    output.push_str(&format!(
        "\"ipv4_local_addresses\":{},",
        json_string_array(&ipv4_addresses),
    ));
    output.push_str(&format!(
        "\"conntrack_entries\":{},\"interfaces\":[",
        json_option_u64(read_u64("/proc/sys/net/netfilter/nf_conntrack_count")),
    ));
    for (index, name) in interfaces.iter().enumerate() {
        if index > 0 {
            output.push(',');
        }
        let stats = interface_stats(name);
        output.push_str(&format!(
            "{{\"name\":{},\"rx_bytes\":{},\"tx_bytes\":{},\"rx_packets\":{},\"tx_packets\":{},\"rx_errors\":{},\"tx_errors\":{},\"rx_dropped\":{},\"tx_dropped\":{}}}",
            json_string(name),
            json_option_u64(stats.rx_bytes), json_option_u64(stats.tx_bytes),
            json_option_u64(stats.rx_packets), json_option_u64(stats.tx_packets),
            json_option_u64(stats.rx_errors), json_option_u64(stats.tx_errors),
            json_option_u64(stats.rx_dropped), json_option_u64(stats.tx_dropped),
        ));
    }
    output.push_str("]}");
    println!("{output}");
}

#[cfg(test)]
mod tests {
    use super::{ipv4_local_addresses_from, json_string, valid_interface_name};

    #[test]
    fn escapes_json_control_characters() {
        assert_eq!(json_string("a\"\\\n"), "\"a\\\"\\\\\\n\"");
    }

    #[test]
    fn accepts_only_safe_interface_names() {
        assert!(valid_interface_name("br-lan.10"));
        assert!(valid_interface_name("eth0"));
        assert!(!valid_interface_name("../../etc/passwd"));
        assert!(!valid_interface_name("eth0;id"));
    }

    #[test]
    fn extracts_unique_local_ipv4_addresses_only() {
        let fixture = r#"
            |-- 192.168.11.0
               /24 link UNICAST
            |-- 192.168.11.108
               /32 host LOCAL
            |-- 192.168.11.108
               /32 host LOCAL
            |-- 192.168.11.255
               /32 link BROADCAST
            |-- invalid
               /32 host LOCAL
        "#;
        assert_eq!(
            ipv4_local_addresses_from(fixture),
            vec!["192.168.11.108".to_owned()]
        );
    }
}
