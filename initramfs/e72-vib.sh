#!/bin/sh
# vib [ms]: vibrate for ms milliseconds (default 150, driver limit 2000); vib 0 stops
f=$(echo /sys/devices/platform/soc/*vibra/pulse_ms)
[ -w "$f" ] || { echo "vib: no vibra driver" >&2; exit 1; }
echo "${1:-150}" > "$f"
