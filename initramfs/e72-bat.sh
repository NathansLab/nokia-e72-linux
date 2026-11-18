#!/bin/sh
# /bin/bat: battery and charger in one line
B=/sys/class/power_supply/battery
C=$(ls -d /sys/class/power_supply/bq2415* 2>/dev/null | head -n 1)
printf '%s%%  %s mV  %s mA  %s.%s C  %s' "$(cat $B/capacity)" "$(($(cat $B/voltage_now) / 1000))" \
	"$(($(cat $B/current_now) / 1000))" "$(($(cat $B/temp) / 10))" "$(($(cat $B/temp) % 10))" "$(cat $B/status)"
[ -n "$C" ] && printf '  (charger %s, fault %s)' "$(cat $C/mode)" "$(cat $C/fault_status)"
echo
