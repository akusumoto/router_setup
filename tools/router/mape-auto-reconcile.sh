#!/bin/sh
# Reconcile a static OCN MAP-E interface after WAN/WAN6 link events.
#
# The direct OCN path on this line supplies a global /64 but no DHCPv6-PD or
# Softwire46 rule.  The script derives a /64 PD from the observed wan6 address,
# passes it explicitly to OpenWrt mapcalc, and only then starts MAP-E.
#
# It must not activate behind BUFFALO: a DHCPv4 address on wan is the guard.

PATH=/usr/sbin:/usr/bin:/sbin:/bin
LOCK=/tmp/mape-auto-reconcile.lock
DELAY_SECONDS=10
SECTION=mape_auto
ICMP_INCLUDE=mape_auto_icmp
ICMP_FILE=/etc/mape-auto-icmp.nft
WAN=wan
WAN6=wan6
BASE_RULE='type=map-e,ipv6prefix=2400:4050:8000::,prefix6len=33,ipv4prefix=153.242.0.0,prefix4len=15,ealen=23,offset=6,br=2001:380:a120::9'

mkdir "$LOCK" 2>/dev/null || exit 0
trap 'rmdir "$LOCK"' EXIT HUP INT TERM

# Allow DHCPv4 and DHCPv6 to settle; this avoids a short MAP-E activation
# during normal BUFFALO startup when wan6 appears before the DHCPv4 lease.
sleep "$DELAY_SECONDS"

remove_static_map() {
    reason="$1"
    if uci -q get firewall."$ICMP_INCLUDE" >/dev/null; then
        uci -q delete firewall."$ICMP_INCLUDE"
        rm -f "$ICMP_FILE"
        uci commit firewall
        /etc/init.d/firewall reload
    fi
    if uci -q get network."$SECTION" >/dev/null; then
        logger -t mape-auto "$reason; removing MAP-E interface"
        ifdown "$SECTION" 2>/dev/null
        uci -q delete network."$SECTION"
        uci -q del_list firewall.@zone[1].network="$SECTION"
        uci commit network
        uci commit firewall
    fi
}

wan_ipv4="$(ubus call network.interface."$WAN" status 2>/dev/null | jsonfilter -e '@["ipv4-address"][0].address')"
if [ -n "$wan_ipv4" ]; then
    remove_static_map "wan has IPv4 $wan_ipv4"
    exit 0
fi

dynamic_map_up="$(ifstatus wan6_4 2>/dev/null | jsonfilter -e '@.up' 2>/dev/null)"
if [ "$dynamic_map_up" = true ]; then
    remove_static_map 'DHCPv6-provided wan6_4 is up'
    exit 0
fi

wan6_ipv6="$(ubus call network.interface."$WAN6" status 2>/dev/null | jsonfilter -e '@["ipv6-address"][0].address')"
[ -n "$wan6_ipv6" ] || exit 0

# Only the locally verified OCN /33 rule is allowed. A new provider allocation
# is a safe stop, not a reason to try a neighboring rule.
case "$wan6_ipv6" in
    2400:4050:[89aAbBcCdDeEfF]*:*) ;;
    *)
        logger -t mape-auto "no verified MAP-E rule for wan6=$wan6_ipv6"
        exit 0
        ;;
esac

old_ifs="$IFS"
IFS=:
set -- $wan6_ipv6
IFS="$old_ifs"
[ $# -ge 4 ] || exit 0
pd="$1:$2:$3:$4::"
rule="$BASE_RULE,pd=$pd,pdlen=64"

# The observed BR uses the legacy CE address layout. Validate that same
# layout here and configure netifd consistently below.
rule_data="$(LEGACY=1 mapcalc "$WAN6" "$rule" 2>&1)"
if [ $? -ne 0 ] || ! printf '%s\n' "$rule_data" | grep -q '^RULE_BMR=1$'; then
    logger -t mape-auto "mapcalc rejected observed wan6=$wan6_ipv6"
    exit 0
fi

# fw4 skips MAP's ICMP SNAT entries because they specify a port range.
# nftables itself can translate echo identifiers; use the first allocated
# range, calculated from the current prefix, before ordinary WAN masquerade.
map_ipv4="$(printf '%s\n' "$rule_data" | sed -n 's/^RULE_1_IPV4ADDR=//p')"
portsets="$(printf '%s\n' "$rule_data" | sed -n "s/^RULE_1_PORTSETS='\(.*\)'$/\1/p")"
icmp_ports="${portsets%% *}"
if ! printf '%s\n' "$map_ipv4" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' ||
    ! printf '%s\n' "$icmp_ports" | grep -Eq '^[0-9]+-[0-9]+$'; then
    logger -t mape-auto 'mapcalc omitted valid IPv4/port sets; refusing activation'
    exit 1
fi
icmp_rule="meta nfproto ipv4 oifname \"map-$SECTION\" icmp type echo-request counter snat ip to $map_ipv4:$icmp_ports comment \"mape-auto ICMP identifiers\""
firewall_changed=0
if [ "$(cat "$ICMP_FILE" 2>/dev/null)" != "$icmp_rule" ]; then
    printf '%s\n' "$icmp_rule" > "$ICMP_FILE"
    firewall_changed=1
fi
if [ "$(uci -q get firewall."$ICMP_INCLUDE".path)" != "$ICMP_FILE" ] ||
    [ "$(uci -q get firewall."$ICMP_INCLUDE".type)" != nftables ] ||
    [ "$(uci -q get firewall."$ICMP_INCLUDE".position)" != chain-prepend ] ||
    [ "$(uci -q get firewall."$ICMP_INCLUDE".chain)" != srcnat ]; then
    uci set firewall."$ICMP_INCLUDE"='include'
    uci set firewall."$ICMP_INCLUDE".type='nftables'
    uci set firewall."$ICMP_INCLUDE".path="$ICMP_FILE"
    uci set firewall."$ICMP_INCLUDE".position='chain-prepend'
    uci set firewall."$ICMP_INCLUDE".chain='srcnat'
    uci commit firewall
    firewall_changed=1
fi
if [ "$firewall_changed" = 1 ]; then
    fw4 check || exit 1
    /etc/init.d/firewall reload || exit 1
fi

old_rule="$(uci -q get network."$SECTION".rule)"
if [ "$old_rule" = "$rule" ] &&
    [ "$(uci -q get network."$SECTION".legacymap)" = 1 ] &&
    [ "$(uci -q get network."$SECTION".encaplimit)" = ignore ] &&
    ifstatus "$SECTION" 2>/dev/null | jsonfilter -e '@.up' | grep -qx true; then
    exit 0
fi

logger -t mape-auto "activating MAP-E from observed wan6=$wan6_ipv6 pd=$pd"
ifdown "$SECTION" 2>/dev/null
uci set network."$SECTION"='interface'
uci set network."$SECTION".proto='map'
uci set network."$SECTION".maptype='map-e'
uci set network."$SECTION".tunlink="$WAN6"
uci set network."$SECTION".zone='wan'
uci set network."$SECTION".rule="$rule"
uci set network."$SECTION".legacymap='1'
uci set network."$SECTION".encaplimit='ignore'
uci -q del_list firewall.@zone[1].network="$SECTION"
uci add_list firewall.@zone[1].network="$SECTION"
uci commit network
uci commit firewall
ifup "$SECTION"
