#!/usr/bin/env bash
set -euo pipefail

source "${ROOTFS_DIR:-}/etc/os-release"

configure_environment() {
    local backend="${1:-}"
    local environment_file="${ROOTFS_DIR:-}/etc/environment"
    local assignment key
    local -a assignments=(XCURSOR_SIZE=48 XDG_SESSION_CLASS=user)

    case "$backend" in
        x11)
            assignments+=(DISPLAY=:5)
            ;;
        anland-wayland)
            assignments+=(
                WAYLAND_DISPLAY=wayland-0
                QT_QPA_PLATFORM=wayland
                ANLAND=1
                ANLAND_SOCKET=/run/display.sock
                ANLAND_DRM_DEVICE=/dev/dri/renderD128
                ANLAND_SKIP_IMPLICIT_SYNC_WAIT=1
            )
            case "$ID" in
                arch|archarm|archlinux)
                    assignments+=(XWAYLAND_GBM_DEVICE=/dev/dri/renderD128)
                    ;;
            esac
            ;;
        *)
            echo "KDE 显示后端无效：$backend" >&2
            return 1
            ;;
    esac

    touch "$environment_file"
    for assignment in "${assignments[@]}"; do
        key="${assignment%%=*}"
        grep -q "^${key}=" "$environment_file" || printf '%s\n' "$assignment" >> "$environment_file"
    done
}

# Debian 13 的 Plasma 6.7 只能来自 unstable：trixie 自带 6.3.6，backports 没有 Plasma。
# sid 的 Qt 6.11.2 依赖 glibc >= 2.43，而 trixie 只有 2.41，所以走 6.7 必然要升级 glibc；
# 但 4.19 厂商内核只验证过 systemd 257，运行时栈（systemd/udev/dbus）必须钉死在 trixie。
readonly KDE_DEBIAN_BASE_PINNED=(
    systemd systemd-sysv libsystemd0 libsystemd-shared libudev1 udev
    libpam-systemd systemd-resolved systemd-timesyncd
    dbus dbus-daemon dbus-bin dbus-user-session libdbus-1-3
    init-system-helpers kmod
)


readonly KDE_DEBIAN_NATIVE_PACKAGES=(
    dbus-x11 x11-xserver-utils fonts-noto-cjk fonts-noto-color-emoji
    kde-plasma-desktop pipewire pipewire-alsa pipewire-pulse wireplumber
    powerdevil kscreen plasma-pa ark kwin-x11 upower konsole
    dolphin kate kinfocenter mesa-utils pulseaudio-utils vulkan-tools
    desktop-base dbus-user-session aha clinfo dmidecode libdisplay-info-bin
    wayland-utils xserver-xorg kfind plasma-systemmonitor filelight glmark2 vkmark
    systemsettings kde-config-screenlocker kio-extras xdg-user-dirs
    dolphin-plugins ffmpegthumbs kdegraphics-thumbnailers
    kimageformat6-plugins webext-plasma-browser-integration libcanberra-pulse
    gstreamer1.0-plugins-base gstreamer1.0-plugins-good sound-theme-freedesktop
)

readonly KDE_DEBIAN_UNSTABLE_PACKAGES=(
    plasma-desktop plasma-desktop-data plasma-workspace kwin-x11
    plasma-pa kscreen powerdevil systemsettings kinfocenter plasma-systemmonitor
    kde-config-screenlocker kio-extras xdg-desktop-portal-kde
    ark konsole dolphin kate kfind filelight dolphin-plugins
    ffmpegthumbs kdegraphics-thumbnailers kimageformat6-plugins
    breeze breeze-icon-theme desktop-base webext-plasma-browser-integration
    fonts-noto-cjk fonts-noto-color-emoji qt6-translations-l10n
    xserver-xorg x11-xserver-utils x11-utils xauth libxcb-cursor0 xkb-data
    pipewire pipewire-alsa pipewire-pulse wireplumber libcanberra-pulse
    gstreamer1.0-plugins-base gstreamer1.0-plugins-good sound-theme-freedesktop
    pulseaudio-utils alsa-utils
    mesa-utils vulkan-tools clinfo glmark2 vkmark
    upower dmidecode libdisplay-info-bin wayland-utils aha
    xdg-user-dirs dbus-user-session kde-cli-tools polkit-kde-agent-1
    libpam-kwallet5
)

# apt 的 `Pin: release n=<suite>` 匹配的是 sources 里写的套件名，不是 Release 文件的
# Suite 字段：镜像的 `sid` 写 `unstable` 会匹配不上，pin 会静默失效。两边必须同名。
debian_unstable_source() {
    local base="${KDE_UNSTABLE_BASE:-https://deb.debian.org/debian}"
    local snapshot="${KDE_UNSTABLE_SNAPSHOT:-}"
    local suite="${KDE_UNSTABLE_SUITE:-}"

    if [ -n "$snapshot" ]; then
        printf '%s %s\n' "https://snapshot.debian.org/archive/debian/${snapshot}" "${suite:-unstable}"
    else
        printf '%s %s\n' "$base" "${suite:-sid}"
    fi
}

debian_unstable_add_repository() {
    local uri suite package version

    read -r uri suite < <(debian_unstable_source)

    cat > /etc/apt/sources.list.d/20-droidspaces-unstable.sources <<EOF
Types: deb
URIs: ${uri}
Suites: ${suite}
Components: main
Architectures: arm64
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
EOF

    # 只钉基础运行时，其余交给求解器。不加 `Package: *` 的低优先级兜底：
    # apt 在 `(= 精确版本)` 依赖上先挑高优先级候选再报不可安装，整个 6.7 栈会解析
    # 失败（breeze 依赖 breeze-wallpaper (= 4:6.7.4-1) 时即如此）。
    {
        printf '# 4.19 厂商内核只验证过 systemd 257：运行时栈钉在 trixie，被迫升级即失败。\n'
        for package in "${KDE_DEBIAN_BASE_PINNED[@]}"; do
            version="$(dpkg-query -W -f='${Version}' "$package" 2>/dev/null || true)"
            [ -n "$version" ] || continue
            printf 'Package: %s\nPin: version %s\nPin-Priority: 1001\n\n' "$package" "$version"
        done
    } > /etc/apt/preferences.d/10-droidspaces-unstable.pref

    apt-get update
}

# 只读 trixie 源解析候选版本：把 unstable 源排除在 sourceparts 之外，
# 这样候选版本就是 trixie / trixie-updates 里最高的那个。
debian_trixie_version() {
    local package="$1" source trixie_dir

    trixie_dir="$(mktemp -d -t droidspaces-trixie.XXXXXXXX)"
    mkdir -p "$trixie_dir/prefs"
    : > "$trixie_dir/preferences"
    if [ -f /etc/apt/sources.list ]; then
        cp /etc/apt/sources.list "$trixie_dir/sources.list"
    else
        : > "$trixie_dir/sources.list"
    fi
    for source in /etc/apt/sources.list.d/*; do
        [ -f "$source" ] || continue
        case "$source" in
            */20-droidspaces-unstable.sources) continue ;;
        esac
        cp "$source" "$trixie_dir/"
    done

    # 同时忽略构建期写的 pin：它们把候选版本钉在安装前的 trixie 版本上，
    # 会让 trixie-updates 的补丁版本看起来像越界。
    LC_ALL=C apt-cache \
        -o Dir::Etc::sourcelist="$trixie_dir/sources.list" \
        -o Dir::Etc::sourceparts="$trixie_dir" \
        -o Dir::Etc::preferences="$trixie_dir/preferences" \
        -o Dir::Etc::preferencesparts="$trixie_dir/prefs" \
        policy "$package" 2>/dev/null | sed -n 's/^ *Candidate: *//p'
    rm -rf "$trixie_dir"
}

debian_unstable_verify() {
    local package current trixie_version version

    for package in plasma-desktop plasma-workspace kwin-x11; do
        version="$(dpkg-query -W -f='${Version}' "$package" 2>/dev/null || true)"
        case "$version" in
            4:6.7.*) printf '[kde] %s %s\n' "$package" "$version" ;;
            *)
                echo "Plasma 6.7 栈安装失败：${package} 版本为 '${version:-未安装}'，期望 4:6.7.x" >&2
                return 1
                ;;
        esac
    done

    for package in /usr/bin/startplasma-x11 /usr/share/xsessions/plasmax11.desktop; do
        [ -e "$package" ] || { echo "Plasma 6.7 缺少 X11 会话入口：$package" >&2; return 1; }
    done

    # 运行时栈必须停在 trixie：systemd 一旦被拉到 262，镜像在 4.19 上起不来。
    # 允许 trixie-updates 的补丁版本，但不接受 unstable 的版本。
    for package in "${KDE_DEBIAN_BASE_PINNED[@]}"; do
        current="$(dpkg-query -W -f='${Version}' "$package" 2>/dev/null || true)"
        [ -n "$current" ] || continue
        trixie_version="$(debian_trixie_version "$package")"
        if [ -n "$trixie_version" ] && [ "$current" != "$trixie_version" ]; then
            echo "运行时栈没有停在 trixie：$package 为 $current，trixie 只有 $trixie_version" >&2
            return 1
        fi
    done

    printf '[kde] glibc %s / Qt %s / systemd %s\n' \
        "$(dpkg-query -W -f='${Version}' libc6)" \
        "$(dpkg-query -W -f='${Version}' libqt6core6t64)" \
        "$(dpkg-query -W -f='${Version}' systemd)"
}

install_debian_native() {
    apt-get install -y --no-install-recommends "${KDE_DEBIAN_NATIVE_PACKAGES[@]}"
}

install_debian_unstable() {
    local -a targets=()
    local package suite

    read -r _ suite < <(debian_unstable_source)

    debian_unstable_add_repository

    for package in "${KDE_DEBIAN_UNSTABLE_PACKAGES[@]}"; do
        targets+=("${package}/${suite}")
    done

    apt-get install -y --no-install-recommends "${targets[@]}"
    debian_unstable_verify

    # 装完就摘掉 unstable 源：容器里只面对 trixie，`apt upgrade` 不会触发 Debian
    # 不支持的 partial upgrade；Plasma 组件就此停在 6.7.4。
    {
        printf 'stack=unstable\n'
        printf 'plasma=%s\n' "$(dpkg-query -W -f='${Version}' plasma-workspace)"
        printf 'qt=%s\n' "$(dpkg-query -W -f='${Version}' libqt6core6t64)"
        printf 'glibc=%s\n' "$(dpkg-query -W -f='${Version}' libc6)"
        printf 'systemd=%s\n' "$(dpkg-query -W -f='${Version}' systemd)"
    } > /etc/droidspaces-kde-stack
    rm -f /etc/apt/sources.list.d/20-droidspaces-unstable.sources \
        /etc/apt/preferences.d/10-droidspaces-unstable.pref
}

install_apt() {
    case "$ID:$VERSION_ID" in
        debian:13)
            if [ "${KDE_STACK:-trixie}" = "unstable" ]; then
                install_debian_unstable
            else
                install_debian_native
            fi
            ;;
        ubuntu:24.04)
            apt-get install -y --no-install-recommends \
                dbus-x11 x11-xserver-utils fonts-noto-cjk fonts-noto-color-emoji kde-plasma-desktop kubuntu-settings-desktop kubuntu-wallpapers \
                pipewire pipewire-alsa pipewire-pulse wireplumber powerdevil kscreen plasma-pa ark kwin-x11 upower konsole \
                dolphin kate kinfocenter mesa-utils pulseaudio-utils vulkan-tools dbus-user-session aha clinfo dmidecode libdisplay-info-bin wayland-utils xserver-xorg \
                kfind plasma-systemmonitor filelight glmark2 systemsettings kde-config-screenlocker kio-extras xdg-user-dirs dolphin-plugins ffmpegthumbs kdegraphics-thumbnailers \
                kimageformat-plugins plasma-browser-integration libcanberra-pulse gstreamer1.0-plugins-base gstreamer1.0-plugins-good sound-theme-freedesktop \
                polkit-kde-agent-1 libpam-systemd libpam-modules libpam-kwallet5 language-pack-kde-zh-hans language-pack-zh-hans qt6-translations-l10n
            ;;
        ubuntu:25.10|ubuntu:26.04)
            apt-get install -y --no-install-recommends \
                dbus-x11 x11-xserver-utils fonts-noto-cjk fonts-noto-color-emoji kde-plasma-desktop kubuntu-settings-desktop kubuntu-wallpapers \
                pipewire pipewire-alsa pipewire-pulse wireplumber powerdevil kscreen plasma-pa ark kwin-x11 upower konsole \
                dolphin kate kinfocenter mesa-utils pulseaudio-utils vulkan-tools dbus-user-session aha clinfo dmidecode libdisplay-info-bin wayland-utils xserver-xorg \
                kfind plasma-systemmonitor filelight glmark2 vkmark systemsettings kde-config-screenlocker kio-extras xdg-user-dirs dolphin-plugins ffmpegthumbs kdegraphics-thumbnailers \
                kimageformat6-plugins plasma-browser-integration libcanberra-pulse gstreamer1.0-plugins-base gstreamer1.0-plugins-good sound-theme-freedesktop \
                polkit-kde-agent-1 libpam-systemd libpam-modules libpam-kwallet5 plasma-session-x11 language-pack-kde-zh-hans language-pack-zh-hans qt6-translations-l10n
            ;;
        *)
            echo "KDE 不支持当前系统：$ID $VERSION_ID" >&2
            return 1
            ;;
    esac
}

install_fedora() {
    case "$VERSION_ID" in
        43|44) ;;
        *) echo "KDE 不支持 Fedora $VERSION_ID" >&2; return 1 ;;
    esac

    dnf install -y --setopt=install_weak_deps=False \
        dbus-x11 xrandr xset xrdb xhost google-noto-cjk-fonts google-noto-emoji-color-fonts plasma-desktop pipewire pipewire-alsa pipewire-pulseaudio wireplumber powerdevil kscreen plasma-pa ark kwin upower konsole \
        dolphin kate kinfocenter glx-utils pulseaudio-utils vulkan-tools fedora-logos aha clinfo dmidecode libdisplay-info wayland-utils xorg-x11-server-Xorg \
        kfind plasma-systemmonitor filelight glmark2 vkmark systemsettings kscreenlocker kio-extras xdg-user-dirs dolphin-plugins ffmpegthumbs kdegraphics-thumbnailers \
        kf6-kimageformats plasma-browser-integration libcanberra-gtk3 gstreamer1-plugins-base gstreamer1-plugins-good sound-theme-freedesktop plasma-milou plasma-workspace plasma-workspace-x11 kwin-x11
}

install_arch_portal_placeholder() {
    local package
    local portal_stub_dir portal_stub_archive portal_stub_readme portal_stub_size
    local -a portal_packages=()

    # plasma-integration requires xdg-desktop-portal-kde. Remove the real portal
    # packages, then satisfy package dependencies with an empty local provider.
    for package in xdg-desktop-portal-kde xdg-desktop-portal-gtk xdg-desktop-portal; do
        if pacman -Qq "$package" >/dev/null 2>&1; then
            portal_packages+=("$package")
        fi
    done
    if ((${#portal_packages[@]})); then
        pacman -Rdd --noconfirm "${portal_packages[@]}"
    fi
    if pacman -Qq droidspaces-noop-xdg-desktop-portals >/dev/null 2>&1; then
        return 0
    fi

    portal_stub_dir="$(mktemp -d /tmp/droidspaces-noop-portals.XXXXXXXX)"
    portal_stub_archive="$portal_stub_dir/droidspaces-noop-xdg-desktop-portals-1-1-any.pkg.tar.zst"
    portal_stub_readme="$portal_stub_dir/usr/share/doc/droidspaces-noop-xdg-desktop-portals/README"
    install -d "${portal_stub_readme%/*}"
    printf '%s\n' \
        'Dependency placeholder for the Droidspaces KDE container profile.' \
        'This package provides no XDG desktop portal implementation or service.' \
        > "$portal_stub_readme"
    portal_stub_size="$(wc -c < "$portal_stub_readme")"

    cat > "$portal_stub_dir/.PKGINFO" <<EOF
pkgname = droidspaces-noop-xdg-desktop-portals
pkgbase = droidspaces-noop-xdg-desktop-portals
pkgver = 1-1
pkgdesc = Empty dependency provider that disables XDG desktop portal packages
url = https://github.com/Goldzxcbug/Droidspaces-rootfs-Desktop-builder
builddate = $(date +%s)
packager = Droidspaces rootfs desktop profile
size = $portal_stub_size
arch = any
license = custom
provides = xdg-desktop-portal
provides = xdg-desktop-portal-kde
provides = xdg-desktop-portal-gtk
EOF

    # Local package signatures may be required by the host pacman.conf.
    sed \
        -e '/^[[:space:]]*LocalFileSigLevel[[:space:]]*=/d' \
        -e '/^\[options\][[:space:]]*$/a LocalFileSigLevel = Optional' \
        /etc/pacman.conf > "$portal_stub_dir/pacman.conf"
    tar --zstd -cf "$portal_stub_archive" -C "$portal_stub_dir" \
        .PKGINFO usr/share/doc/droidspaces-noop-xdg-desktop-portals/README
    pacman --config "$portal_stub_dir/pacman.conf" -U --noconfirm "$portal_stub_archive"
    rm -rf -- "$portal_stub_dir"
}

install_arch() {
    install_arch_portal_placeholder

    pacman -S --noconfirm --needed \
        xorg-xrandr noto-fonts-cjk noto-fonts-emoji plasma-desktop pipewire pipewire-alsa pipewire-pulse wireplumber powerdevil kscreen plasma-pa ark kwin upower konsole \
        dolphin kate kinfocenter mesa-utils libpulse vulkan-tools aha clinfo dmidecode wayland-utils xorg-server \
        kfind plasma-systemmonitor filelight glmark2 vkmark systemsettings kscreenlocker kio-extras xdg-user-dirs dolphin-plugins ffmpegthumbs kdegraphics-thumbnailers \
        kimageformats plasma-browser-integration libcanberra gstreamer gst-plugins-base gst-plugins-good sound-theme-freedesktop
}

install_profile() {
    case "$ID" in
        debian|ubuntu) install_apt ;;
        fedora) install_fedora ;;
        arch|archarm|archlinux) install_arch ;;
        *) echo "KDE 不支持当前发行版：$ID" >&2; return 1 ;;
    esac
}

case "${1:-install}" in
    install) install_profile ;;
    configure-environment) configure_environment "${2:-}" ;;
    *) echo "KDE profile 操作无效：$1" >&2; exit 1 ;;
esac
