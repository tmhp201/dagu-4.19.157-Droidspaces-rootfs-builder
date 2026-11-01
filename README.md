# Dagu Droidspaces RootFS

为小米平板 5 Pro 12.4（`dagu`，内核 `4.19.157`）准备的 Droidspaces 根文件系统。装好 KPM、Termux、Termux:X11，并在 Termux 里装好 X11 与音频包之后，导入本仓库发布的 rootfs，容器内的 KDE 桌面、声音、双栈网络、systemd 与 Docker 直接可用。

## 为什么需要这个 rootfs

这台设备的内核是 4.19，厂商关闭了 `CONFIG_USER_NS`、`CONFIG_SYSVIPC`、`CONFIG_POSIX_MQUEUE`、`CONFIG_IP6_NF_NAT`、`CONFIG_MACVLAN`。这些能力由 [droidspaces-dagu-kpm](https://github.com/univers629/droidspaces-dagu-kpm) 在运行时补上；rootfs 这一侧还有几处必须预先处理：

| 问题 | 处理方式 |
| --- | --- |
| systemd-networkd 257 用 nexthop 对象下发 IPv6 RA 路由，4.19 不支持，networkd 反复重配并丢掉地址 | 关闭 `IPv6AcceptRA`、开启 `KeepConfiguration`，由 `ds-nat6.service` 自行派生 IPv6 地址 |
| NAT 模式下容器拿不到可路由的 IPv6 | 由 DHCPv4 地址派生 `fd64:7370::/48` 内的地址，网关 `fe80::1`；宿主没有全局 IPv6 时不保留默认路由 |
| Termux:X11 的 X socket 与 Termux PulseAudio 的 socket 位于容器外 | `desktop-session.service` 读取 `/run/droidspaces.env` 里的 `PULSE_SERVER`；X socket 由 Droidspaces 的 X11 开关绑定到 `/tmp/.X11-unix` |
| 容器内没有自动启动图形会话的入口 | `desktop-session.service` 在 `:5` 上启动 `startplasma-x11` |

## 镜像内容

| 组件 | 内容 |
| --- | --- |
| 发行版 | Debian 13（trixie），arm64 |
| 桌面 | KDE Plasma X11：`plasma-desktop`、`plasma-workspace`、`plasma-pa`、Konsole、Dolphin、Kate、Spectacle、Ark |
| 网络 | `systemd-networkd` + `systemd-resolved`，`10-droidspaces.network` 走 DHCPv4 并保留地址 |
| IPv6 | `ds-nat6.service`：从 IPv4 派生地址、装默认路由、探测上游 |
| 容器 | `docker.service`、`containerd.service`，`/etc/docker/daemon.json` 配置镜像加速 |
| 系统 | systemd 作为 init，`ssh.service`、`dbus.service`、`dagu-firstboot.service` |
| 用户 | `dagu`（uid 1000，`sudo` 免密），桌面会话以该用户运行 |
| 浏览器 | Firefox ESR |

## 前置条件

以下三项各做一次。

**1. 刷入 KPM**。使用 [droidspaces-dagu-kpm](https://github.com/univers629/droidspaces-dagu-kpm) 的发布物，按其 README 刷入 `boot_a`。

**2. 安装两个应用**：Termux 与 Termux:X11。

**3. 在 Termux 里安装 X11 与音频包**：

```sh
pkg update
pkg install x11-repo
pkg install termux-x11-nightly pulseaudio
```

## 安装

### 准备归档

从本仓库 Release 下载 `Dagu-KDE-Droidspaces-rootfs-aarch64-*.tar.xz`，放进设备存储（例如 `/sdcard/Download`）。不要解压。

### 打开安装向导

Droidspaces → 底部 **容器** 标签 → 右下角 **+** → **从文件安装** → 选择刚才的 `.tar.xz`。

向导共五步，顺序固定：**容器设置 → 推荐配置 → 配置 → 存储 → 安装概要**。其中 **推荐配置** 只在从 Droidspaces 导出的归档（自带 `container.config`）时出现，本镜像没有携带该文件，因此会直接从 **容器设置** 进入 **配置**。

### 1/5 容器设置

| 字段 | 填写 | 说明 |
| --- | --- | --- |
| 容器名称 | 任意，例如 `dagu` | 不能与已有容器重名 |
| 主机名 | 与容器名称相同即可 | 留空时默认跟随容器名称 |

底部按钮：**下一步：配置**。

### 2/5 配置

页面自上而下分五组，顺序与下面的表一致。每组之间用分隔线隔开。

**网络**

| 顺序 | 选项 | 选择 | 说明 |
| --- | --- | --- | --- |
| 1 | 网络模式 | `NAT（默认）` | 点开是子页，见下方「网络模式子页」 |
| 2 | 禁用 IPV6 | 关 | 宿主没有全局 IPv6 时由 `ds-nat6` 自动不保留默认路由，不需要在这里关 |
| 3 | DNS 服务器 | `223.5.5.5,8.8.8.8` | 留空则使用 DHCP 下发的 DNS |

**网络模式子页**（点「网络模式」进入）：选项依次为 `NAT（默认）`、`主机`、`Macvlan（有线局域网）`、`网关（虚拟路由器）`、`无网络`。选 `NAT` 即可；选 `Macvlan` 时下面会多出父接口与 macvlan 模式（bridge/private/vepa/passthru）两组选项，Wi-Fi 下不可用。选 `NAT` 后本页还会出现 **静态 IP 地址**（留空即可）。选 `网关` 会增加 **上游接口** 与 **端口转发**。选完返回上一级继续。

**集成与硬件**

| 顺序 | 选项 | 选择 | 说明 |
| --- | --- | --- | --- |
| 4 | Android 存储 | 关 | 需要访问 `/sdcard` 时再开 |
| 5 | 硬件访问 | 关 | 会把 GPU 节点镜像进隔离的 `/dev`，与下面一项互斥 |
| 6 | GPU 访问 | 开 | 硬件渲染，KDE 桌面需要 |
| 7 | 配置 Termux:X11 | 开 | 把 Termux:X11 的 socket 绑定到容器 `/tmp/.X11-unix`，`DISPLAY=:5` |
| 8 | Anland 显示 | 关 | 与 Termux:X11 互斥，本镜像走 X11 |
| 9 | 配置 VirGL 3D 加速功能 | 关 | 与 GPU 访问互斥 |
| 10 | 配置 PulseAudio | 开 | 以 Termux 用户启动 PulseAudio，并把 `PULSE_SERVER` 写进 `/run/droidspaces.env` |

**资源限制**

| 顺序 | 选项 | 选择 | 说明 |
| --- | --- | --- | --- |
| 11 | 内存限制 | 关 | 本机内核缺 CFS 带宽限流，CPU 限制不可用；内存限制可留默认 |
| 12 | 允许交换空间（swap） | 关 | |
| 13 | 限制 CPU | 关 | 内核未开 `CONFIG_CFS_BANDWIDTH`，置灰 |
| 14 | 限制进程数 | 关 | 内核未开 `CONFIG_CGROUP_PIDS`，置灰 |

**安全与启动**

| 顺序 | 选项 | 选择 | 说明 |
| --- | --- | --- | --- |
| 15 | SELinux 宽容模式 | 关 | |
| 16 | 允许沙箱 | 开 | 允许容器内创建用户命名空间，Docker、bwrap、桌面组件的沙箱依赖它 |
| 17 | 易失模式 | 关 | 改动不落盘 |
| 18 | 强制 Cgroup V1 | 关 | 本机内核只有 cgroup v1，Droidspaces 会自动处理 |
| 19 | 特权模式 | 不配置 | |
| 20 | 开机自启动 | 按需 | |

**高级选项**

| 顺序 | 选项 | 选择 | 说明 |
| --- | --- | --- | --- |
| 21 | 环境变量 | 不配置 | 声音与显示由上面的开关负责 |
| 22 | 绑定挂载点 | 不配置 | X11 socket 已由「配置 Termux:X11」处理 |
| 23 | 指定 init 可执行文件路径 | `/sbin/init` | 镜像用 systemd；留空也等价于 `/sbin/init` |
| 24 | Termux:X11 额外参数 | 留空 | 开启「配置 Termux:X11」后出现 |

底部按钮：**下一步：存储**。

### 3/5 存储

| 顺序 | 选项 | 选择 | 说明 |
| --- | --- | --- | --- |
| 1 | 存储位置 | `内部存储（默认）` | 选「自定义存储目录」会多出 **选择文件夹**，可放到 SD 卡或 U 盘 |
| 2 | 使用稀疏镜像 | **关** | 关闭后 rootfs 以目录解压到安装路径。本机 4.19 厂商内核上，稀疏镜像（loop + ext4）启动容器的路径尚未验证，打开会出现启动即重启；目录模式是与已验证容器一致的形式 |
| 3 | 镜像大小 | 仅在开启稀疏镜像时可调 | |

底部按钮：**下一步：安装概览**。

### 4/5 安装概要

按顺序核对这几行：

| 行 | 期望值 |
| --- | --- |
| 归档 | 下载的 `Dagu-KDE-…tar.xz` 文件名 |
| 容器 | 上一步填写的名称 |
| 主机名 | 同上 |
| 网络模式 | `NAT` |
| 静态 IP 地址 | 只在填写过时出现 |
| 存储配置 | `目录`（若存储页关掉了稀疏镜像） |
| 安装路径 | 内部存储下的容器目录 |
| 选项 | 展开后确认 GPU 访问、配置 Termux:X11、配置 PulseAudio、允许沙箱 为开启 |

确认后点 **安装**，进入安装进度页；解包需要一到几分钟。

### 5/5 安装进度

安装完成后回到 **容器** 标签，卡片上出现新容器。

## 首次启动

1. 在 Termux 里执行一次 `termux-x11 :5`，或直接打开 Termux:X11 应用。
2. 在 **容器** 标签点 **启动**，会弹出日志窗口；等卡片显示「正在运行」与 PID 后关闭即可。
3. 打开 Termux:X11 应用，看到 KDE 桌面。

启动过程中容器内依次发生：

- `systemd-networkd` 在 `eth0` 上取 DHCP 地址；
- `ds-nat6.service` 从 IPv4 地址派生 `fd64:7370::…/64`，装默认路由并探测上游，不可达则移除该路由；
- `desktop-session.service` 等待 `/tmp/.X11-unix/X5`，然后以 `dagu` 用户执行 `startplasma-x11`；
- `docker.service`、`containerd.service` 启动，容器内可直接 `docker run`。

## 验证

在 **面板** 标签点卡片上的 **终端**（或容器详情里的 **可用用户** → 复制登录命令，粘到 Termux）后执行：

```sh
ip -br addr show eth0          # 应有 172.28.x.y/16 与 fd64:7370::…/64
curl -4 -s -o /dev/null -w '%{http_code}\n' http://www.baidu.com
curl -6 -s -o /dev/null -w '%{http_code}\n' https://www.baidu.com
pactl list short sinks         # 应看到 OpenSL_ES_sink 等 Termux 侧 sink
docker run --rm hello-world
systemctl status desktop-session ds-nat6 docker --no-pager
```

## 重建容器

长按容器卡片 → **卸载容器**，输入容器名确认，会删除 rootfs 与设置；之后按上面的向导重新安装。

## 命令行等价形式

```sh
su -c "droidspaces --name=dagu \
  --rootfs=/data/local/Droidspaces/Containers/dagu/rootfs \
  --init=/sbin/init --net=nat --dns=223.5.5.5,8.8.8.8 \
  --x11 --pulse-audio --gpu --allow-sandboxing start"
```

## 自行构建

**GitHub Actions**：推送到 `main`、推 `v*` 标签，或在 Actions 页面手动触发，都会构建并发布新的 Release，同时更新 `rootfs.json`。

**本地**：

```sh
./build.sh -a aarch64 -i Dagu-KDE -v v20261101-120000
```

依赖 Docker（含 buildx）、`jq`、`xz`。产物为 `Dagu-KDE-Droidspaces-rootfs-aarch64-<日期>-<版本>.tar.xz`。

## 目录结构

```
archs.json                              架构到 Docker 平台与 CI runner 的映射
build.sh                                构建单个模板
templates/aarch64/Dagu-KDE.Dockerfile   镜像定义
rootfs/                                 覆盖进镜像的文件
  etc/systemd/network/10-droidspaces.network
  etc/systemd/system/{desktop-session,ds-nat6,dagu-firstboot}.service
  etc/docker/daemon.json
  etc/profile.d/90-droidspaces-session.sh
  usr/local/bin/{start-desktop-session,ds-nat6-up.sh}
  usr/local/sbin/dagu-firstboot
scripts/generate_rootfs_json.py          由 Release 资产生成 rootfs.json
rootfs.json                             供 Droidspaces 添加仓库时读取
```

## 已知限制

- 稀疏镜像模式在本机 4.19 内核上启动容器会导致整机重启，安装时请关闭「使用稀疏镜像」。
- IPv6 能否出网取决于宿主网络：宿主没有全局 IPv6 时，容器只有 `fd64:7370::/48` 内的地址，出网走 IPv4。
- `macvlan` 网络模式在 Wi-Fi 上不可用（网卡只接收目的地址为自身的帧），请使用 NAT。
- 声音依赖「配置 PulseAudio」开关：未开启时容器内只有本地空设备，不会出声。
- 镜像内 `/etc/resolv.conf` 默认是 `1.1.1.1`；向导里填了 DNS 服务器时会被覆盖，不填时可按需修改。
- Firefox ESR 在容器内可能无法启动内容进程（页面空白）；其它浏览器或桌面程序不受影响。
- 「配置 Termux:X11」开关（`enable_x11`）会让 Droidspaces 自己拉起 X 服务器，在本机内核上会导致整机重启；请把它关闭，改用绑定挂载 `$PREFIX/tmp/.X11-unix:/tmp/.X11-unix`。
- 绑定挂载的 X socket 会在容器停止时被删除。顺序必须是「先启动容器，再启动 Termux 里的 `termux-x11 :5`，最后进桌面会话」；容器一旦重启，需要重新启动 X 服务器。
- 桌面会话不使用容器内的 user systemd（unit 在此环境里不会就绪），而是由 `start-desktop-session` 在私有 D-Bus 会话里直接拉起 `startplasma-x11`；KWin 合成在 `~/.config/kwinrc` 里关闭，否则桌面全黑。

## 许可

MIT。
