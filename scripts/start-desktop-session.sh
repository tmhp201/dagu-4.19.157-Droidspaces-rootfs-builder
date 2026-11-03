#!/usr/bin/env bash
set -euo pipefail

config="${DROIDSPACES_DESKTOP_CONFIG:-/etc/droidspaces-desktop.conf}"
[[ -r "$config" ]] || { echo "缺少桌面配置文件：$config" >&2; exit 1; }
source "$config"

case "${DESKTOP:-}:${DISPLAY_BACKEND:-}" in
    none:x11) command_line='exit 0' ;;
    # X11 的 X 服务器由 Termux:X11 提供：容器里只有 socket，没有 Xorg。
    # 启动前等 socket 就绪（最多 15 秒）；等不到就退出，由 path 单元在
    # socket 出现后重新拉起本会话。
    kde:x11)
        command_line='export DISPLAY="${DISPLAY:-:5}"
x11_display="${DISPLAY#*:}"
x11_display="${x11_display%%.*}"
x11_socket="/tmp/.X11-unix/X${x11_display}"
for _ in $(seq 1 150); do
    [[ -S "$x11_socket" ]] && break
    sleep 0.1
done
[[ -S "$x11_socket" ]] || { echo "等待 X11 socket 超时：$x11_socket（Termux:X11 没起来，或 :5 被重复启动后 socket 文件被删）" >&2; exit 1; }
echo "--> [x11] $DISPLAY"
exec startplasma-x11'
        ;;
    kde:anland-wayland) command_line='exec startplasma-wayland' ;;
    kde-mobile:anland-wayland) command_line='exec startplasmamobile' ;;
    gnome:anland-wayland) command_line='exec gnome-session --session=gnome' ;;
    # Anland Next 的会话本体就是包内的 anland-session（会话 D-Bus + wayland
    # 链接 + rootless Xwayland + mini-wm），不经过任何桌面环境。用 /usr/bin 下
    # 的系统路径，不依赖用户家目录里的副本；XDG_RUNTIME_DIR 由脚本自己算，
    # systemd 用户管理器不可用时它只告警继续，所以不需要用户级单元先起来。
    anland-next:anland-wayland) command_line='exec /usr/bin/anland-session' ;;
    niri:anland-wayland) command_line='exec /usr/bin/niri-anland' ;;
    hyprland:anland-wayland) command_line='exec /usr/bin/hyprland-anland' ;;
    mango:anland-wayland) command_line='exec /usr/bin/mango-anland' ;;
    denial:anland-wayland) command_line='exec /usr/bin/denial-anland' ;;
    *)
        echo "不支持的桌面会话：${DESKTOP:-未设置}/${DISPLAY_BACKEND:-未设置}" >&2
        exit 1
        ;;
esac

if [[ "${DROIDSPACES_SESSION_DRY_RUN:-false}" == true ]]; then
    printf '%s\n' "$command_line"
    exit 0
fi

exec /bin/bash -lc "$command_line"
