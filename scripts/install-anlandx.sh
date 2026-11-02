#!/bin/bash
# Install the Anland 6.x session for the desktop user.
#
# 6.x replaced the per-compositor display protocol with plain Wayland: the host
# daemon (the anland-awl module) terminates each client's connection and turns
# every toplevel into an Android window, so the container only needs the
# session plumbing — a wayland socket, a rootless Xwayland for X11 apps and the
# mini window manager. That is what anlandx installs; the patched KWin used by
# 5.x must not be installed, it would take over the display path.
set -euo pipefail

VERSION="${ANLAND_VERSION:-6.2}"
USERNAME="${1:-dagu}"

apt-get update
apt-get install -y --no-install-recommends \
    build-essential pkg-config curl unzip ca-certificates \
    libx11-dev libxext-dev libxfixes-dev libxrandr-dev libxi-dev \
    libxtst-dev libxrender-dev libxcomposite-dev libxkbfile-dev \
    libwayland-dev wayland-protocols

# The installer drops privileges to the desktop user, which needs to read the
# extracted tree, so build it somewhere world-traversable instead of a private
# mktemp directory.
tmp=/opt/anlandx-src
rm -rf "$tmp"
install -d -m 0755 "$tmp"
trap 'rm -rf "$tmp"' EXIT

curl -fsSL -o "$tmp/anland.zip" \
    "https://github.com/SuperTurtleDev/anland/releases/download/${VERSION}/anland-build.2.zip"
unzip -o -q "$tmp/anland.zip" anlandx.tar.gz -d "$tmp"
tar xzf "$tmp/anlandx.tar.gz" -C "$tmp"
chmod -R a+rX "$tmp"

# The session installs into the user's home and builds only the small helpers;
# the distro Xwayland is good enough (ANLAND_XWAYLAND=0) because the GL fixes
# it patches are for the Mesa kgsl path that anland does not use.
su - "$USERNAME" -c "ANLAND_XWAYLAND=0 bash '$tmp/anlandx/setupanlandx.sh'"
