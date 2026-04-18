local luci = luci
local netmod = luci.model.network
local uci = require("luci.model.uci").cursor()
local nixio = require("nixio")
local proto = netmod:register_protocol("eoip")

function proto.get_i18n(self)
	return luci.i18n.translate("EoIP (Mikrotik)")
end

function proto.ifname(self)
	return self:_get("ifname") or ("eoip0")
end

function proto.package_install(self)
	return { "eoip" }
end

function proto.opkg_package(self)
	return "eoip"
end

function proto.is_installed(self)
	return nixio.fs.access("/lib/netifd/proto/eoip.sh")
end

function proto.is_floating(self)
	return true
end

function proto.is_virtual(self)
	return true
end

function proto.get_interfaces(self)
	return nil
end

function proto.contains_interface(self, ifc)
	return (netmod:ifnameof(ifc) == self:ifname())
end

function proto.config_package(self)
	return "network"
end

function proto.setup_schema(self, section, ifname)
	local ifname_opt = section:taboption("general", Value, "ifname", luci.i18n.translate("Device Name"))
	ifname_opt.placeholder = "eoip0"
	ifname_opt.datatype = "maxlength(15)"
	ifname_opt.rmempty = true

	local id = section:taboption("general", Value, "id", luci.i18n.translate("Tunnel ID"))
	id.datatype = "range(0, 65535)"

	local remote = section:taboption("general", Value, "remote", luci.i18n.translate("Remote IP"))
	remote.datatype = "or(hostname,ip4addr)"

	local localip = section:taboption("general", Value, "local", luci.i18n.translate("Local IP"))
	localip.datatype = "ip4addr"

	local nobind = section:taboption("general", Flag, "nobind", luci.i18n.translate("Do not bind to any interface"))
	nobind.rmempty = false
	nobind.default = nobind.enabled
	nobind.cfgvalue = function(self, sec)
		local v = uci:get("network", sec, "tunlink")
		if v == nil or v == "" or v == "none" then
			return self.enabled
		end
		return self.disabled
	end
	nobind.write = function(self, sec, value)
		Flag.write(self, sec, value)
		if value == self.enabled then
			uci:set("network", sec, "tunlink", "none")
		end
	end

	local tunlink = section:taboption("general", Value, "tunlink", luci.i18n.translate("Bind interface"))
	tunlink.template = "cbi/network_ifacelist"
	tunlink.rmempty = true
	tunlink.default = "none"
	tunlink:value("none", luci.i18n.translate("unspecified"))
	tunlink.write = function(self, sec, value)
		local v = value or ""
		local nb = uci:get("network", sec, "nobind")
		if nb == "1" then
			v = "none"
		end
		if v == "" then
			v = "none"
		end
		local brsec = v:match("^br%-(.+)$")
		if brsec and uci:get("network", brsec) then
			v = brsec
		end
		Value.write(self, sec, v)
	end

	local bridge = section:taboption("general", Value, "bridge", luci.i18n.translate("Bridge Device (optional)"))
	bridge.placeholder = "br-lan"

	local dynamic = section:taboption("advanced", Flag, "dynamic", luci.i18n.translate("Dynamic Peer"))
	dynamic.default = dynamic.disabled

	local mtu = section:taboption("advanced", Value, "mtu", luci.i18n.translate("MTU"))
	mtu.placeholder = "1458"
	mtu.validate = function(self, value)
		if value == nil or value == "" then
			return "1458"
		end
		if value == "auto" then
			return value
		end
		local n = tonumber(value)
		if n and n >= 576 and n <= 9200 then
			return tostring(math.floor(n))
		end
		return nil, luci.i18n.translate("Must be 'auto' or a value between 576 and 9200")
	end

	local keepalive = section:taboption("advanced", Value, "keepalive", luci.i18n.translate("Keepalive interval (s)"))
	keepalive.placeholder = "10"
	keepalive.datatype = "range(0,600)"

	local dscp = section:taboption("advanced", Value, "dscp", luci.i18n.translate("DSCP"))
	dscp.placeholder = "inherit"
	dscp.validate = function(self, value)
		if value == nil or value == "" then
			return ""
		end
		if value == "inherit" then
			return ""
		end
		local n = tonumber(value)
		if n and n >= 0 and n <= 63 then
			return tostring(math.floor(n))
		end
		return nil, luci.i18n.translate("Must be between 0 and 63")
	end

	local df = section:taboption("advanced", Flag, "df", luci.i18n.translate("Don't Fragment"))
	df.default = df.disabled

	local loop_protect = section:taboption("advanced", Flag, "loop_protect", luci.i18n.translate("Enable loop protect"))
	loop_protect.default = loop_protect.disabled

	local loop_disable_time = section:taboption("advanced", Value, "loop_protect_disable_time", luci.i18n.translate("Loop-protect disable time (s)"))
	loop_disable_time.placeholder = "5"
	loop_disable_time.datatype = "range(1,3600)"
	loop_disable_time:depends("loop_protect", "1")

	local loop_send_interval = section:taboption("advanced", Value, "loop_protect_send_interval", luci.i18n.translate("Loop-protect send interval (s)"))
	loop_send_interval.placeholder = "5"
	loop_send_interval.datatype = "range(1,600)"
	loop_send_interval:depends("loop_protect", "1")

	local clamp_tcp_mss = section:taboption("advanced", Flag, "clamp_tcp_mss", luci.i18n.translate("Clamp TCP MSS to PMTU"))
	clamp_tcp_mss.default = clamp_tcp_mss.enabled

	local allow_fast_path = section:taboption("advanced", Flag, "allow_fast_path", luci.i18n.translate("Allow fast path (best effort)"))
	allow_fast_path.default = allow_fast_path.enabled

	local macaddr = section:taboption("advanced", Value, "macaddr", luci.i18n.translate("Override MAC address"))
	macaddr.datatype = "macaddr"
	macaddr.placeholder = "02:00:00:00:00:01"

	local arp = section:taboption("advanced", Flag, "arp", luci.i18n.translate("Enable ARP"))
	arp.default = arp.enabled

	local arp_timeout = section:taboption("advanced", Value, "arp_timeout", luci.i18n.translate("ARP stale timeout (s)"))
	arp_timeout.placeholder = "default"
	arp_timeout.datatype = "uinteger"

	local arp_ignore = section:taboption("advanced", Value, "arp_ignore", luci.i18n.translate("ARP ignore mode"))
	arp_ignore.placeholder = "kernel default"
	arp_ignore.datatype = "range(0,8)"

	local arp_announce = section:taboption("advanced", Value, "arp_announce", luci.i18n.translate("ARP announce mode"))
	arp_announce.placeholder = "kernel default"
	arp_announce.datatype = "range(0,2)"

	local arp_accept = section:taboption("advanced", Flag, "arp_accept", luci.i18n.translate("Accept gratuitous ARP"))
	arp_accept.rmempty = true

	local arp_filter = section:taboption("advanced", Flag, "arp_filter", luci.i18n.translate("Enable ARP filtering"))
	arp_filter.rmempty = true

	local arp_notify = section:taboption("advanced", Flag, "arp_notify", luci.i18n.translate("Notify ARP on link change"))
	arp_notify.rmempty = true

	local arp_base_reachable = section:taboption("advanced", Value, "arp_base_reachable_time_ms", luci.i18n.translate("ARP base reachable time (ms)"))
	arp_base_reachable.placeholder = "kernel default"
	arp_base_reachable.datatype = "uinteger"

	local arp_retrans = section:taboption("advanced", Value, "arp_retrans_time_ms", luci.i18n.translate("ARP retransmit time (ms)"))
	arp_retrans.placeholder = "kernel default"
	arp_retrans.datatype = "uinteger"

	local vlan = section:taboption("general", DynamicList, "vlan", luci.i18n.translate("VLAN IDs"))
	vlan.datatype = "range(1, 4094)"
end

netmod:register_pattern_virtual("^eoip%-.+")
netmod:register_pattern_virtual("^zeoip%-.+")

return proto
