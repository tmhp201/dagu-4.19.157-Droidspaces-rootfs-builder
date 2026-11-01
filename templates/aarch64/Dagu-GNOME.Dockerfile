FROM ubuntu:noble AS customizer

ARG DEBIAN_FRONTEND=noninteractive
ARG USERNAME=dagu
ARG USER_UID=1000

ENV LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8

# APT 并行下载与重试，CI 网络抖动时构建不会整轮失败
RUN printf '%s\n' \
    'Acquire::Queue-Mode "host";' \
    'Acquire::http::Pipeline-Depth "10";' \
    'Acquire::https::Pipeline-Depth "10";' \
    'Acquire::Retries "3";' \
    > /etc/apt/apt.conf.d/99parallel-downloads

RUN apt-get update && apt-get upgrade -y && apt-get install -y --no-install-recommends \
        systemd systemd-sysv systemd-resolved systemd-timesyncd \
        dbus dbus-user-session dconf-cli \
        ubuntu-desktop-minimal ubuntu-session gnome-tweaks \
        gnome-shell-extension-ubuntu-dock gnome-shell-extension-desktop-icons-ng \
        gnome-shell-extension-appindicator \
        network-manager \
        docker.io containerd \
        iptables \
        iproute2 iputils-ping curl wget ca-certificates \
        sudo bash less nano procps psmisc xz-utils tar kmod udev \
        locales tzdata \
        fonts-noto-cjk fonts-dejavu-core \
        x11-xserver-utils xdg-utils \
        pipewire pipewire-pulse wireplumber pulseaudio-utils \
        openssh-server

# Ubuntu 的 GNOME 包依赖 snapd 才有完整会话；容器里不跑 snapd，直接屏蔽
RUN systemctl mask snapd.service snapd.socket 2>/dev/null || true

RUN apt-get clean && rm -rf /var/lib/apt/lists/*

# Docker 命令行：Ubuntu 的 docker.io 不提供 /usr/bin/docker，单独取官方静态包
RUN case "$(dpkg --print-architecture)" in \
        arm64) DOCKER_ARCH=aarch64 ;; \
        amd64) DOCKER_ARCH=x86_64 ;; \
        *) echo "unsupported architecture"; exit 1 ;; \
    esac \
    && curl -fsSL "https://download.docker.com/linux/static/stable/${DOCKER_ARCH}/docker-27.3.1.tgz" \
        -o /tmp/docker-cli.tgz \
    && tar -xzf /tmp/docker-cli.tgz -C /tmp \
    && install -m 0755 /tmp/docker/docker /usr/bin/docker \
    && rm -rf /tmp/docker /tmp/docker-cli.tgz

# 桌面与容器运行所需的基本运行状态
RUN sed -i 's/^# *en_US.UTF-8/en_US.UTF-8/; s/^# *zh_CN.UTF-8/zh_CN.UTF-8/' /etc/locale.gen \
    && locale-gen \
    && ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime \
    && echo "Asia/Shanghai" > /etc/timezone

# Android 的 socket 权限按组下发：没有 aid_inet 时非 root 无法创建 AF_INET 套接字
RUN groupadd -g 3003 aid_inet \
    && groupadd -g 3004 aid_net_raw \
    && groupadd -g 786 droidspaces-gpu 2>/dev/null || true

# Ubuntu 的 base 镜像自带 UID 1000 的 ubuntu 用户，先让位给 dagu
RUN userdel -r ubuntu 2>/dev/null || true
RUN useradd -m -u "$USER_UID" -s /bin/bash "$USERNAME" \
    && echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/90-$USERNAME" \
    && chmod 0440 "/etc/sudoers.d/90-$USERNAME" \
    && for g in video input render aid_inet aid_net_raw droidspaces-gpu docker; do \
           usermod -aG "$g" "$USERNAME" 2>/dev/null || true; \
       done \
    && echo "$USERNAME:$USERNAME" | chpasswd

# 覆盖文件先落盘：desktop-session.service 与 ds-nat6.service 由 rootfs/ 提供，
# 必须在启用单元之前存在。
COPY rootfs/ /
RUN install -d -o "$USER_UID" -g "$USER_UID" /home/"$USERNAME"/.config
RUN chmod 0755 /usr/local/bin/start-desktop-session \
               /usr/local/bin/ds-nat6-up.sh \
               /usr/local/sbin/dagu-firstboot

# Ubuntu 24.04 的 iptables 默认走 nf_tables，4.19 内核上 docker 建链会失败
RUN update-alternatives --set iptables /usr/sbin/iptables-legacy 2>/dev/null || true \
    && update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy 2>/dev/null || true

# 屏蔽 gdm：容器里由 desktop-session.service 直接拉起会话
RUN systemctl disable gdm3 2>/dev/null || true \
    && systemctl mask gdm3.service 2>/dev/null || true

RUN dconf update

RUN systemctl enable systemd-networkd systemd-resolved dbus docker containerd \
        desktop-session ds-nat6 dagu-firstboot ssh \
    && systemctl disable getty@tty1 \
    && systemctl mask systemd-udev-settle.service \
    && : > /etc/machine-id

FROM scratch AS export
LABEL droidspaces.name="Dagu GNOME (Ubuntu 24.04)" \
      droidspaces.distro="Ubuntu" \
      droidspaces.description="Ubuntu 24.04 with GNOME on X11, systemd, Docker and dual-stack networking for Droidspaces on the Xiaomi Pad 5 Pro 12.4." \
      droidspaces.author="dagu-4.19.157-Droidspaces-rootfs-builder"
COPY --from=customizer / /
