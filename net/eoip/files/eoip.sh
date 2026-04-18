#!/bin/sh
. /lib/functions.sh
. /lib/netifd/netifd-proto.sh
init_proto "$@"

eoip_log() {
    logger -t "customfeed-eoip" "$*"
}

eoip_sysctl_set() {
    local path="$1"
    local value="$2"
    [ -n "$path" ] || return 0
    [ -n "$value" ] || return 0
    [ -w "$path" ] || return 0
    echo "$value" >"$path" 2>/dev/null || true
}

eoip_sync_hotplug_scripts() {
    local src dst

    for src in \
        /rom/etc/hotplug.d/iface/95-eoip-dhcp-default-route \
        /rom/etc/hotplug.d/iface/96-eoip-bridge-auto-mac
    do
        [ -r "$src" ] || continue
        dst="/etc/hotplug.d/iface/${src##*/}"
        if [ ! -r "$dst" ] || ! cmp -s "$src" "$dst"; then
            cp "$src" "$dst" >/dev/null 2>&1 || continue
            chmod 0755 "$dst" >/dev/null 2>&1 || true
        fi
    done

    src="/rom/etc/hotplug.d/net/96-eoip-bridge-auto-mac"
    [ -r "$src" ] || src="/rom/etc/hotplug.d/iface/96-eoip-bridge-auto-mac"
    if [ -r "$src" ]; then
        dst="/etc/hotplug.d/net/96-eoip-bridge-auto-mac"
        if [ ! -r "$dst" ] || ! cmp -s "$src" "$dst"; then
            mkdir -p /etc/hotplug.d/net >/dev/null 2>&1 || true
            cp "$src" "$dst" >/dev/null 2>&1 || true
            chmod 0755 "$dst" >/dev/null 2>&1 || true
        fi
    fi
}

eoip_mtu_diag() {
    local ifname="$1"
    local mtu_req="$2"
    local tunlink="$3"
    local mtu_cur mtu_under

    mtu_cur="$(cat /sys/class/net/$ifname/mtu 2>/dev/null)"
    if [ -n "$mtu_cur" ]; then
        eoip_log "mtu diag: ifname=$ifname requested=$mtu_req current=$mtu_cur"
        [ -n "$mtu_req" ] && [ "$mtu_cur" != "$mtu_req" ] && \
            eoip_log "mtu warning: ifname=$ifname requested=$mtu_req applied=$mtu_cur"
    else
        eoip_log "mtu warning: ifname=$ifname unable_to_read_current_mtu"
    fi

    if [ -n "$tunlink" ] && [ -d "/sys/class/net/$tunlink" ]; then
        mtu_under="$(cat /sys/class/net/$tunlink/mtu 2>/dev/null)"
        [ -n "$mtu_under" ] && eoip_log "mtu underlay: ifname=$ifname tunlink=$tunlink tunlink_mtu=$mtu_under"
        if [ -n "$mtu_cur" ] && [ -n "$mtu_under" ] && [ "$mtu_cur" -gt "$mtu_under" ] 2>/dev/null; then
            eoip_log "mtu warning: ifname=$ifname mtu=$mtu_cur > tunlink($tunlink)=$mtu_under (fragmentation likely)"
        fi
    fi
}

proto_eoip_init_config() {
    proto_config_add_string "ifname"
    proto_config_add_string "remote"
    proto_config_add_string "dst"
    proto_config_add_string "local"
    proto_config_add_string "src"
    proto_config_add_string "tunlink"
    proto_config_add_string "bridge"
    proto_config_add_int "id"
    proto_config_add_int "idtun"
    proto_config_add_string "mtu"
    proto_config_add_int "keepalive"
    proto_config_add_int "dscp"
    proto_config_add_boolean "df"
    proto_config_add_boolean "loop_protect"
    proto_config_add_int "loop_protect_disable_time"
    proto_config_add_int "loop_protect_send_interval"
    proto_config_add_boolean "clamp_tcp_mss"
    proto_config_add_boolean "allow_fast_path"
    proto_config_add_string "macaddr"
    proto_config_add_boolean "arp"
    proto_config_add_int "arp_timeout"
    proto_config_add_int "arp_ignore"
    proto_config_add_int "arp_announce"
    proto_config_add_boolean "arp_accept"
    proto_config_add_boolean "arp_filter"
    proto_config_add_boolean "arp_notify"
    proto_config_add_int "arp_base_reachable_time_ms"
    proto_config_add_int "arp_retrans_time_ms"
    proto_config_add_boolean "dynamic"
    proto_config_add_string "vlan"
    no_device=1
    available=1
}

eoip_apply_tcpmss_clamp() {
    local ifname="$1"
    command -v iptables >/dev/null 2>&1 || return 0

    iptables -w -t mangle -C FORWARD -o "$ifname" -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null || \
        iptables -w -t mangle -A FORWARD -o "$ifname" -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null || true
    iptables -w -t mangle -C FORWARD -i "$ifname" -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null || \
        iptables -w -t mangle -A FORWARD -i "$ifname" -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null || true
}

eoip_remove_tcpmss_clamp() {
    local ifname="$1"
    command -v iptables >/dev/null 2>&1 || return 0

    while iptables -w -t mangle -C FORWARD -o "$ifname" -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null; do
        iptables -w -t mangle -D FORWARD -o "$ifname" -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null || break
    done
    while iptables -w -t mangle -C FORWARD -i "$ifname" -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null; do
        iptables -w -t mangle -D FORWARD -i "$ifname" -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null || break
    done
}

proto_eoip_add_vlan() {
    local vid="$1"
    local ifname="$2"

    case "$vid" in
        ''|*[!0-9]*)
            return
        ;;
    esac

    [ "$vid" -ge 1 ] 2>/dev/null || return
    [ "$vid" -le 4094 ] 2>/dev/null || return

    ip link show "$ifname.$vid" >/dev/null 2>&1 || \
        ip link add link "$ifname" name "$ifname.$vid" type vlan id "$vid" 2>/dev/null
    ip link set dev "$ifname.$vid" up 2>/dev/null || true
}

proto_eoip_del_vlan() {
    local vid="$1"
    local ifname="$2"

    case "$vid" in
        ''|*[!0-9]*)
            return
        ;;
    esac

    ip link delete "$ifname.$vid" 2>/dev/null || true
}

eoip_ifname_state_file() {
    local cfg="$1"
    echo "/var/run/eoip.${cfg}.ifname"
}

eoip_pick_ifname() {
    local base="${1:-eoip}"
    local idx=0
    local cand

    while [ "$idx" -lt 4096 ]; do
        cand="${base}${idx}"
        if ! ip link show dev "$cand" >/dev/null 2>&1; then
            echo "$cand"
            return 0
        fi
        idx=$((idx + 1))
    done

    echo "${base}$$"
    return 0
}

eoip_select_ifname() {
    local cfg="$1"
    local configured="$2"
    local state_file cached picked

    [ -n "$configured" ] && {
        echo "$configured"
        return 0
    }

    state_file="$(eoip_ifname_state_file "$cfg")"
    if [ -f "$state_file" ]; then
        cached="$(cat "$state_file" 2>/dev/null)"
        [ -n "$cached" ] && {
            echo "$cached"
            return 0
        }
    fi

    picked="$(eoip_pick_ifname eoip)"
    echo "$picked" > "$state_file"
    # Persist auto-generated name so LuCI can list the device
    # (important on 18.06 where runtime-only names are often hidden).
    if command -v uci >/dev/null 2>&1; then
        uci -q set "network.${cfg}.ifname=${picked}"
        uci -q commit network
    fi
    echo "$picked"
    return 0
}

proto_eoip_setup() {
    local config="$1"
    local ifname remote dst local src tunlink bridge id idtun mtu dynamic
    local keepalive dscp df macaddr arp arp_timeout
    local loop_protect loop_protect_disable_time loop_protect_send_interval
    local clamp_tcp_mss allow_fast_path
    local arp_ignore arp_announce arp_accept arp_filter arp_notify
    local arp_base_reachable_time_ms arp_retrans_time_ms
    local vlan_list vid

    eoip_sync_hotplug_scripts

    json_get_vars ifname remote dst local src tunlink bridge id idtun mtu dynamic
    json_get_vars keepalive dscp df macaddr arp arp_timeout
    json_get_vars loop_protect loop_protect_disable_time loop_protect_send_interval
    json_get_vars clamp_tcp_mss allow_fast_path
    json_get_vars arp_ignore arp_announce arp_accept arp_filter arp_notify
    json_get_vars arp_base_reachable_time_ms arp_retrans_time_ms
    json_get_values vlan_list vlan

    ifname="$(eoip_select_ifname "$config" "$ifname")"
    [ -z "$remote" ] && remote="$dst"
    [ -z "$local" ] && local="$src"
    [ -z "$id" ] && id="$idtun"
    [ -z "$mtu" ] && mtu=1458
    [ -z "$keepalive" ] && keepalive=10
    [ -z "$dscp" ] && dscp=-1
    [ "$df" = "1" ] || df=0
    [ "$loop_protect" = "1" ] || loop_protect=0
    [ -z "$loop_protect_disable_time" ] && loop_protect_disable_time=5
    [ -z "$loop_protect_send_interval" ] && loop_protect_send_interval=5
    [ "$clamp_tcp_mss" = "0" ] && clamp_tcp_mss=0 || clamp_tcp_mss=1
    [ "$allow_fast_path" = "0" ] && allow_fast_path=0 || allow_fast_path=1
    [ "$arp" = "0" ] || arp=1
    [ -z "$arp_timeout" ] && arp_timeout=0
    [ -z "$arp_ignore" ] && arp_ignore=-1
    [ -z "$arp_announce" ] && arp_announce=-1
    [ -z "$arp_accept" ] && arp_accept=""
    [ -z "$arp_filter" ] && arp_filter=""
    [ -z "$arp_notify" ] && arp_notify=""
    [ -z "$arp_base_reachable_time_ms" ] && arp_base_reachable_time_ms=0
    [ -z "$arp_retrans_time_ms" ] && arp_retrans_time_ms=0
    [ "$dynamic" = "1" ] || dynamic=0
    [ "$tunlink" = "none" ] && tunlink=""

    [ -z "$remote" ] || [ -z "$id" ] && {
        eoip_log "setup failed: section=$config reason=missing remote/id remote='$remote' id='$id'"
        proto_notify_error "$config" "EOIP_MISSING_REMOTE_OR_ID"
        proto_setup_failed "$config"
        return 1
    }

    eoip_log "setup start: section=$config ifname=$ifname remote=$remote local=${local:-auto} id=$id dynamic=$dynamic tunlink=${tunlink:-auto} bridge=${bridge:-none} mtu=${mtu:-auto} keepalive=$keepalive dscp=$dscp df=$df loop_protect=$loop_protect clamp_tcp_mss=$clamp_tcp_mss allow_fast_path=$allow_fast_path arp=$arp"

    if ! command -v /usr/bin/eoip >/dev/null 2>&1; then
        eoip_log "setup failed: section=$config reason=missing /usr/bin/eoip binary"
        proto_notify_error "$config" "EOIP_BINARY_NOT_FOUND"
        proto_setup_failed "$config"
        return 1
    fi

    if ! proto_run_command "$config" /usr/bin/eoip "$ifname" "$id" "$remote" "$dynamic" "$local" "$tunlink" "$keepalive" "$dscp" "$df" "$loop_protect" "$loop_protect_disable_time" "$loop_protect_send_interval"; then
        eoip_log "setup failed: section=$config reason=eoip command start failure"
        proto_notify_error "$config" "EOIP_COMMAND_FAILED"
        proto_setup_failed "$config"
        return 1
    fi

    if [ -n "$mtu" ] && [ "$mtu" != "auto" ]; then
        ip link set dev "$ifname" mtu "$mtu" 2>/dev/null || true
    fi
    if [ -n "$macaddr" ]; then
        ip link set dev "$ifname" address "$macaddr" 2>/dev/null || true
    fi
    if [ "$arp" = "1" ]; then
        ip link set dev "$ifname" arp on 2>/dev/null || true
    else
        ip link set dev "$ifname" arp off 2>/dev/null || true
    fi
    if [ "$arp_timeout" -gt 0 ] 2>/dev/null; then
        eoip_sysctl_set "/proc/sys/net/ipv4/neigh/$ifname/gc_stale_time" "$arp_timeout"
    fi
    if [ "$arp_ignore" -ge 0 ] 2>/dev/null; then
        eoip_sysctl_set "/proc/sys/net/ipv4/conf/$ifname/arp_ignore" "$arp_ignore"
    fi
    if [ "$arp_announce" -ge 0 ] 2>/dev/null; then
        eoip_sysctl_set "/proc/sys/net/ipv4/conf/$ifname/arp_announce" "$arp_announce"
    fi
    if [ -n "$arp_accept" ]; then
        eoip_sysctl_set "/proc/sys/net/ipv4/conf/$ifname/arp_accept" "$arp_accept"
    fi
    if [ -n "$arp_filter" ]; then
        eoip_sysctl_set "/proc/sys/net/ipv4/conf/$ifname/arp_filter" "$arp_filter"
    fi
    if [ -n "$arp_notify" ]; then
        eoip_sysctl_set "/proc/sys/net/ipv4/conf/$ifname/arp_notify" "$arp_notify"
    fi
    if [ "$arp_base_reachable_time_ms" -gt 0 ] 2>/dev/null; then
        eoip_sysctl_set "/proc/sys/net/ipv4/neigh/$ifname/base_reachable_time_ms" "$arp_base_reachable_time_ms"
    fi
    if [ "$arp_retrans_time_ms" -gt 0 ] 2>/dev/null; then
        eoip_sysctl_set "/proc/sys/net/ipv4/neigh/$ifname/retrans_time_ms" "$arp_retrans_time_ms"
    fi
    if [ "$clamp_tcp_mss" = "1" ]; then
        eoip_apply_tcpmss_clamp "$ifname"
    else
        eoip_remove_tcpmss_clamp "$ifname"
    fi
    if [ "$allow_fast_path" = "1" ]; then
        eoip_log "allow_fast_path requested: no direct Linux equivalent, keeping fast path as kernel/default behavior"
    fi
    [ -n "$bridge" ] && ip link set dev "$ifname" master "$bridge" 2>/dev/null || true
    for vid in $vlan_list; do
        proto_eoip_add_vlan "$vid" "$ifname"
    done

    if ! ip link show "$ifname" >/dev/null 2>&1; then
        eoip_log "setup failed: section=$config reason=device_not_created ifname=$ifname"
        proto_notify_error "$config" "EOIP_DEVICE_NOT_CREATED"
        proto_setup_failed "$config"
        return 1
    fi
    eoip_mtu_diag "$ifname" "$mtu" "$tunlink"

    proto_init_update "$ifname" 1
    proto_send_update "$config"
    eoip_log "setup done: section=$config ifname=$ifname"
}

proto_eoip_teardown() {
    local config="$1"
    local ifname
    local clamp_tcp_mss
    local vlan_list vid

    json_get_var ifname ifname
    json_get_var clamp_tcp_mss clamp_tcp_mss
    json_get_values vlan_list vlan
    [ -z "$ifname" ] && ifname="$(cat "$(eoip_ifname_state_file "$config")" 2>/dev/null)"
    [ -z "$ifname" ] && ifname="eoip-${config}"

    eoip_log "teardown: section=$config ifname=$ifname"
    for vid in $vlan_list; do
        proto_eoip_del_vlan "$vid" "$ifname"
    done
    [ "$clamp_tcp_mss" = "1" ] && eoip_remove_tcpmss_clamp "$ifname"
    proto_kill_command "$config"
    ip link delete "$ifname" 2>/dev/null || true
    rm -f "$(eoip_ifname_state_file "$config")"
}

add_protocol eoip
