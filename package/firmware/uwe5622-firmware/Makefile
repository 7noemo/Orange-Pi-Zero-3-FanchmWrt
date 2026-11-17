# SPDX-License-Identifier: GPL-2.0-only
#
# UNISOC UWE5622 firmware for AW859A (Orange Pi Zero 3 onboard Wi-Fi)
#
# 两个二进制文件由 diy-part1.sh 通过 sparse checkout 从 armbian/firmware 取回
# （只取 uwe5622 目录），放在本目录下一起打包。
# 这样做的原因：OpenWrt 官方树既没有 kmod-uwe5622 也没有对应固件包，
# 而固件不能进 git（体积 + 版权），所以构建时现取。

include $(TOPDIR)/rules.mk

PKG_NAME:=uwe5622-firmware
# 注意 PKG_VERSION 必须 apk 兼容：'-' 会被当成版本后缀（r1/rc1…），
# 用日期要写成点号分隔，否则 apk 打包阶段直接报 "package version is invalid"
PKG_VERSION:=2026.10
PKG_RELEASE:=1

include $(INCLUDE_DIR)/package.mk

define Package/uwe5622-firmware
  SECTION:=firmware
  CATEGORY:=Firmware
  TITLE:=UNISOC UWE5622 firmware (AW859A)
  DEPENDS:=@TARGET_sunxi
  PKGARCH:=all
endef

define Package/uwe5622-firmware/description
  Firmware files (wcnmodem.bin, wifi_2355b001_1ant.ini) for the Unisoc
  UWE5622 / AW859A wireless chipset, required by kmod-uwe5622.
endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
	$(CP) ./wcnmodem.bin $(PKG_BUILD_DIR)/
	$(CP) ./wifi_2355b001_1ant.ini $(PKG_BUILD_DIR)/
endef

define Build/Compile
	true
endef

define Package/uwe5622-firmware/install
	$(INSTALL_DIR) $(1)/lib/firmware/uwe5622
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/wcnmodem.bin $(1)/lib/firmware/uwe5622/
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/wifi_2355b001_1ant.ini $(1)/lib/firmware/uwe5622/
endef

$(eval $(call BuildPackage,uwe5622-firmware))
