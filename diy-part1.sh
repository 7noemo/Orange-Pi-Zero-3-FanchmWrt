#!/bin/bash
#
# diy-part1.sh - 在 feeds update 之前执行
#
# FanchmWrt 底座（fanchmwrt-25.12.6 = OpenWrt 25.12.6 / kernel 6.12）相比
# ImmortalWrt 缺三块东西，这里补齐：
#   1. 板载 Wi-Fi（AW859A / UWE5622）的内核驱动包 —— OpenWrt 官方树没有
#   2. uwe5622 固件包（wcnmodem.bin 等二进制，从 armbian/firmware 取）
#   3. Zero 2 / Zero 3 的 Wi-Fi 设备树节点（mmc1 + pwrseq + 两路 regulator）
# 另外追加 kenzok8/small feed（PassWall2 及其 tcping / geoview 依赖）。
#
# 注意：FanchmWrt 自己的 package/fcm（fwxd / fwx）与 luci-app-fwx-* 都在
# 主干和官方 fanchmwrt-packages feed 里，不需要也不应该再引入 OpenAppFilter，
# 否则会和 fwx 抢同一套 netlink/配置。

set -e

WS="${GITHUB_WORKSPACE:-$(cd "$(dirname "$0")" && pwd)}"

# --- 1. uwe5622 驱动（从 ImmortalWrt 取，pin 到具体 commit 保证可复现）---
IMM_REPO=https://github.com/immortalwrt/immortalwrt
IMM_SHA=2fe3065ade26bd1ef85539c9d1bd2272bdb0aa01

rm -rf /tmp/imm
git init -q /tmp/imm
git -C /tmp/imm remote add origin "$IMM_REPO"
if git -C /tmp/imm fetch -q --depth 1 origin "$IMM_SHA"; then
	echo "[diy-part1] uwe5622: immortalwrt @ $IMM_SHA"
else
	echo "[diy-part1] uwe5622: pinned fetch failed, falling back to master"
	git -C /tmp/imm fetch -q --depth 1 origin master
fi
git -C /tmp/imm checkout -q FETCH_HEAD -- package/kernel/uwe5622
rm -rf package/kernel/uwe5622
cp -r /tmp/imm/package/kernel/uwe5622 package/kernel/
rm -rf /tmp/imm
echo "[diy-part1] vendored kmod-uwe5622"

# --- 1b. cfg80211 接口：适配 mac80211 backports-6.18 ---
# 驱动的 cfg80211_ops 要满足的是 mac80211 backports 包里的结构体，不是内核的。
# FanchmWrt 25.12.6 用的是 backports-6.18.55，其
# set_wiphy_params(wiphy, int radio_idx, u32 changed) 已多一个参数；驱动按
# LINUX_VERSION_CODE(6.12) 选到了老签名，编译报：
#   initialization of 'int (*)(struct wiphy *, int, u32)' from incompatible
#   pointer type 'int (*)(struct wiphy *, u32)'
# ImmortalWrt 自带的 010 补丁强制的是相反的一套（老 wireless_dev 变体），
# 直接替换掉。
rm -f package/kernel/uwe5622/patches/010-fix-cfg80211-backport.patch
cat > package/kernel/uwe5622/patches/010-backports-cfg80211-api.patch <<'PATCH'
Subject: [PATCH] wifi: uwe5622: use the backports-6.18 set_wiphy_params signature

The cfg80211_ops struct comes from the mac80211 backports package, whose API
may be newer than the kernel the driver is compiled against. backports-6.18
adds the radio_idx argument to set_wiphy_params, so select that variant when
building for OpenWrt.

--- a/unisocwifi/cfg80211.c
+++ b/unisocwifi/cfg80211.c
@@ -2348,7 +2348,7 @@ err:
 	return ret;
 }
 
-#if LINUX_VERSION_CODE >= KERNEL_VERSION(6, 17, 0)
+#if (LINUX_VERSION_CODE >= KERNEL_VERSION(6, 17, 0)) || defined(BUILD_OPENWRT)
 static int sprdwl_cfg80211_set_wiphy_params(struct wiphy *wiphy, int radio_idx, u32 changed)
 #else
 static int sprdwl_cfg80211_set_wiphy_params(struct wiphy *wiphy, u32 changed)
PATCH
echo "[diy-part1] patched uwe5622 for backports-6.18 cfg80211 API"

# --- 1c. 变长数组 reply buffer（CONFIG_WERROR 下 -Werror=vla 直接挂）---
# 移植 armbian/uwe5622 d6a378a + fa9d1a6
cat > package/kernel/uwe5622/patches/015-fix-wvla-reply-buffers.patch <<'PATCH'
Subject: [PATCH] unisocwifi: size the reply buffers with sizeof (-Wvla)

sprdwl_set_packet_offload(), sprdwl_vendor_get_llstat_handler() and
sprdwl_vendor_clr_llstat_handler() size r_buf[] by a u16 that only ever holds
a sizeof value, so gcc sees a variable-length array and kernels built with
CONFIG_WERROR fail with -Werror=vla.

Use the sizeof expression as the array size; r_len keeps its role as the
in/out reply length.

Ported from armbian/uwe5622 d6a378a and fa9d1a6.

--- a/unisocwifi/cmdevt.c
+++ b/unisocwifi/cmdevt.c
@@ -3630,7 +3630,7 @@ int sprdwl_set_packet_offload(struct sprdwl_priv *priv, u8 vif_ctx_id,
 	struct sprdwl_cmd_packet_offload *p;
 	struct sprdwl_cmd_packet_offload *packet = NULL;
 	u16 r_len = sizeof(*packet);
-	u8 r_buf[r_len];
+	u8 r_buf[sizeof(*packet)];
 
 	msg = sprdwl_cmd_getbuf(priv, sizeof(*p) + len, vif_ctx_id,
 				SPRDWL_HEAD_RSP, WIFI_CMD_PACKET_OFFLOAD);
--- a/unisocwifi/vendor.c
+++ b/unisocwifi/vendor.c
@@ -471,7 +471,7 @@ static int sprdwl_vendor_get_llstat_handler(struct wiphy *wiphy,
 	struct wifi_iface_stat *iface_st;
 	struct sprdwl_llstat_radio *dif_radio;
 	u16 r_len = sizeof(*llst);
-	u8 r_buf[r_len], ret, i;
+	u8 r_buf[sizeof(*llst)], ret, i;
 	u32 reply_radio_length, reply_iface_length;
 
 	struct sprdwl_priv *priv = wiphy_priv(wiphy);
@@ -593,7 +593,7 @@ static int sprdwl_vendor_clr_llstat_handler(struct wiphy *wiphy,
 	struct nlattr *tb[SPRDWL_LL_STATS_CLR_MAX + 1];
 	u32 *stats_clear_rsp_mask, stats_clear_req_mask = 0;
 	u16 r_len = sizeof(*stats_clear_rsp_mask);
-	u8 r_buf[r_len];
+	u8 r_buf[sizeof(*stats_clear_rsp_mask)];
 	u32 reply_length, ret, err;
 
 	struct sprdwl_priv *priv = wiphy_priv(wiphy);
PATCH

# ccflags-y 在 KBUILD_CFLAGS 之后生效，能盖掉内核的 -Werror；但模块 Makefile
# 属于下载下来的源码，只能在解包之后注入，所以覆盖 Build/Prepare。
cat >> package/kernel/uwe5622/Makefile <<'MAKE'

define Build/Prepare
	$(call Build/Prepare/Default)
	echo 'ccflags-y += -Wno-error' >> $(PKG_BUILD_DIR)/unisocwifi/Makefile
	echo 'ccflags-y += -Wno-error' >> $(PKG_BUILD_DIR)/unisocwcn/Makefile
endef
MAKE
echo "[diy-part1] patched uwe5622 VLA reply buffers"

# --- 2. 固件包（Makefile 随仓库，二进制这里取）---
mkdir -p package/firmware
rm -rf package/firmware/uwe5622-firmware
cp -r "$WS/package/firmware/uwe5622-firmware" package/firmware/

git clone --depth 1 --filter=blob:none --sparse https://github.com/armbian/firmware.git /tmp/armbian-fw
git -C /tmp/armbian-fw sparse-checkout set uwe5622
cp /tmp/armbian-fw/uwe5622/wcnmodem.bin package/firmware/uwe5622-firmware/
cp /tmp/armbian-fw/uwe5622/wifi_2355b001_1ant.ini package/firmware/uwe5622-firmware/
rm -rf /tmp/armbian-fw
echo "[diy-part1] fetched uwe5622 firmware files"

# --- 3. Zero 3 Wi-Fi 设备树 ---
# 上游 sun50i-h616-orangepi-zero.dtsi 只开了 mmc0（TF 卡），Wi-Fi 走的 mmc1
# + wifi-pwrseq（PG18）+ vcc33-wifi / vcc-wifi-io 两路 regulator 全都没有，
# 驱动编好了也起不来 wlan0。补丁在 diy-part2.sh 里按实际内核版本落位。

# --- 4. kenzok8/small feed（PassWall2 + tcping / geoview / 各芯核）---
if ! grep -q "kenzok8/small" feeds.conf.default; then
	echo 'src-git small https://github.com/kenzok8/small' >> feeds.conf.default
fi
echo "[diy-part1] appended kenzok8/small feed"
