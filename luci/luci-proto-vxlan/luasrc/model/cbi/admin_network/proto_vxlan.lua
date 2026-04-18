local map, section, net = ...
local uci = require("luci.model.uci").cursor()

local ifname, vni, remote, localip, nobind, tunlink, port, mtu, ttl, tos, rxcsum, txcsum, vlan

ifname = section:taboption("general", Value, "ifname", translate("Device Name"))
ifname.placeholder = "vxlan0"
ifname.datatype = "maxlength(15)"
ifname.rmempty = true

vni = section:taboption("general", Value, "vid", translate("VXLAN network identifier"))
vni.datatype = "range(1, 16777215)"

remote = section:taboption("general", Value, "peeraddr", translate("Remote IPv4 address"))
remote.datatype = "or(hostname,ip4addr)"
remote.rmempty = false

localip = section:taboption("general", Value, "ipaddr", translate("Local IPv4 address"))
localip.datatype = "ip4addr"

nobind = section:taboption("general", Flag, "nobind", translate("Do not bind to any interface"))
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

tunlink = section:taboption("general", Value, "tunlink", translate("Bind interface"))
tunlink.template = "cbi/network_ifacelist"
tunlink.rmempty = true
tunlink.default = "none"
tunlink:value("none", translate("unspecified"))
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

port = section:taboption("general", Value, "port", translate("Destination port"))
port.datatype = "port"
port.placeholder = "4789"

vlan = section:taboption("general", DynamicList, "vlan", translate("VLAN IDs"))
vlan.datatype = "range(1, 4094)"

mtu = section:taboption("advanced", Value, "mtu", translate("Override MTU"))
mtu.placeholder = "1500"
mtu.datatype = "range(576, 9200)"

ttl = section:taboption("advanced", Value, "ttl", translate("Override TTL"))
ttl.placeholder = "64"
ttl.datatype = "min(1)"

tos = section:taboption("advanced", Value, "tos", translate("Override TOS"))
tos.datatype = "range(0,255)"

rxcsum = section:taboption("advanced", Flag, "rxcsum", translate("Enable rx checksum"))
rxcsum.default = rxcsum.enabled

txcsum = section:taboption("advanced", Flag, "txcsum", translate("Enable tx checksum"))
txcsum.default = txcsum.enabled
