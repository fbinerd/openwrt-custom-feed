local luci = luci
local netmod = luci.model.network
local uci = require("luci.model.uci").cursor()
local proto = netmod:register_protocol("vxlan")

function proto.get_i18n(self)
	return luci.i18n.translate("VXLAN (RFC7348)")
end

function proto.ifname(self)
	return self:_get("ifname") or (self.sid or "vxlan")
end

function proto.package_install(self)
	return { "vxlan" }
end

function proto.opkg_package(self)
	return "vxlan"
end

function proto.is_installed(self)
	return nixio.fs.access("/lib/netifd/proto/vxlan.sh")
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
	ifname_opt.placeholder = "vxlan0"
	ifname_opt.datatype = "maxlength(15)"
	ifname_opt.rmempty = true

	local remote = section:taboption("general", Value, "peeraddr", luci.i18n.translate("Remote IPv4 address"))
	remote.datatype = "or(hostname,ip4addr)"
	remote.rmempty = false

	local localip = section:taboption("general", Value, "ipaddr", luci.i18n.translate("Local IPv4 address"))
	localip.datatype = "ip4addr"

	local port = section:taboption("general", Value, "port", luci.i18n.translate("Destination port"))
	port.datatype = "port"
	port.placeholder = "4789"

	local vlan = section:taboption("general", DynamicList, "vlan", luci.i18n.translate("VLAN IDs"))
	vlan.datatype = "range(1, 4094)"

	local vni = section:taboption("general", Value, "vid", luci.i18n.translate("VXLAN network identifier"))
	vni.datatype = "range(1, 16777215)"

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

	local dev = section:taboption("general", Value, "tunlink", luci.i18n.translate("Bind interface"))
	dev.template = "cbi/network_ifacelist"
	dev.rmempty = true
	dev.default = "none"
	dev:value("none", luci.i18n.translate("unspecified"))
	dev.write = function(self, sec, value)
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

	local mtu = section:taboption("advanced", Value, "mtu", luci.i18n.translate("MTU"))
	mtu.datatype = "range(576, 9000)"
	mtu.placeholder = "1500"

	local ttl = section:taboption("advanced", Value, "ttl", luci.i18n.translate("Override TTL"))
	ttl.datatype = "min(1)"
	ttl.placeholder = "64"

	local tos = section:taboption("advanced", Value, "tos", luci.i18n.translate("Override TOS"))
	tos.datatype = "range(0,255)"

	local rxcsum = section:taboption("advanced", Flag, "rxcsum", luci.i18n.translate("Enable rx checksum"))
	rxcsum.default = rxcsum.enabled
	rxcsum.rmempty = true

	local txcsum = section:taboption("advanced", Flag, "txcsum", luci.i18n.translate("Enable tx checksum"))
	txcsum.default = txcsum.enabled
	txcsum.rmempty = true

end

netmod:register_pattern_virtual("^vxlan$")
netmod:register_pattern_virtual("^vxlan%-.+")
netmod:register_pattern_virtual("^zevx%-.+")

return proto
