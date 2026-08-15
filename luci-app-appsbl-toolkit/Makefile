# SPDX-License-Identifier: GPL-2.0-only

include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-appsbl-toolkit
PKG_LICENSE:=GPL-2.0-only

LUCI_TITLE:=Web UI for the APPSBL research toolkit (research-only)
LUCI_DESCRIPTION:=Adds an "APPSBL Toolkit" System page (Dual-Key Patch, \
	Environment, and OEM Recovery submenus) that runs appsbl-dualkey-patch/ \
	appsbl-env-tool/appsbl-verify-image: probing, patching, and restoring \
	0:APPSBL and its env partition, and validating an uploaded firmware \
	image's signature against TP-Link/Mercusys's real vendor key. This \
	package targets the same firmware-signing scheme TP-Link reuses across \
	several of its own and Mercusys-branded devices, currently exercised \
	on the Mercusys MR80X v2/v5. Selecting this package pulls in \
	appsbl-toolkit, which does the actual work and enforces the \
	initramfs-only safety gate - this is only a front end for it.
LUCI_DEPENDS:=+appsbl-toolkit

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
