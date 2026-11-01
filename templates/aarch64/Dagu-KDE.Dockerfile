FROM debian:trixie AS customizer

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

RUN sed -i 's/Components: main/Components: main contrib non-free non-free-firmware/' \
        /etc/apt/sources.list.d/debian.sources 2>/dev/null || true
RUN apt-get update && apt-get upgrade -y && apt-get install -y --no-install-recommends \
        systemd systemd-sysv systemd-resolved systemd-timesyncd \
        dbus dbus-user-session \
        kde-plasma-desktop plasma-workspace plasma-pa kwin-x11 \
        kde-config-gtk-style kde-config-screenlocker kde-spectacle \
        konsole dolphin kate ark firefox-esr \
        qml6-module-qtquick-particles qml6-module-qtwebchannel \
        qml6-module-qtwebengine qml6-module-org-kde-kirigamiaddons-datetime \
        qml6-module-org-kde-kirigamiaddons-formcard
RUN apt-get install -y --no-install-recommends \
        docker.io containerd \
        iproute2 iputils-ping curl wget ca-certificates \
        sudo bash less nano procps psmisc xz-utils tar kmod udev \
        locales tzdata \
        fonts-noto-cjk fonts-dejavu-core \
        x11-xserver-utils xdg-utils \
        pulseaudio-utils \
        openssh-server
RUN apt-get clean && rm -rf /var/lib/apt/lists/*

# 桌面与容器运行所需的基本运行状态
RUN sed -i 's/^# *en_US.UTF-8/en_US.UTF-8/; s/^# *zh_CN.UTF-8/zh_CN.UTF-8/' /etc/locale.gen \
    && locale-gen \
    && ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime \
    && echo "Asia/Shanghai" > /etc/timezone

RUN useradd -m -u "$USER_UID" -s /bin/bash "$USERNAME" \
    && echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/90-$USERNAME" \
    && chmod 0440 "/etc/sudoers.d/90-$USERNAME" \
    && usermod -aG video,input,render "$USERNAME" 2>/dev/null || true

# 覆盖文件先落盘：desktop-session.service 与 ds-nat6.service 由 rootfs/ 提供，
# 必须在启用单元之前存在。
COPY rootfs/ /
RUN install -d -o "$USER_UID" -g "$USER_UID" /home/"$USERNAME"/.config \
    && cp /etc/skel/.config/kwinrc /home/"$USERNAME"/.config/kwinrc \
    && chown -R "$USER_UID":"$USER_UID" /home/"$USERNAME"/.config
RUN chmod 0755 /usr/local/bin/start-desktop-session \
               /usr/local/bin/ds-nat6-up.sh \
               /usr/local/sbin/dagu-firstboot

# 这些单元由 rootfs 预置的配置驱动：网络、桌面会话、容器内的 docker
RUN systemctl enable systemd-networkd systemd-resolved dbus docker containerd \
        desktop-session ds-nat6 dagu-firstboot ssh \
    && systemctl disable getty@tty1 \
    && systemctl mask systemd-udev-settle.service \
    && : > /etc/machine-id

FROM scratch AS export
LABEL droidspaces.name="Dagu KDE (Debian 13)" \
      droidspaces.distro="Debian" \
      droidspaces.description="Debian 13 with KDE Plasma on X11, systemd, Docker and dual-stack networking for Droidspaces on the Xiaomi Pad 5 Pro 12.4." \
      droidspaces.author="dagu-4.19.157-Droidspaces-rootfs-builder"
COPY --from=customizer / /
