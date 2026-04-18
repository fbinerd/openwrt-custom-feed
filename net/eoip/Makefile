include $(TOPDIR)/rules.mk

PKG_NAME:=eoip
PKG_VERSION:=0.5
PKG_RELEASE:=9

PKG_MAINTAINER:=fbinerd <fbinerd@github.com>
PKG_LICENSE:=GPL-3.0

include $(INCLUDE_DIR)/package.mk

define Package/eoip
  SECTION:=net
  CATEGORY:=Network
  TITLE:=Ethernet Over IP (Mikrotik compatible) - Tiny version
  DEPENDS:=+kmod-tun
endef

define Package/eoip/description
  Tiny implementation of EoIP protocol to work as a netifd proto handler.
endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
	$(CP) ./src/* $(PKG_BUILD_DIR)/
endef

define Build/Compile
	$(TARGET_CC) $(TARGET_CFLAGS) -o $(PKG_BUILD_DIR)/eoip $(PKG_BUILD_DIR)/eoip.c $(TARGET_LDFLAGS)
endef

define Package/eoip/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/eoip $(1)/usr/bin/eoip
	$(INSTALL_DIR) $(1)/lib/netifd/proto
	$(INSTALL_BIN) ./files/eoip.sh $(1)/lib/netifd/proto/eoip.sh
	$(INSTALL_DIR) $(1)/etc/hotplug.d/iface
	$(INSTALL_BIN) ./files/95-eoip-dhcp-default-route $(1)/etc/hotplug.d/iface/95-eoip-dhcp-default-route
	$(INSTALL_BIN) ./files/96-eoip-bridge-auto-mac $(1)/etc/hotplug.d/iface/96-eoip-bridge-auto-mac
	$(INSTALL_DIR) $(1)/etc/hotplug.d/net
	$(INSTALL_BIN) ./files/96-eoip-bridge-auto-mac $(1)/etc/hotplug.d/net/96-eoip-bridge-auto-mac
endef

$(eval $(call BuildPackage,eoip))
