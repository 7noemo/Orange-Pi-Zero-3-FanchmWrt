#!/bin/bash
#
# diy-part2.sh - 在 .config 载入之后、defconfig 之前执行
#
# 做三件事：
#   1. 按 sunxi target 实际的内核版本，把 Wi-Fi 设备树补丁落到对应 patches-x.y 目录
#   2. 自检：目标设备、Wi-Fi 包、fwx 业务包是否都在 .config 里
#   3. 打印关键信息，便于 CI 日志里一眼看出这次编的是什么

set -e

WS="${GITHUB_WORKSPACE:-$(cd "$(dirname "$0")" && pwd)}"
SUNXI=target/linux/sunxi

# --- 1. Wi-Fi 设备树补丁落位 ---
# 补丁是按 6.12 的 sun50i-h616-orangepi-zero.dtsi 生成的。上游哪天把 sunxi
# 内核版本提上去，补丁一样要落在 patches-<新版本>，否则内核根本不会应用它，
# 表现就是"驱动装了但 wlan0 不存在"——所以这里不能写死 6.12。
KVER=$(sed -n 's/^KERNEL_PATCHVER:=//p' "$SUNXI/Makefile" | tr -d '[:space:]')
if [ -z "$KVER" ]; then
	echo "::error::cannot detect KERNEL_PATCHVER from $SUNXI/Makefile"
	exit 1
fi
DEST="$SUNXI/patches-$KVER"
mkdir -p "$DEST"
if ! ls "$DEST"/102-dts-sun50i-h616-orangepi-zero*.patch >/dev/null 2>&1; then
	cp "$WS/patches/102-dts-sun50i-h616-orangepi-zero3-add-wifi.patch" "$DEST/"
	echo "[diy-part2] staged Wi-Fi DTS patch into $DEST (kernel $KVER)"
else
	echo "[diy-part2] Wi-Fi DTS patch already present in $DEST"
fi

# --- 2. 自检 ---
# 只查「必须由种子 config 显式选中」的包。
# fwxd / kmod-fwx / luci-app-fwx-* 这些是上游 include/target.mk 的
# DEFAULT_PACKAGES.router 带进来的，defconfig 之后才会出现在 .config 里，
# 在 defconfig 之前查它们必然是空的 —— 那些放到 workflow 的
# "Verify key packages in .config" 步骤里查。
fail=0
check_on() {
	if grep -q "^CONFIG_$1=y" .config; then
		echo "OK:   $1"
	else
		echo "FAIL: $1 不在种子 config 里（包名不对或依赖缺失）"
		fail=1
	fi
}
for k in \
	TARGET_sunxi_cortexa53_DEVICE_xunlong_orangepi-zero3 \
	PACKAGE_kmod-uwe5622 PACKAGE_uwe5622-firmware \
	PACKAGE_luci-app-fwx-app-center \
	PACKAGE_luci-app-passwall2 PACKAGE_luci-compat \
	LUCI_LANG_zh_Hans \
	PACKAGE_luci-app-ttyd PACKAGE_luci-app-samba4 PACKAGE_luci-app-dockerman
do
	check_on "$k"
done

if [ "$fail" -ne 0 ]; then
	echo "::error::预装包自检失败，详见上面 FAIL 行（defconfig 会把无效包名静默丢掉）"
	exit 1
fi

echo "[diy-part2] target: $(grep '^CONFIG_TARGET_BOARD=' .config) / $(grep '^CONFIG_TARGET_SUBTARGET=' .config)"
echo "[diy-part2] kernel patchver: $KVER"
exit 0
