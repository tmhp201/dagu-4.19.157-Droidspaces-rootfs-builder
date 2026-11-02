# Dagu Droidspaces RootFS

为小米平板 5 Pro 12.4（`dagu`，内核 `4.19.157`）准备的 Droidspaces 根文件系统，两条产线：

| 模板 | 发行版 | 桌面 | 显示 |
| --- | --- | --- | --- |
| `Dagu-Anland` | Ubuntu 26.04 LTS | Plasma 6 + Anland 补丁版 KWin | Anland Wayland（`wayland-anland`） |
| `Dagu-KDE` | Debian 13 | Plasma 6.7 | Termux:X11（`DISPLAY=:5`），Mesa/kgsl 渲染 |

下面的章节以 `Dagu-Anland` 为主线；Debian 模板的差异见 [Debian 13 / Plasma 6.7](#debian-13--plasma-67)。

## 为什么需要这个 rootfs

这台设备的内核是 4.19，厂商关闭了 `CONFIG_USER_NS`、`CONFIG_SYSVIPC`、`CONFIG_POSIX_MQUEUE`、`CONFIG_IP6_NF_NAT`、`CONFIG_MACVLAN`。这些能力由 [droidspaces-dagu-kpm](https://github.com/univers629/droidspaces-dagu-kpm) 在运行时补上；rootfs 这一侧还要处理：

| 问题 | 处理方式 |
| --- | --- |
| Ubuntu 26.04 自带的 systemd 259 需要新内核接口 | 镜像内改用发行版打包的 systemd 257 包族，状态目录 `/etc/droidspaces-systemd257` |
| systemd-networkd 257 用 nexthop 对象下发 IPv6 RA 路由，4.19 不支持 | 关闭 `IPv6AcceptRA`、开启 `KeepConfiguration`，由 `ds-nat6.service` 自行派生 IPv6 地址 |
| NAT 模式下容器没有可路由的 IPv6 | 从 DHCPv4 地址派生 `fd64:7370::/48` 内地址，网关 `fe80::1`；宿主没有全局 IPv6 时不保留默认路由 |
| 容器内没有显示服务 | `anland-session.service` 以 `dagu` 身份启动 `anland-session`：连接 Anland daemon 的 Wayland socket，拉起 rootless Xwayland 与 `anland-miniwm` |
| 容器内没有 logind，`/run/user/1000` 不会自动建立 | `tmpfiles.d` 与 unit 的 `ExecStartPre` 共同创建 |

## 镜像内容

| 组件 | 内容 |
| --- | --- |
| 发行版 | Ubuntu 26.04.1 LTS（`resolute`），arm64 |
| init | systemd 257，含 `systemd-networkd`、`systemd-resolved` |
| 桌面 | KDE Plasma 6：Anland 补丁版 KWin、Dolphin、Konsole、Kate |
| 显示 | `anland-session`：Wayland socket、rootless Xwayland、`anland-miniwm` |
| 网络 | `10-droidspaces.network` 走 DHCPv4 并保留地址；`ds-nat6.service` 派生 IPv6 |
| 容器 | `docker.service`、`containerd.service`；`iptables` 切到 legacy 后端 |
| 用户 | `dagu`（uid 1000，`sudo` 免密），附加组 `aid_inet`、`aid_net_raw`、`droidspaces-gpu` |
| 浏览器 | Firefox |

## 前置条件

**1. 刷入 KPM**。使用 [droidspaces-dagu-kpm](https://github.com/univers629/droidspaces-dagu-kpm) 的发布物，按其 README 刷入 `boot_a`。

**2. 安装 Anland 宿主组件**。从 [Anland Releases](https://github.com/SuperTurtleDev/anland/releases) 取 6.x 的 `anland-build.N.zip`：

| 文件 | 用途 |
| --- | --- |
| `module/anland-awl.zip` | Magisk 模块，提供 `waylandbridge` daemon 与 `anland.host` binder 服务 |
| `anland-wayland.apk` | 设备端显示应用（`com.anlandnext`） |
| `anlandx.tar.gz` | 容器侧会话组件，镜像构建时已内置，无需手动安装 |

```sh
su -c "magisk --install-module /sdcard/Download/anland-awl.zip"
adb install -r anland-wayland.apk
```

装好后重启设备，确认 daemon 与 socket：

```sh
su -c "service list | grep anland.host"     # 应出现 anland.host: [anland.IHost]
su -c "ls /data/local/tmp/awl"              # 应出现 wayland-0
```

若应用提示 `binder anland.host 不可达`，说明 SELinux 没有按名称放行该服务，补一条兜底规则：

```sh
su -c 'magiskpolicy --live "allow untrusted_app_29 default_android_service service_manager find"'
```

**3. 安装 Anland Shell**。从 [anland-shell Releases](https://github.com/SuperTurtleDev/anland-shell/releases) 取 APK 安装，用于启动容器与在容器里拉起应用。

## 安装

从本仓库 Release 下载 `Dagu-Anland-Droidspaces-rootfs-aarch64-*.tar.xz`，放进设备存储，然后在 Droidspaces 里 **容器 → + → 从文件安装** 导入。向导共五步，关键取值：

| 步骤 | 选项 | 取值 |
| --- | --- | --- |
| 配置 · 网络 | 网络模式 / DNS | `NAT` / `223.5.5.5,8.8.8.8` |
| 配置 · 集成与硬件 | GPU 访问 | 开 |
| 配置 · 集成与硬件 | 配置 Termux:X11 | **关**，本镜像走 Anland |
| 配置 · 集成与硬件 | Anland 显示 | **关**，那是 Droidspaces 内置的 5.x daemon，与本镜像的 6.x 冲突 |
| 配置 · 集成与硬件 | 配置 PulseAudio | 开 |
| 配置 · 安全与启动 | 允许沙箱 | 开 |
| 配置 · 高级选项 | 绑定挂载点 | `/data/local/tmp/awl:/run/anland` |
| 配置 · 高级选项 | 指定 init | `/sbin/init` |
| 存储 | 使用稀疏镜像 | **开**，`suid` 需要 ext4 镜像；目录模式落在 f2fs 上，`sudo` 不可用 |
| 存储 | 镜像大小 | 不小于 12 GiB |

### 首次启动

1. 在 Droidspaces 或 Anland Shell 里启动容器。
2. 打开 **Anland Wayland**（`com.anlandnext`），等状态变为 `daemon 运行中`。
3. 用 Anland Shell 的终端或应用入口启动程序；每个应用成为独立窗口，点一行即全屏。

启动过程中容器内依次发生：

- `systemd-networkd` 在 `eth0` 上取 DHCP 地址；
- `ds-nat6.service` 派生 `fd64:7370::…/64`，装默认路由并探测上游；
- `anland-session.service` 等 `/run/anland/wayland-0` 出现，把 `wayland-anland` 链接到 `/run/user/1000`，再启动会话；
- `docker.service`、`containerd.service` 启动。

## 验证

在容器内执行：

```sh
ip -br addr show eth0                       # 172.28.x.y/16 与 fd64:7370::…/64
curl -4 -s -o /dev/null -w '%{http_code}\n' http://www.baidu.com
curl -6 -s -o /dev/null -w '%{http_code}\n' https://www.baidu.com
sudo -n id                                  # 稀疏镜像下为 uid=0(root)
systemctl status anland-session ds-nat6 docker --no-pager
ls -l /run/user/1000/wayland-anland         # 指向 /run/anland/wayland-0
```

## Debian 13 / Plasma 6.7

`debian` 分支新增 `Dagu-KDE` 模板：Debian 13 (trixie) 底座 + Plasma 6.7.4 + X11 + Mesa/kgsl。与 `Dagu-Anland` 的主要差异：

| 项目 | Dagu-Anland | Dagu-KDE |
| --- | --- | --- |
| 发行版 | Ubuntu 26.04 | Debian 13 |
| systemd | 257（用 `systemd257.sh` 换装） | 257（发行版自带，`systemd257.sh` 检测后跳过） |
| 桌面 | Anland 补丁版 KWin（Wayland） | Plasma 6.7.4 + `kwin-x11` |
| 显示 | `anland-session` | Termux:X11，`desktop-session.service` → `startplasma-x11` |
| 渲染 | Mesa/kgsl（Anland 后端） | Mesa/kgsl（`MESA_LOADER_DRIVER_OVERRIDE=kgsl`） |
| 容器开关 | Anland 开、Termux:X11 关 | **Termux:X11 开**、Anland 关 |
| 音频 | PulseAudio（Anland 会话内置） | PulseAudio，`enable_pulseaudio=1`，socket 桥到 `/tmp/.pulse-socket` |
| Docker | docker + containerd | docker.io + docker-cli + buildx + compose，overlay2 |

安装时向导取值与 [安装](#安装) 相同，只有两处不同：**配置 Termux:X11 选开**、**Anland 选关**。

`--x11` 在这台设备上会触发重启：Droidspaces 以 termux 用户 `app_process` 拉起 Termux:X11 的那条路径会直接把机器带下去。绕开的做法是让容器启动时不带 `--x11`，改把 Termux:X11 的 socket 目录挂进来：

```sh
# 宿主：先在 Android 侧打开 Termux:X11 应用，再启动容器
su -c "droidspaces --name=deb13 \
  --rootfs=/data/local/Droidspaces/Containers/deb13/rootfs \
  --init=/sbin/init --net=nat --dns=223.5.5.5,8.8.8.8 --gpu \
  -B /data/data/com.termux/files/usr/tmp:/mnt/termux start"

# 容器内（root）：把 socket 桥到 /tmp/.X11-unix
mount --bind /mnt/termux/.X11-unix /tmp/.X11-unix
systemctl restart desktop-session
```

首次启动后：

```sh
systemctl status desktop-session.service   # active (running)
dpkg -s plasma-workspace | grep Version    # 4:6.7.4-*
glxinfo -B | grep -E "Vendor|Device"       # freedreno / FD650
```

Plasma 6.7 要求 glibc ≥ 2.43，而 trixie 是 2.41，模板因此从 unstable 取 KDE/Qt/KF6，并把 systemd、udev、dbus 等底座按精确版本钉死在 trixie；构建期还会断言 systemd 运行时与包族都是 257，否则不产出镜像。镜像内置 Docker 26.1、buildx 与 compose，CI 在 runner 上先补装 docker 与 CLI 再调用 `build.sh`。依赖解析与回退方式见 [docs/debian-plasma67.md](docs/debian-plasma67.md)。

## 重建容器

长按容器卡片 → **卸载容器**，输入容器名确认，会删除 rootfs 与设置；之后按上面的向导重新安装。

## 命令行等价形式

```sh
su -c "droidspaces --name=kubuntu \
  --rootfs-img=/data/local/Droidspaces/Containers/kubuntu/rootfs.img \
  --init=/sbin/init --net=nat --dns=223.5.5.5,8.8.8.8 \
  --pulse-audio --gpu --allow-sandboxing start"
```

## 自行构建

**GitHub Actions**：`debian` 分支上推送到该分支，或在 Actions 页面手动触发，都会构建 `Dagu-KDE` 并发布新的 Release，同时更新 `rootfs.json`。本分支的工作流只构建这一个模板，不再产出 `Dagu-Anland` 镜像。

**本地**：

```sh
./build.sh -a aarch64 -i Dagu-Anland -v v20261102-120000
./build.sh -a aarch64 -i Dagu-KDE -v v20261102-120000
```

依赖 Docker（含 buildx）、`jq`、`xz`。产物为 `<模板>-Droidspaces-rootfs-aarch64-<日期>-<版本>.tar.xz`。模板的默认参数放在同目录的 `.env`（如 `templates/aarch64/Dagu-KDE.env`），已导出的环境变量优先。

## 目录结构

```
archs.json                                  架构到 Docker 平台与 CI runner 的映射
build.sh                                    构建单个模板
templates/aarch64/Dagu-Anland.Dockerfile    Ubuntu + Anland 镜像定义
templates/aarch64/Dagu-KDE.Dockerfile       Debian 13 + Plasma 6.7 镜像定义
templates/aarch64/Dagu-KDE.env              该模板的默认构建参数
docs/debian-plasma67.md                     Debian 分支的依赖解析与已知风险
rootfs/                                     覆盖进镜像的文件
  etc/systemd/network/10-droidspaces.network
  etc/systemd/system/{anland-session,ds-nat6,dagu-firstboot}.service
  etc/docker/daemon.json
  etc/profile.d/90-droidspaces-session.sh
  usr/lib/tmpfiles.d/droidspaces-session.conf
  usr/local/bin/{start-anland-session,ds-nat6-up.sh}
  usr/local/sbin/dagu-firstboot
scripts/install-anlandx.sh                  容器侧 Anland 会话组件
scripts/generate_rootfs_json.py             由 Release 资产生成 rootfs.json
rootfs.json                                 供 Droidspaces 添加仓库时读取
```

## 已知限制

- 目录模式的 rootfs 落在 Android 的 f2fs 上，挂载带 `nosuid`，`sudo` 与其它 setuid 程序在内核层面失效；需要 root 请使用稀疏镜像，或用 `droidspaces enter`。
- Anland 6.x 是「每个应用一个窗口」，没有整合成整块桌面的合成器；窗口由 `anland-miniwm` 管理，X11 程序共用一个 Xwayland 窗口。
- IPv6 能否出网取决于宿主网络：宿主没有全局 IPv6 时，容器只有 `fd64:7370::/48` 内的地址，出网走 IPv4。
- `macvlan` 网络模式在 Wi-Fi 上不可用（网卡只接收目的地址为自身的帧），请使用 NAT。
- 声音依赖「配置 PulseAudio」开关；关闭时容器内只有本地空设备。
- 镜像内 `/etc/resolv.conf` 默认为 `1.1.1.1`，向导里填写的 DNS 会覆盖它。
- `Dagu-KDE` 的 glibc 2.43 来自 unstable，属于 Debian 不支持的混装；需要完全发行版原生的镜像时用 `KDE_STACK=trixie` 构建，得到 Plasma 6.3.6。

## 许可

MIT。
