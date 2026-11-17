# Orange-Pi-Zero-3-FanchmWrt

香橙派 **Orange Pi Zero 3**（全志 H618，Cortex-A53）云编译 **FanchmWrt** 固件。

FanchmWrt 是 OpenAppFilter（OAF）作者 **destan19** 维护的开源企业级路由系统，底座是 OpenWrt 稳定分支，在其上自研了一套 **DPI 应用识别 + 上网行为管理 + 上网审计** 体系。本仓只做三件事：**选目标设备、补板载 Wi-Fi、预装常用插件**，业务功能全部来自上游源码。

## 说明

- 源码：[fanchmwrt/fanchmwrt](https://github.com/fanchmwrt/fanchmwrt) 分支 `fanchmwrt-25.12.6`（OpenWrt 25.12.6，内核 **6.12**）
- **Wi-Fi 已支持**：板载 AW859A（Unisoc UWE5622）。OpenWrt 官方树没有这个驱动，本仓做了三件事让它跑起来：
  1. `diy-part1.sh` 从 ImmortalWrt 引入 `kmod-uwe5622` 驱动包（pin 到具体 commit）
  2. 打两个补丁适配 mac80211 **backports-6.18** 的 cfg80211 接口（`set_wiphy_params` 多一个 `radio_idx`）与 `-Werror=vla`
  3. `patches/102-*.patch` 打开 DTS 里的 `mmc1`（SDIO）+ `wifi-pwrseq`（PG18）+ 两路 regulator —— 没有它驱动装了也没有 `wlan0`
  4. 固件二进制从 `armbian/firmware` 现取，打成 `uwe5622-firmware` 包随镜像发布
- **内置 fwx 业务**（上游 `DEFAULT_PACKAGES.router` 自带）：仪表板、应用过滤、上网审计、终端管理、每日流量/时长统计、特征库在线升级、MAC 过滤/黑名单、无线设置、应用中心、Full Cone NAT（NAT1）、shortcut-fe 快转
- **预装插件**：PassWall2（仅 Xray 芯核 + nftables 透明代理）、Samba4、aria2 + AriaNg、Docker + Dockerman、ttyd、命令面板、Tailscale、UPnP、DDNS、WOL、kmod-fs-ntfs3/exfat
- **默认中文界面**，主机名 `FanchmWrt-Zero3`
- 固件下载请前往 **Releases**
- 默认地址：`http://192.168.1.1`，首次登录无密码（请立刻设置）

## 首次使用

1. 解压 `.img.gz`，用 balenaEtcher / Rufus 写入 **4GB 以上** 的 TF 卡（镜像是 256M 启动分区 + 2G rootfs）
2. 插卡上电，网线接板载网口，浏览器打开 `192.168.1.1`
3. 系统 → 管理权：设置 root 密码
4. 网络 → 无线：选择国家码（默认已设 CN）后即可开 2.4G / 5G
5. 行为管理 → 应用过滤 / 上网审计：按终端下发策略

> 特征库分免费 Lite 版（约 300 个应用）和 Plus 版（500+ 应用，需在 openappfilter.com 取 Key）。系统本身与源码免费，Key 只影响特征库档位。

## 1GB / 1.5GB 内存版（起不来先看这里）

Zero 3 的 1GB / 1.5GB / 2GB / 4GB 是同一份镜像，不用按容量选版本。容易出问题的是 U-Boot 的 DRAM 探测：

- 老 U-Boot（2024.01 那代）常把 **1GB 认成 2GB**，内核按 2GB 建页表，碰到 1GB 以上地址就 panic
- 本仓跟的 FanchmWrt 25.12 用的是较新的 U-Boot，误判概率已大幅下降

仍起不来时接串口（**115200 8N1**，板边 3 pin debug UART），看前几行按现象分流：

| 串口现象 | 结论 | 处理 |
|---|---|---|
| 完全无输出，或只剩 `U-Boot SPL 20xx.xx` | SPL 阶段 DRAM 初始化失败 | 换 5V/2A 以上电源、换卡重写 |
| 打印 `DRAM: 2048 MiB` 而板子是 1GB | 容量误判 | 换新版 U-Boot；临时可在 bootargs 加 `mem=1024M` |
| 打印 `DRAM: 1024 MiB` 后卡住 | 不是内存问题 | 见下面三条刷写错误 |

刷写最常见的三个错：

1. **没解压**：直接把 `.img.gz` 写进卡（要写解压后的 `.img`）
2. **卡太小**：启动分区 256M + rootfs 2G，用 4GB 以上卡
3. **写错文件**：`initramfs-kernel.bin` 是内存运行镜像，不是 SD 镜像

## 自动编译

- 上游分支有新提交时每 18 小时自动检查并触发编译（Update Checker）
- 也可在 Actions 页面手动运行 `Build FanchmWrt Zero 3`，并可指定分支
- 编译成功才发布 Release，自动保留最近 3 个版本
- CI 里有**预装包守卫**：`fwxd` / `kmod-fwx` / `kmod-uwe5622` / `luci-app-passwall2` 等被 defconfig 静默丢掉时直接失败并打印依赖

## 自定义

Fork 后改 `zero3-fanchmwrt.config` 里的 `CONFIG_PACKAGE_*` 即可。

- 想换/加第三方插件：在 `diy-part1.sh` 末尾追加 feed，再把包名写进 config
- 想跟新版 FanchmWrt：把 workflow 的 `REPO_BRANCH` 改到新分支（如 `fanchmwrt-25.12.7`），DTS 补丁会按实际内核版本自动落位

## 声明

FanchmWrt 主体为 **GPL-2.0**，但其 README 明确：**行为管理（家长控制）相关源码仅限个人使用，不得代表公司使用，也不得集成进商业路由器产品出售**。本仓仅做编译集成，未修改该部分代码；商用请自行联系上游取得授权。

## 致谢

- [fanchmwrt/fanchmwrt](https://github.com/fanchmwrt/fanchmwrt)（destan19）
- [immortalwrt/immortalwrt](https://github.com/immortalwrt/immortalwrt)（uwe5622 驱动）
- [armbian/firmware](https://github.com/armbian/firmware)（Wi-Fi 固件）
- [kenzok8/small](https://github.com/kenzok8/small)（PassWall2）
- [P3TERX/Actions-OpenWrt](https://github.com/P3TERX/Actions-OpenWrt)（CI 模板）

## License

[MIT](./LICENSE)
