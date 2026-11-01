# Session variables shared by login shells and the desktop session.
# droidspaces.env carries PULSE_SERVER when the container starts with audio.
[ -r /run/droidspaces.env ] && . /run/droidspaces.env

DISPLAY="${DISPLAY:-:5}"
export DISPLAY

if [ -S /tmp/.pulse-socket ] && [ -z "${PULSE_SERVER:-}" ]; then
    PULSE_SERVER="unix:/tmp/.pulse-socket"
    export PULSE_SERVER
fi
