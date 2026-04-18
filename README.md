# openwrt-custom-feed

Custom OpenWrt feed focused on **EoIP** and **VXLAN** protocol support for low-memory routers, with native **netifd** integration and full **LuCI** protocol UIs.

This repository targets OpenWrt 18.06 and is designed for MikroTik interoperability, VLAN-over-tunnel use cases, and stable operation on constrained hardware.

## Keywords

OpenWrt, OpenWrt 18.06, EoIP, MikroTik EoIP, VXLAN, RFC7348, LuCI protocol, netifd, VLAN over tunnel, DHCP over VXLAN, DHCP over EoIP, tunnel bridge, ARP tuning, MSS clamp.

## What This Feed Provides

- `eoip`: MikroTik-compatible EoIP userspace helper + netifd protocol script
- `vxlan`: VXLAN netifd backend with OpenWrt 18.06 compatibility fixes
- `luci-proto-eoip`: LuCI protocol page for EoIP configuration
- `luci-proto-vxlan`: LuCI protocol page for VXLAN configuration

## Main Features

- Native protocol behavior in `/etc/config/network` (no standalone app dependency)
- LuCI integration in the standard **Network > Interfaces** flow
- Auto device naming (`eoipN` / `vxlanN`) when needed
- Optional bind interface / no-bind behavior for routed underlay setups
- VLAN subinterface generation over tunnel interfaces
- DHCP helper logic for dependent interfaces on tunnel VLANs
- Bridge MAC auto-adjust logic for VXLAN/EoIP bridge scenarios
- Advanced EoIP options: loop-protect, ARP tuning, MSS clamp, DF control

## Branch Strategy

- `openwrt-18.06`: stable branch for OpenWrt 18.06
- Future OpenWrt versions should use one branch per version line

## Feed Setup

Add to `feeds.conf` or `feeds.conf.default`:

```text
src-git customfeed https://github.com/fbinerd/openwrt-custom-feed.git;openwrt-18.06
```

Then run:

```sh
./scripts/feeds update customfeed
./scripts/feeds install -p customfeed eoip vxlan luci-proto-eoip luci-proto-vxlan
```

## Typical Buildroot Install Targets

```sh
./scripts/feeds install -p customfeed eoip
./scripts/feeds install -p customfeed vxlan
./scripts/feeds install -p customfeed luci-proto-eoip
./scripts/feeds install -p customfeed luci-proto-vxlan
```

## Notes

- OpenWrt 18.06 has legacy LuCI/network model behavior; this feed includes compatibility handling for that stack.
- For 1500-byte VLAN payloads over tunnels, underlay MTU and DF/fragmentation behavior still apply.
