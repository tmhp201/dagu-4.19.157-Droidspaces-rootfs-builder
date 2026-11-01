# Dagu Droidspaces RootFS

为小米平板 5 Pro 12.4（`dagu`，内核 `4.19.157`）准备的 Droidspaces 根文件系统。装好 KPM、Termux、Termux:X11，以及在 Termux 里装好 X11 与音频包之后，导入本仓库发布的 rootfs，容器内的 KDE 桌面、声音、双栈网络、systemd 与 Docker 直接可用，不需要在宿主或容器里放任何脚本、改任何配置。

## 为什么需要这个 rootfs

这台设备的内核是 4.19，且厂商关闭了 `CONFIG_USER_NS`、`CONFIG_SYSVIPC`、`CONFIG_POSIX_MQUEUE`、`CONFIG_IP6_NF_NAT`、`CONFIG_MACVLAN`。这些能力由 [droidspaces-dagu-kpm](https://github.com/univers629/droidspaces-dagu-kpm) 在运行时补上；而 rootfs 这一侧还有几处必须预先处理，否则开箱即用做不到：

| 问题 | 处理方式 |
| --- | --- |
| systemd-networkd 257 用 nexthop 对象下发 IPv6 RA 路由，4.19 不支持，networkd 反复重配并丢掉地址 | 关闭 `IPv6AcceptRA`、开启 `KeepConfiguration`，由 `ds-nat6.service` 自行派生 IPv6 地址 |
| NAT 模式下容器拿不到可路由的 IPv6，访问 IPv6 站点会卡在超时 | 由 DHCPv4 地址派生 `fd64:7370::/48` 内的地址，网关 `fe80::1`；宿主没有全局 IPv6 时不保留默认路由 |
| Termux:X11 的 X socket 与 Termux PulseAudio 的 socket 位于容器外 | `desktop-session.service` 读取 `/run/droidspaces.env` 里的 `PULSE_SERVER`，X socket 由 Droidspaces 的 X11 支持绑定到 `/tmp/.X11-unix` |
| 容器内没有自动启动图形会话的入口 | `desktop-session.service` 在 `:5` 上启动 `startplasma-x11` |

## 镜像内容

| 组件 | 内容 |
| --- | --- |
| 发行版 | Debian 13（trixie），arm64 |
| 桌面 | KDE Plasma 6 X11：`plasma-desktop`、`plasma-workspace`、`plasma-pa`、Konsole、Dolphin、Kate、Spectacle、Ark |
| 网络 | `systemd-networkd` + `systemd-resolved`，`10-droidspaces.network` 走 DHCPv4 并保留地址 |
| IPv6 | `ds-nat6.service`：从 IPv4 派生地址、装默认路由、探测上游 |
| 容器 | `docker.service`、`containerd.service`，`/etc/docker/daemon.json` 配置镜像加速 |
| 系统 | systemd 作为 init，`ssh.service`、`dbus.service`、`dagu-firstboot.service` |
| 用户 | `dagu`（uid 1000，`sudo` 免密），桌面会话以该用户运行 |
| 浏览器 | Firefox ESR |

## 前置条件

以下三项各做一次。

**1. 刷入 KPM**。使用 [droidspaces-dagu-kpm](https://github.com/univers629/droidspaces-dagu-kpm) 的发布物，按该仓库 README 刷入 `boot_a`。KPM 提供 xt_addrtype、用户命名空间、PID/IPC 命名空间桥、IPv6 NAT、POSIX mqueue 与 SysV 共享内存。

**2. 安装两个应用**：Termux 与 Termux:X11。

**3. 在 Termux 里安装 X11 与音频包**：

```sh
pkg update
pkg install x11-repo
pkg install termux-x11-nightly pulseaudio
```

`pulseaudio` 用于把容器内的声音转发到 Android 的音频输出，Droidspaces 会在容器启动时拉起它。

## 在 Droidspaces 里创建容器

下载本仓库 Release 里的 `Dagu-KDE-Droidspaces-rootfs-aarch64-*.tar.xz`，放到设备任意目录（例如 `/sdcard/Download`）。

打开 Droidspaces，进入容器列表 → 新建容器，按下表逐项选择：

| 配置项 | 选择 | 原因 |
| --- | --- | --- |
| RootFS 来源 | 本地文件，选中刚下载的 `.tar.xz` | |
| 容器名称 | 任意，例如 `dagu` | |
| 初始化程序 | `/sbin/init` | 镜像用 systemd 管理服务 |
| 网络模式 | `NAT` | Wi-Fi 下 macvlan 只能发不能收；NAT 模式由 Droidspaces 提供 IPv4/IPv6 转发 |
| 静态 IP | 留空 | 由 NAT 的 DHCP 分配 |
| DNS | `223.5.5.5,8.8.8.8` | 留空时使用 DHCP 下发的 DNS，两者都可 |
| X11 支持 | 开 | 把 Termux:X11 的 socket 绑定到容器 `/tmp/.X11-unix`，并把 `DISPLAY=:5` 写进环境 |
| 音频 | 开 | 以 Termux 用户启动 PulseAudio，并把 `PULSE_SERVER` 写入 `/run/droidspaces.env` |
| GPU | 开 | 使用硬件渲染 |
| Sandboxing | 开 | 允许容器内再创建用户命名空间 |
| Android 存储 / Swap / VTS | 关 | 与桌面无关 |
| 内存 / CPU 限制 | 不限 | |
| 开机自启 | 按需 | |

对应的命令行形式：

```sh
su -c "droidspaces --name=dagu \
  --rootfs=/data/local/Droidspaces/Containers/dagu/rootfs \
  --init=/sbin/init --net=nat --dns=223.5.5.5,8.8.8.8 \
  --x11 --pulse-audio --gpu --allow-sandboxing start"
```

> 若界面里没有 `X11` / `音频` 开关，可先创建容器，再用 `droidspaces` 的配置界面打开，或直接编辑容器目录下的 `container.config`：`enable_x11=1`、`enable_pulseaudio=1`。

## 第一次启动

1. 在 Termux 里执行一次 `termux-x11 :5`（或直接用 Termux:X11 应用，Droidspaces 会自行拉起 X server）。
2. 启动容器。systemd 依次做：
   - `systemd-networkd` 在 `eth0` 上取 DHCP 地址；
   - `ds-nat6.service` 从 IPv4 地址派生 `fd64:7370::…/64`，装默认路由，探测上游是否可达，不可达则移除该路由；
   - `desktop-session.service` 等待 `/tmp/.X11-unix/X5` 出现，然后以 `dagu` 用户执行 `startplasma-x11`。
3. 打开 Termux:X11 应用即可看到 KDE 桌面。

## 验证

在容器里执行：

```sh
ip -br addr show eth0          # 应有 172.28.x.y/16 与 fd64:7370::…/64
curl -4 -s -o /dev/null -w '%{http_code}\n' http://www.baidu.com
curl -6 -s -o /dev/null -w '%{http_code}\n' https://www.baidu.com
pactl list short sinks         # 应能看到 OpenSL_ES_sink 等 Termux 侧 sink
docker run --rm hello-world
systemctl status desktop-session ds-nat6 docker --no-pager
```

## 自行构建

**GitHub Actions**：推送到 `main`、推 `v*` 标签，或在 Actions 页面手动触发，都会构建并发布一个新的 Release，同时更新 `rootfs.json`。

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

- IPv6 能否出网取决于宿主网络：宿主没有全局 IPv6 时，容器只有 `fd64:7370::/48` 内的地址，出网走 IPv4。
- `macvlan` 网络模式在 Wi-Fi 上不可用（网卡只接收目的地址为自身的帧），请使用 NAT。
- 声音依赖 Droidspaces 的 `--pulse-audio`：未开启时容器内只有本地空设备，不会出声。
- Firefox ESR 在容器内可能无法启动内容进程（页面空白）；其它浏览器或桌面程序不受影响。

## 许可

MIT。
