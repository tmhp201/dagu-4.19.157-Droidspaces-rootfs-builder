#!/bin/sh
# Assign the container its IPv6 address in the Droidspaces NAT66 prefix and
# install the default route.
#
# systemd-networkd 257 configures IPv6 RA routes through nexthop objects, which
# the 4.19 kernel does not implement, so RA handling is off (see
# 10-droidspaces.network) and the address is derived from the DHCPv4 lease here.
set -eu

IF=eth0
PREFIX=fd64:7370
GATEWAY=fe80::1

i=0
v4=
while [ "$i" -lt 60 ]; do
    v4=$(ip -4 -o addr show dev "$IF" scope global 2>/dev/null \
         | awk '{print $4}' | cut -d/ -f1 | head -n1)
    [ -n "$v4" ] && break
    sleep 1
    i=$((i + 1))
done
[ -n "$v4" ] || { echo "no IPv4 address on $IF" >&2; exit 1; }

IFS=. read -r a b c d <<EOS
$v4
EOS

v6=$(printf '%s::%x:%x' "$PREFIX" $((a * 256 + b)) $((c * 256 + d)))
ip -6 addr replace "$v6/64" dev "$IF"

# The NAT66 gateway only leads anywhere while the host has a global IPv6
# address. Without one the default route turns every IPv6 connect into a
# timeout instead of an immediate failure, so the route is probed and dropped
# again when the upstream does not answer.
ip -6 route replace default via "$GATEWAY" dev "$IF"
if curl -6 -s -m 4 -o /dev/null "http://[2400:3200::1]" 2>/dev/null ||
   ping -6 -c 1 -W 2 2400:3200::1 >/dev/null 2>&1; then
    echo "IPv6 $v6/64 via $GATEWAY"
else
    ip -6 route del default via "$GATEWAY" dev "$IF" 2>/dev/null || true
    echo "IPv6 $v6/64, no upstream: default route left out"
fi
