#!/bin/bash
# Build one rootfs template for one architecture.
#
#   ./build.sh -a aarch64 -i Dagu-GNOME [-v v20261101-120000]
#
# The template is a Dockerfile whose last stage is named "export". The exported
# filesystem becomes the rootfs tarball.
set -euo pipefail
cd "$(dirname "$0")"

VERSION="dev"
while getopts "a:i:v:" opt; do
  case $opt in
    a) ARCH="$OPTARG" ;;
    i) NAME="${OPTARG%.Dockerfile}" ;;
    v) VERSION="$OPTARG" ;;
    *) echo "Usage: $0 -a <arch> -i <Name> [-v <version>]" >&2; exit 1 ;;
  esac
done
[ -n "${ARCH:-}" ] && [ -n "${NAME:-}" ] || { echo "Usage: $0 -a <arch> -i <Name> [-v <version>]" >&2; exit 1; }

DOCKERFILE="templates/$ARCH/$NAME.Dockerfile"
[ -f "$DOCKERFILE" ] || { echo "Error: $DOCKERFILE not found" >&2; exit 1; }

PLATFORM=$(jq -er --arg a "$ARCH" '.[$a].platform' archs.json) \
  || { echo "Error: arch '$ARCH' not in archs.json" >&2; exit 1; }

FINAL_NAME="${NAME}-Droidspaces-rootfs-${ARCH}-$(date +%Y%m%d)-${VERSION}.tar.xz"
TEMP_TAR="custom-${ARCH}-${NAME}-rootfs.tar"

echo "========================================================="
echo " Template : $DOCKERFILE"
echo " Platform : $PLATFORM"
echo " Version  : $VERSION"
echo "========================================================="

if ! docker run --rm --platform "$PLATFORM" alpine:3.23 true >/dev/null 2>&1; then
  echo "Host cannot run $PLATFORM natively; installing binfmt/QEMU..."
  docker run --privileged --rm tonistiigi/binfmt --install all >/dev/null
fi

if ! docker buildx inspect droidspaces-builder >/dev/null 2>&1; then
  docker buildx create --name droidspaces-builder --driver docker-container --use
else
  docker buildx use droidspaces-builder
fi
docker buildx inspect --bootstrap >/dev/null

docker buildx build \
  --platform "$PLATFORM" \
  --target export \
  --output "type=tar,dest=$TEMP_TAR" \
  --build-arg DESKTOP="${DESKTOP:-kde}" \
  --build-arg DESKTOP_AUTOSTART="${DESKTOP_AUTOSTART:-true}" \
  --build-arg DISPLAY_BACKEND="${DISPLAY_BACKEND:-anland-wayland}" \
  --build-arg PulseAudio="${PULSEAUDIO:-true}" \
  --build-arg ENABLE_zh_tz_ARG="${ENABLE_ZH_TZ:-true}" \
  --build-arg ENABLE_binfmt_ARG=false \
  --build-arg ENABLE_yj_ARG=false \
  --build-arg ENABLE_mesa_ARG=false \
  --build-arg ENABLE_kfgj_ARG=false \
  --build-arg ENABLE_zip_ARG=true \
  --build-arg ENABLE_docker_ARG=true \
  --build-arg ENABLE_srf_ARG=false \
  --build-arg ENABLE_8gen2_wayland_ARG=false \
  --build-arg ENABLE_nosnap_ARG=true \
  --build-arg ENABLE_systemd257_ARG=true \
  --build-arg USERNAME="${USERNAME:-dagu}" \
  -f "$DOCKERFILE" \
  .

echo "Compressing (xz -T0 -9)..."
xz -T0 -9 -f "$TEMP_TAR"
mv "${TEMP_TAR}.xz" "$FINAL_NAME"

echo "========================================================="
echo " Done: $FINAL_NAME"
echo "========================================================="
