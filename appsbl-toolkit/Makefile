# SPDX-License-Identifier: GPL-2.0-only

include $(TOPDIR)/rules.mk

PKG_NAME:=appsbl-toolkit
PKG_RELEASE:=1
PKG_FLAGS:=nonshared
PKG_LICENSE:=GPL-2.0-only

include $(INCLUDE_DIR)/package.mk

define Package/appsbl-toolkit
  SECTION:=utils
  CATEGORY:=Base system
  TITLE:=APPSBL research toolkit for TP-Link/Mercusys devices (research-only)
  DEPENDS:=@(TARGET_qualcommax) +mtd +kmod-mtd-rw +uboot-envtools
endef

define Package/appsbl-toolkit/description
 Research-only toolkit targeting TP-Link's own nm_fwup.c/handle_fw_cloud
 firmware-signing scheme (RSA-1024 PKCS#1v1.5 or RSA-2048/PSS, shared
 across a number of TP-Link and Mercusys-branded devices - see
 appsbl/scripts/tplink-cloud-sign.py's COMPATIBLE_ROUTERS list). This
 package's hardcoded offsets/hashes currently target the Mercusys MR80X
 v2/v5 (also sold as the MR3000X); appsbl-verify-image's signature check
 itself is not device-specific:
 .
 - appsbl-patch-dualkey / appsbl-dualkey-patcher: patches the live
   0:APPSBL partition to accept this project's own signing key as a
   fallback alongside TP-Link/Mercusys's original key. Verifies the
   partition's SHA-256 before and after the structural part of the
   patch against the exact stock build and the known-good result, and
   separately validates each embedded public key as a well-formed,
   correctly-sized PUBLICKEYBLOB - refusing to write anything to flash
   if any of those checks fail. The key fields are independent,
   human-editable files under /etc/appsbl-dualkey/, so rotating the
   research key is a matter of editing them (or using --set-key, which
   validates before writing) rather than rebuilding this package. Also
   supports --restore-factory (reverses the patch back to the exact
   stock image) and --write-appsbl <file> (raw, size-checked write).
 - appsbl-env-tool: reads, backs up, and edits the 0:APPSBL environment
   partition (0:appsblenv - U-Boot env, bootcmd/bootdelay/MACs/etc.),
   wrapping uboot-envtools' fw_printenv/fw_setenv rather than
   reimplementing the env format. Deliberately does NOT claim to
   restore a genuine untouched OEM-factory env - this project has no
   captured reference for that; --restore-baseline only restores the
   three variables this project's own installer sets
   (bootcmd/bootdelay/tp_boot_idx), never device-unique fields like
   ethaddr. See appsbl-env-tool(8).
 - appsbl-verify-image / appsbl-verify-and-restore: checks an uploaded
   file's RSA signature against TP-Link/Mercusys's REAL public
   firmware-signing keys, using their own vendor verification code
   (compiled as-is, not reimplemented - see appsbl/CLEAN_ROOM_STATUS.md
   and appsbl/scripts/tplink-cloud-sign-crosscheck). A valid signature
   is used only as authorization to originalize 0:appsblenv (the same
   --restore-baseline as appsbl-env-tool) and, only with
   --unpatch-appsbl (off by default), to also reverse the dual-key
   patch back to the exact stock image. The uploaded file's payload is
   never read for anything beyond the signature check itself. See
   appsbl-verify-and-restore(8).
 .
 WARNING: research-only, no warranty, entirely at your own risk. Never
 run automatically - see appsbl-patch-dualkey(8), appsbl-env-tool(8),
 and appsbl-verify-and-restore(8).
endef

define Build/Compile
	$(MAKE) -C $(PKG_BUILD_DIR) \
		CC="$(TARGET_CC)" \
		CFLAGS="$(TARGET_CFLAGS) $(TARGET_CPPFLAGS) -Wall -Wextra -Werror" \
		LDFLAGS="$(TARGET_LDFLAGS)"
endef

define Package/appsbl-toolkit/install
	$(INSTALL_DIR) $(1)/usr/sbin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/appsbl-dualkey-patcher $(1)/usr/sbin/
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/appsbl-verify-image $(1)/usr/sbin/
	$(INSTALL_BIN) ./files/usr/sbin/appsbl-patch-dualkey $(1)/usr/sbin/
	$(INSTALL_BIN) ./files/usr/sbin/appsbl-env-tool $(1)/usr/sbin/
	$(INSTALL_BIN) ./files/usr/sbin/appsbl-verify-and-restore $(1)/usr/sbin/
	$(INSTALL_DIR) $(1)/etc/appsbl-dualkey
	$(INSTALL_DATA) ./files/etc/appsbl-dualkey/firmware-rsa2048.b64 $(1)/etc/appsbl-dualkey/
	$(INSTALL_DATA) ./files/etc/appsbl-dualkey/legacy-rsa1024.b64 $(1)/etc/appsbl-dualkey/
endef

$(eval $(call BuildPackage,appsbl-toolkit))
