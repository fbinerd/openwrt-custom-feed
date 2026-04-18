#!/bin/sh

[ -n "$INCLUDE_ONLY" ] || {
	. /lib/functions.sh
	. /lib/functions/network.sh
	. ../netifd-proto.sh
	init_proto "$@"
}

vxlan_sync_hotplug_scripts() {
	local src dst

	# Keep iface hooks synced from /rom.
	for src in \
		/rom/etc/hotplug.d/iface/95-vxlan-dhcp-default-route \
		/rom/etc/hotplug.d/iface/96-vxlan-bridge-auto-mac
	do
		[ -r "$src" ] || continue
		dst="/etc/hotplug.d/iface/${src##*/}"
		if [ ! -r "$dst" ] || ! cmp -s "$src" "$dst"; then
			cp "$src" "$dst" >/dev/null 2>&1 || continue
			chmod 0755 "$dst" >/dev/null 2>&1 || true
		fi
	done

	# Mirror bridge auto-MAC hook under /etc/hotplug.d/net too.
	# Some reload/apply flows trigger net events earlier than iface.
	src="/rom/etc/hotplug.d/net/96-vxlan-bridge-auto-mac"
	[ -r "$src" ] || src="/rom/etc/hotplug.d/iface/96-vxlan-bridge-auto-mac"
	if [ -r "$src" ]; then
		dst="/etc/hotplug.d/net/96-vxlan-bridge-auto-mac"
		if [ ! -r "$dst" ] || ! cmp -s "$src" "$dst"; then
			mkdir -p /etc/hotplug.d/net >/dev/null 2>&1 || true
			cp "$src" "$dst" >/dev/null 2>&1 || true
			chmod 0755 "$dst" >/dev/null 2>&1 || true
		fi
	fi
}

vxlan_generic_setup() {
	local cfg="$1"
	local mode="$2"
	local local="$3"
	local remote="$4"

	local link="$cfg"
	local ifname
	json_get_var ifname ifname
	link="$(vxlan_select_ifname "$cfg" "$ifname")"

	vxlan_prepare_link "$cfg" "$link"

	local port vid ttl tos mtu macaddr zone rxcsum txcsum
	json_get_vars port vid ttl tos mtu macaddr zone rxcsum txcsum


	proto_init_update "$link" 1

	proto_add_tunnel
	json_add_string mode "$mode"

	[ -n "$tunlink" ] && json_add_string link "$tunlink"
	[ -n "$local" ] && json_add_string local "$local"
	[ -n "$remote" ] && json_add_string remote "$remote"

	[ -n "$ttl" ] && json_add_int ttl "$ttl"
	[ -n "$tos" ] && json_add_string tos "$tos"
	[ -n "$mtu" ] && json_add_int mtu "$mtu"

	json_add_object 'data'
	[ -n "$port" ] && json_add_int port "$port"
	[ -n "$vid" ] && json_add_int id "$vid"
	[ -n "$macaddr" ] && json_add_string macaddr "$macaddr"
	[ -n "$rxcsum" ] && json_add_boolean rxcsum "$rxcsum"
	[ -n "$txcsum" ] && json_add_boolean txcsum "$txcsum"
	json_close_object

	proto_close_tunnel

	proto_add_data
	[ -n "$zone" ] && json_add_string zone "$zone"
	proto_close_data

	proto_send_update "$cfg"

	vxlan_vlan_create_from_uci "$cfg" "$link"
}

vxlan_prepare_link() {
	local cfg="$1"
	local link="$2"
	local tries=0

	[ -n "$link" ] || return 0
	command -v ip >/dev/null 2>&1 || return 0

	# If a stale vxlan device remained from a failed setup/restart,
	# remove it first to avoid "duplicate VNI" errors on re-create.
	if ip link show dev "$link" >/dev/null 2>&1; then
		ip link del dev "$link" >/dev/null 2>&1 || true

		while [ "$tries" -lt 10 ]; do
			ip link show dev "$link" >/dev/null 2>&1 || break
			tries=$((tries + 1))
			sleep 1
		done
	fi
}

proto_vxlan_setup() {
	local cfg="$1"

	vxlan_sync_hotplug_scripts

	local ipaddr peeraddr
	json_get_vars ipaddr peeraddr tunlink
	[ "$tunlink" = "none" ] && tunlink=""

	[ -z "$peeraddr" ] && {
		proto_notify_error "$cfg" "MISSING_ADDRESS"
		proto_block_restart "$cfg"
		exit
	}

	( proto_add_host_dependency "$cfg" '' "$tunlink" )

	[ -z "$ipaddr" ] && {
		local wanif="$tunlink"
		if [ -z "$wanif" ] && ! network_find_wan wanif; then
			proto_notify_error "$cfg" "NO_WAN_LINK"
			exit
		fi

		if ! network_get_ipaddr ipaddr "$wanif"; then
			proto_notify_error "$cfg" "NO_WAN_LINK"
			exit
		fi
	}

	vxlan_generic_setup "$cfg" 'vxlan' "$ipaddr" "$peeraddr"
}

proto_vxlan6_setup() {
	local cfg="$1"

	vxlan_sync_hotplug_scripts

	local ip6addr peer6addr
	json_get_vars ip6addr peer6addr tunlink
	[ "$tunlink" = "none" ] && tunlink=""

	[ -z "$peer6addr" ] && {
		proto_notify_error "$cfg" "MISSING_ADDRESS"
		proto_block_restart "$cfg"
		exit
	}

	( proto_add_host_dependency "$cfg" '' "$tunlink" )

	[ -z "$ip6addr" ] && {
		local wanif="$tunlink"
		if [ -z "$wanif" ] && ! network_find_wan6 wanif; then
			proto_notify_error "$cfg" "NO_WAN_LINK"
			exit
		fi

		if ! network_get_ipaddr6 ip6addr "$wanif"; then
			proto_notify_error "$cfg" "NO_WAN_LINK"
			exit
		fi
	}

	vxlan_generic_setup "$cfg" 'vxlan6' "$ip6addr" "$peer6addr"
}

proto_vxlan_teardown() {
	local cfg="$1"
	rm -f "$(vxlan_ifname_state_file "$cfg")"
	vxlan_vlan_cleanup "$cfg"
}

proto_vxlan6_teardown() {
	local cfg="$1"
	rm -f "$(vxlan_ifname_state_file "$cfg")"
	vxlan_vlan_cleanup "$cfg"
}

vxlan_generic_init_config() {
	no_device=1
	available=1

	proto_config_add_string "ifname"
	proto_config_add_string "tunlink"
	proto_config_add_string "zone"

	proto_config_add_int "vid"
	proto_config_add_int "port"
	proto_config_add_int "ttl"
	proto_config_add_int "tos"
	proto_config_add_int "mtu"
	proto_config_add_string "macaddr"
	proto_config_add_string "vlan"
}

vxlan_pick_ifname() {
	local base="${1:-vxlan}"
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

vxlan_ifname_state_file() {
	local cfg="$1"
	echo "/var/run/vxlan.${cfg}.ifname"
}

vxlan_select_ifname() {
	local cfg="$1"
	local configured="$2"
	local state_file cached picked

	[ -n "$configured" ] && {
		echo "$configured"
		return 0
	}

	state_file="$(vxlan_ifname_state_file "$cfg")"
	if [ -f "$state_file" ]; then
		cached="$(cat "$state_file" 2>/dev/null)"
		[ -n "$cached" ] && {
			echo "$cached"
			return 0
		}
	fi

	picked="$(vxlan_pick_ifname vxlan)"
	echo "$picked" > "$state_file"
	echo "$picked"
	return 0
}

vxlan_vlan_state_file() {
	local cfg="$1"
	echo "/var/run/vxlan.${cfg}.vlans"
}

vxlan_wait_link() {
	local dev="$1"
	local tries=0

	while [ "$tries" -lt 10 ]; do
		ip link show dev "$dev" >/dev/null 2>&1 && return 0
		tries=$((tries + 1))
		sleep 1
	done

	return 1
}

vxlan_vlan_create_from_uci() {
	local cfg="$1"
	local parent="$2"
	local vlan_raw
	[ -n "$cfg" ] || return 0
	[ -n "$parent" ] || return 0
	command -v ip >/dev/null 2>&1 || return 0
	vxlan_wait_link "$parent" || return 0

	config_load network
	vxlan_vlan_cleanup "$cfg"
	config_list_foreach "$cfg" vlan vxlan_vlan_add_from_list "$cfg" "$parent"

	# Fallback for legacy UCI where VLAN IDs were persisted as plain string
	# instead of proper list values (e.g. "15 44" or "15,44").
	config_get vlan_raw "$cfg" vlan
	if [ -n "$vlan_raw" ]; then
		vlan_raw="${vlan_raw//,/ }"
		for vid in $vlan_raw; do
			vxlan_vlan_add_from_list "$vid" "$cfg" "$parent"
		done
	fi
}

vxlan_vlan_add_from_list() {
	local vid="$1"
	local cfg="$2"
	local parent="$3"
	local state_file
	local vdev

	case "$vid" in
		""|*[!0-9]*)
			return 0
		;;
	esac
	[ "$vid" -ge 1 ] 2>/dev/null || return 0
	[ "$vid" -le 4094 ] 2>/dev/null || return 0

	vxlan_wait_link "$parent" || return 0

	vdev="${parent}.${vid}"
	if ! ip link show dev "$vdev" >/dev/null 2>&1; then
		ip link add link "$parent" name "$vdev" type vlan id "$vid" >/dev/null 2>&1 || return 0
	fi
	ip link set dev "$vdev" up >/dev/null 2>&1

	state_file="$(vxlan_vlan_state_file "$cfg")"
	grep -qxF "$vdev" "$state_file" 2>/dev/null || echo "$vdev" >> "$state_file"

	vxlan_ifup_dependents "$cfg" "$vdev"
}

vxlan_ifup_dependents_cb() {
	local sec="$1"
	local owner="$2"
	local dev="$3"
	local proto ifname auto defaultroute

	[ "$sec" = "$owner" ] && return 0

	vxlan_cfg_get proto "$sec" proto
	case "$proto" in
		vxlan|vxlan6)
			return 0
		;;
	esac

	vxlan_cfg_get ifname "$sec" ifname
	[ -n "$ifname" ] || return 0
	vxlan_ifname_has_member "$ifname" "$dev" || return 0

	vxlan_bridge_autoset_mac "$sec" "$dev"
	if [ "$proto" = "dhcp" ]; then
		vxlan_cfg_get defaultroute "$sec" defaultroute
		if [ -z "$defaultroute" ] && command -v uci >/dev/null 2>&1; then
			uci -q set "network.${sec}.defaultroute=0"
			uci -q commit network
		fi
	fi
	vxlan_cfg_get_bool auto "$sec" auto 1
	[ "$auto" -eq 1 ] || return 0
	(
		sleep 2
		ifup "$sec" >/dev/null 2>&1
	) &
}

vxlan_ifname_has_member() {
	local ifname="$1"
	local dev="$2"
	local member

	for member in $ifname; do
		[ "$member" = "$dev" ] && return 0
		case "$member" in
			"$dev".*)
				return 0
			;;
		esac
	done

	return 1
}

vxlan_bridge_autoset_mac() {
	local sec="$1"
	local dev="$2"
	local type ifname mac newmac brdev

	vxlan_cfg_get type "$sec" type
	[ "$type" = "bridge" ] || return 0

	vxlan_cfg_get ifname "$sec" ifname
	[ -n "$ifname" ] || return 0
	vxlan_ifname_has_member "$ifname" "$dev" || return 0

	vxlan_cfg_get mac "$sec" macaddr
	[ -n "$mac" ] && return 0

	newmac="$(vxlan_gen_unique_mac "$sec")"
	[ -n "$newmac" ] || return 0

	uci -q set "network.${sec}.macaddr=$newmac"
	uci -q commit network

	# Apply immediately to the live bridge device if available.
	brdev="br-$sec"
	if ! ip link show dev "$brdev" >/dev/null 2>&1; then
		brdev="$(ifstatus "$sec" 2>/dev/null | jsonfilter -e '@.l3_device' 2>/dev/null)"
		[ -n "$brdev" ] || brdev="$(ifstatus "$sec" 2>/dev/null | jsonfilter -e '@.device' 2>/dev/null)"
	fi
	if [ -n "$brdev" ] && ip link show dev "$brdev" >/dev/null 2>&1; then
		ip link set dev "$brdev" address "$newmac" >/dev/null 2>&1 || true
	fi
}

vxlan_mac_exists_runtime() {
	local mac="$(echo "$1" | tr 'A-F' 'a-f')"
	ip link show 2>/dev/null | awk '/link\/ether/ {print tolower($2)}' | grep -qx "$mac"
}

vxlan_mac_exists_uci_other() {
	local mac="$(echo "$1" | tr 'A-F' 'a-f')"
	local exclude="$2"
	uci -q show network 2>/dev/null | \
		sed -n "s/^network\.\([^.]*\)\.macaddr='\([^']*\)'/\1 \2/p" | \
		awk -v m="$mac" -v e="$exclude" '{ if ($1 != e && tolower($2) == m) { found=1 } } END { exit(found ? 0 : 1) }'
}

vxlan_mac_is_valid() {
	echo "$1" | tr 'A-F' 'a-f' | grep -Eq '^[0-9a-f]{2}(:[0-9a-f]{2}){5}$'
}

vxlan_mac_is_zero() {
	[ "$(echo "$1" | tr 'A-F' 'a-f')" = "00:00:00:00:00:00" ]
}

vxlan_mac_is_unicast() {
	local mac="$1"
	local first
	vxlan_mac_is_valid "$mac" || return 1
	first="${mac%%:*}"
	first=$((0x$first))
	[ $((first & 0x01)) -eq 0 ]
}

vxlan_mac_is_laa_unicast() {
	local mac="$1"
	local first
	echo "$mac" | grep -Eq '^[0-9a-fA-F]{2}(:[0-9a-fA-F]{2}){5}$' || return 1
	first="${mac%%:*}"
	first=$((0x$first))
	[ $((first & 0x01)) -eq 0 ] && [ $((first & 0x02)) -ne 0 ]
}

vxlan_get_runtime_bridge_mac() {
	local sec="$1"
	local brdev
	brdev="br-$sec"
	if ip link show dev "$brdev" >/dev/null 2>&1; then
		ip link show dev "$brdev" 2>/dev/null | awk '/link\/ether/ {print tolower($2); exit}'
		return 0
	fi

	brdev="$(ifstatus "$sec" 2>/dev/null | jsonfilter -e '@.l3_device' 2>/dev/null)"
	[ -n "$brdev" ] || brdev="$(ifstatus "$sec" 2>/dev/null | jsonfilter -e '@.device' 2>/dev/null)"
	[ -n "$brdev" ] || return 1
	ip link show dev "$brdev" 2>/dev/null | awk '/link\/ether/ {print tolower($2); exit}'
}

vxlan_get_router_mac() {
	local dev mac lan_ifname

	for dev in eth0 eth1 br-lan br-wan wlan0; do
		[ -r "/sys/class/net/$dev/address" ] || continue
		mac="$(cat "/sys/class/net/$dev/address" 2>/dev/null | tr 'A-F' 'a-f')"
		vxlan_mac_is_valid "$mac" || continue
		vxlan_mac_is_zero "$mac" && continue
		vxlan_mac_is_unicast "$mac" || continue
		echo "$mac"
		return 0
	done

	lan_ifname="$(uci -q get network.lan.ifname 2>/dev/null)"
	for dev in $lan_ifname; do
		[ -r "/sys/class/net/$dev/address" ] || continue
		mac="$(cat "/sys/class/net/$dev/address" 2>/dev/null | tr 'A-F' 'a-f')"
		vxlan_mac_is_valid "$mac" || continue
		vxlan_mac_is_zero "$mac" && continue
		vxlan_mac_is_unicast "$mac" || continue
		echo "$mac"
		return 0
	done

	return 1
}

vxlan_find_base_mac() {
	vxlan_get_router_mac
}

vxlan_gen_unique_mac() {
	local sec="$1"
	local base
	local b1 b2 b3 b4 b5 b6
	local o1 o2 o3 o4 o5 o6 cand i

	base="$(vxlan_find_base_mac "$sec" | tr 'A-F' 'a-f')"
	vxlan_mac_is_valid "$base" || return 1
	vxlan_mac_is_zero "$base" && return 1
	vxlan_mac_is_unicast "$base" || return 1

	IFS=':' read -r b1 b2 b3 b4 b5 b6 <<EOF
$base
EOF
	o1=$((0x$b1))
	o2=$((0x$b2))
	o3=$((0x$b3))
	o4=$((0x$b4))
	o5=$((0x$b5))
	o6=$((0x$b6))

	i=1
	while [ "$i" -le 2048 ]; do
		o6=$(( (o6 + 1) & 0xff ))
		if [ "$o6" -eq 0 ]; then
			o5=$(( (o5 + 1) & 0xff ))
			if [ "$o5" -eq 0 ]; then
				o4=$(( (o4 + 1) & 0xff ))
				if [ "$o4" -eq 0 ]; then
					o3=$(( (o3 + 1) & 0xff ))
					if [ "$o3" -eq 0 ]; then
						o2=$(( (o2 + 1) & 0xff ))
						if [ "$o2" -eq 0 ]; then
							o1=$(( (o1 + 1) & 0xff ))
						fi
					fi
				fi
			fi
		fi

		cand="$(printf '%02x:%02x:%02x:%02x:%02x:%02x' "$o1" "$o2" "$o3" "$o4" "$o5" "$o6")"
		vxlan_mac_is_zero "$cand" && { i=$((i + 1)); continue; }
		vxlan_mac_is_unicast "$cand" || { i=$((i + 1)); continue; }

		if ! vxlan_mac_exists_runtime "$cand" && ! vxlan_mac_exists_uci_other "$cand" "$sec"; then
			echo "$cand"
			return 0
		fi
		i=$((i + 1))
	done

	return 1
}

vxlan_cfg_get() {
	local __dest="$1"
	local sec="$2"
	local opt="$3"
	local val

	config_get val "$sec" "$opt"
	if [ -z "$val" ] && command -v uci >/dev/null 2>&1; then
		val="$(uci -q get "network.${sec}.${opt}" 2>/dev/null)"
	fi

	eval "$__dest=\$val"
}

vxlan_cfg_get_bool() {
	local __dest="$1"
	local sec="$2"
	local opt="$3"
	local def="${4:-0}"
	local val

	vxlan_cfg_get val "$sec" "$opt"
	[ -n "$val" ] || val="$def"

	case "$val" in
		1|on|true|yes|enabled) val=1 ;;
		0|off|false|no|disabled) val=0 ;;
		*) val="$def" ;;
	esac

	eval "$__dest=\$val"
}

vxlan_ifup_dependents() {
	local owner="$1"
	local dev="$2"
	[ -n "$dev" ] || return 0
	config_foreach vxlan_ifup_dependents_cb interface "$owner" "$dev"
}

vxlan_vlan_cleanup() {
	local cfg="$1"
	local state_file
	state_file="$(vxlan_vlan_state_file "$cfg")"
	[ -f "$state_file" ] || return 0

	local dev
	while IFS= read -r dev; do
		[ -n "$dev" ] || continue
		ip link del dev "$dev" >/dev/null 2>&1
	done < "$state_file"

	rm -f "$state_file"
}

proto_vxlan_init_config() {
	vxlan_generic_init_config
	proto_config_add_string "ipaddr"
	proto_config_add_string "peeraddr"
}

proto_vxlan6_init_config() {
	vxlan_generic_init_config
	proto_config_add_string "ip6addr"
	proto_config_add_string "peer6addr"
}

[ -n "$INCLUDE_ONLY" ] || {
	add_protocol vxlan
	add_protocol vxlan6
}
