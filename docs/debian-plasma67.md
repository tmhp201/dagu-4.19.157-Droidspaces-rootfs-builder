# Debian 13 + Plasma 6.7 + X11 + GPU 渲染

`debian` 分支交付的第二个模板 `templates/aarch64/Dagu-KDE.Dockerfile`：Debian 13 (trixie) 底座，KDE Plasma 6.7.4 桌面，显示走 Termux:X11（`DISPLAY=:5`），渲染走 Mesa + `kgsl`（Freedreno），面向 dagu（`4.19.157`）的 Droidspaces 容器。

## 结论

可行，但有一个不能绕开的代价：**Plasma 6.7 必须把 glibc 从 trixie 的 2.41 升到 2.43**。

| 结论 | 证据 |
| --- | --- |
| Debian 13 自带 Plasma 6.3.6，trixie-backports 没有 Plasma | trixie 的 `plasma-workspace 4:6.3.6-2`；`trixie-backports` 查 `plasma-desktop` 为 "Package not available in this suite" |
| 6.7.4 只在 unstable/forky | `plasma-workspace 4:6.7.4-2`、`plasma-desktop 4:6.7.4-1+b1`、`kwin-x11 4:6.7.4-1+b1`（arm64 均有） |
| Qt 6.11.2 要求 glibc ≥ 2.43 | `libqt6gui6:arm64=6.11.2+dfsg-7 依赖 libc6 (>= 2.43)`，trixie 只有 2.41 |
| X11 会话随 6.7 一起结束 | 上游在 Plasma 6.8 去掉了 X11 会话，6.7 是最后一个带 `kwin-x11` 的版本；unstable 里 `plasma-workspace` 仍提供 `/usr/bin/startplasma-x11` 与 `/usr/share/xsessions/plasmax11.desktop` |
| 4.19 内核只能配 systemd 257 | 与 Anland 分支同一个约束：systemd 262 依赖的接口 4.19 没有 |

所以本模板做的是「trixie 底座 + unstable 的 KDE 栈」：底座（systemd、udev、dbus、kmod、init-system-helpers）按精确版本钉死在 trixie，只让 KDE/Qt/KF6 以及它们硬依赖的少数库走 unstable。

## 依赖解析结果

在 arm64 的 trixie + unstable 索引上，用 61 个 unstable 目标包跑 `apt-get -s install --no-install-recommends`（prefs 只有 trixie 精确版本 pin 1001）：

```
升级了 18 个软件包，新安装了 880 个软件包，要卸载 0 个软件包
```

| 类别 | 包 |
| --- | --- |
| glibc 族（被迫） | `libc6 2.41 → 2.43`、`libc-bin`、`locales`、`libc-l10n` |
| 编译器运行时 | `libstdc++6`、`libgcc-s1` |
| 基础库 | `libpcre2-8-0`、`libexpat1`、`libelf1t64`、`zlib1g`、`dmidecode` |
| ncurses 族 | `ncurses-base`、`ncurses-bin`、`ncurses-term`、`libncursesw6`、`libtinfo6` |
| dbus 数据包 | `dbus-session-bus-common`、`dbus-system-bus-common`（`dbus-daemon` 仍是 trixie 1.16.2） |

systemd、udev、dbus-daemon、libdbus-1-3、kmod 全部保持 trixie 版本；`debian_unstable_verify` 在装完 KDE 后把 unstable 源排除在外，逐包比对「已安装版本」与「trixie 候选版本」，两者不一致即构建失败。trixie-updates 的补丁版本可以通过，unstable 的版本不能。

三处与 apt 有关的实现约束（`scripts/desktops/kde.sh` 内有对应注释）：

| 约束 | 原因 | 处理 |
| --- | --- | --- |
| `Pin: release n=unstable` 不生效 | 镜像的 suite 是 `sid`，apt 按 sources 里写的套件名匹配，pin 静默失效 | pin 与 sources 用同一个套件名（默认 `sid`） |
| `Package: *` 低优先级兜底 | 求解器在 `(= 精确版本)` 依赖上先挑高优先级候选再报不可安装，`breeze` 因 `breeze-wallpaper (= 4:6.7.4-1)` 失败 | 不加兜底 pin，只钉底座 |
| `dbus-x11` 作为 unstable 目标 | 它的 `dbus-daemon (= 1.16.2-8)` 会把整个 dbus 拉到 unstable 并卸载 `dbus` 元包 | 从 unstable 目标列表移除 |

## 显示与渲染

| 环节 | 配置 |
| --- | --- |
| 显示服务 | Droidspaces `--x11`：Android 端起 Termux:X11，socket `/tmp/.X11-unix/X5` 挂进容器，登录 shell 得到 `DISPLAY=:5` |
| 会话 | `/etc/droidspaces-desktop.conf` 写 `DESKTOP=kde`、`DISPLAY_BACKEND=x11`；`desktop-session.service` 以 1000 号用户执行 `/usr/local/bin/start-desktop-session` → `startplasma-x11` |
| 渲染 | `/etc/environment` 写 `MESA_LOADER_DRIVER_OVERRIDE=kgsl`、`TU_DEBUG=noconform`；Mesa 来自 `install-mesa`（`debian_trixie_arm64` 包，arm64 专用构建） |
| 合成器 | `KDE_COMPOSITING=true` 时 kwin 的 OpenGL 合成器走 Mesa/kgsl；默认关闭（`kwinrc` `[Compositing] Enabled=false`）：真机上打开后 kwin 能拿到渲染上下文，但画面不出现在 Termux:X11 上（黑屏），只让应用自己用 GPU 绘制 |
| GPU 节点 | Droidspaces `--gpu` 镜像 `/dev/kgsl-3d0`、`/dev/dri/renderD*`；容器用户需在 `droidspaces-gpu` 组（gid 786，构建时已加） |

4.19 厂商内核没有 `msm` DRM，只有 `/dev/kgsl-3d0`，因此不能走 Zink/VirGL 那套；Freedreno 的 `kgsl` 后端是唯一的硬件 GL 路径。Mesa-for-Android 的 `libEGL_mesa`/`libgallium` 链接 `libLLVM.so.19.1`，所以镜像必须装发行版的 `libllvm19`（trixie 自带 `1:19.1.7-3+b1`）；缺它时 `libEGL_mesa` 加载失败，`glxinfo` 报 `couldn't find RGB GLX visual or fbconfig`，kwin 与 plasmashell 都起不来。

## 构建

```sh
./build.sh -a aarch64 -i Dagu-KDE -v v20261102-120000
```

`templates/aarch64/Dagu-KDE.env` 提供默认值，环境变量优先：

| 变量 | 默认 | 说明 |
| --- | --- | --- |
| `KDE_STACK` | `unstable` | `trixie` 时退回发行版原生 Plasma 6.3.6，完全不碰 unstable |
| `DISPLAY_BACKEND` | `x11` | 只能是 `x11`（KDE + Anland Wayland 需要 Anland 补丁版 KWin） |
| `KDE_COMPOSITING` | `false` | `true` 时打开 kwin 的 OpenGL 合成器 |
| `ENABLE_MESA` | `true` | 装 arm64 的 Mesa；关掉则用发行版 Mesa（无 kgsl 驱动） |
| `KDE_UNSTABLE_SNAPSHOT` | 空 | 填 snapshot.debian.org 的时间戳可复现构建，套件改用 `unstable` |
| `ENABLE_SYSTEMD257` | `true` | 调用 `systemd257.sh` 做版本闸门；Debian 13 已是 257，脚本检测后跳过 |

### systemd 与 4.19

4.19 内核上验证过的 systemd 是 257，本镜像在两个层面把它固定下来：

- 构建期：`KDE_DEBIAN_BASE_PINNED` 把 systemd 家族按精确版本钉在 trixie，`debian_unstable_verify` 在装完 KDE 后逐包比对已安装版本与 trixie 候选版本，不一致即失败；模板随后再断言 `systemctl --version` 的主版本为 257、`systemd`/`udev`/`libsystemd*`/`libudev*` 全部落在 `257.*`。断言失败直接中断构建，不会产出镜像。
- 运行期：发行版自带的 257 即目标版本，不再替换整套 systemd；networkd 仍使用 `rootfs/` 里的 `10-droidspaces.network`（`IPv6AcceptRA=no`）与 `ds-nat6.service`，绕开 networkd 257 用 nexthop 对象下发 RA 路由、而 4.19 不支持的老问题。

`ENABLE_SYSTEMD257=true` 调用的是与上游同一份 `systemd257.sh`：它只对 Ubuntu 26.04、Fedora 43/44 和 Arch 提供预构建包族，遇到已经是 257 的发行版会记录一行后返回，既不会重装也不会报错；只有「systemd 不是 257 且发行版没有预构建包族」时才失败。改成 `false` 只跳过这一层检查，构建期的版本断言仍然生效。

## 使用

下载 `Dagu-KDE-Droidspaces-rootfs-aarch64-*.tar.xz`，在 Droidspaces 里从文件导入。向导取值：

| 步骤 | 选项 | 取值 |
| --- | --- | --- |
| 配置 · 网络 | 网络模式 / DNS | `NAT` / `223.5.5.5,8.8.8.8` |
| 配置 · 集成与硬件 | GPU 访问 | 开 |
| 配置 · 集成与硬件 | 配置 Termux:X11 | **开** |
| 配置 · 集成与硬件 | Anland | 关 |
| 配置 · 集成与硬件 | PulseAudio | 开（socket） |
| 配置 · 沙箱 | 允许沙箱 | 开 |

命令行等价形式：

```sh
droidspaces --name=kde --rootfs-img=dagu-kde.img --init=/sbin/init \
  --net=nat --dns=223.5.5.5,8.8.8.8 --gpu --x11 --pulse-audio --allow-sandboxing start
```

## 验证

容器内：

```sh
cat /etc/droidspaces-desktop.conf          # DESKTOP=kde / DISPLAY_BACKEND=x11
systemctl status desktop-session.service   # active (running)
startplasma-x11 --version                  # Plasma 6.7.x
dpkg -s plasma-workspace | grep Version    # 4:6.7.4-*
systemd --version                          # systemd 257
glxinfo -B | grep -E "renderer|OpenGL"     # Vendor: freedreno / Device: FD650 / direct rendering: Yes
glxgears -info                             # 5 秒约 600 帧（vsync 封顶 120 FPS）
```

宿主：

```sh
su -c "cat /run/droidspaces/containers/kde/container.config" | grep -E "enable_x11|enable_gpu_mode"
```

## 已知风险

| 风险 | 说明 | 回退 |
| --- | --- | --- |
| glibc 混装 | 2.43 的 `libc6` 配 257 的 systemd 属于 Debian 不支持的 partial upgrade | `KDE_STACK=trixie` 重新构建，退回 Plasma 6.3.6 |
| kwin 合成器 | 打开后 kwin 能初始化 OpenGL，但画面不出现在 Termux:X11（实测整屏黑，只剩光标）；GLX/DRI3 + kgsl 的呈现路径还没打通 | 默认关闭（`KDE_COMPOSITING=false`）；应用仍走 GPU 的 GLX/EGL |
| 容器网络 | Droidspaces `--net=nat` 依赖容器内 DHCP 客户端；`systemd-networkd` 被屏蔽时 eth0 拿不到地址、DNS 全失效 | 镜像已保留 networkd/resolved，只屏蔽 udevd 与 NetworkManager |
| Plasma 6.8 | 上游去掉 X11 会话，本方案停在 6.7.x 不再上移 | 无：再往上必须转 Wayland |
| Mesa 版本 | `install-mesa` 装的是预编译 arm64 包，版本跟随上游发布 | `install-mesa --uninstall` 回到发行版 Mesa（kgsl 不可用） |

## 复现依赖解析

不需要设备或构建机，用 arm64 索引即可验证 apt 计划（索引取自 tuna 镜像）：

```sh
export APT_CONFIG=/tmp/deb-sim/apt.conf   # 指向 arm64 的 trixie + sid 索引与合成 status
apt-get -s install --no-install-recommends $(sed 's|$|/sid|' pkgs.txt)
```

61 个 unstable 目标、18 个升级、880 个新装、0 卸载，即上面的表。
