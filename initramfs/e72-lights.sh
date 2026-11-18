#!/bin/sh
# /bin/e72-lights: display and keyboard light follow the keys.
# on at a key press, dimmed after $1 s (15), off after another $2 s (45).
# with the ambient light sensor (tsl2563) the "on" level follows the room
# light and the keyboard light stays off in daylight; without it: $3 (120).
P=/sys/class/backlight/panel/brightness
K=/sys/class/backlight/gazoo-pwm0/brightness
ON=${3:-120}
EV=
for n in /sys/class/input/event*/device/name; do
	case "$(cat $n 2>/dev/null)" in *keyboard*) EV=/dev/input/$(basename ${n%/device/name}) ;; esac
done
[ -n "$EV" ] || EV=/dev/input/event1
LUX=$(echo /sys/bus/iio/devices/iio:device*/in_illuminance0_input)
lit() {
	p=$ON; k=15
	if [ -r "$LUX" ] && l=$(cat "$LUX" 2>/dev/null) && [ -n "$l" ]; then
		if [ "$l" -lt 5 ]; then p=40; k=10
		elif [ "$l" -lt 50 ]; then p=90; k=15
		elif [ "$l" -lt 400 ]; then p=150; k=0
		else p=255; k=0; fi
	fi
	echo $p > $P; echo $k > $K
}
st=on; lit
while :; do
	case $st in
	on)  t=${1:-15} ;;
	dim) t=${2:-45} ;;
	off) t=86400 ;;
	esac
	if busybox timeout $t dd if=$EV of=/dev/null bs=16 count=1 2>/dev/null; then
		[ $st = on ] || lit
		st=on
	elif [ $st = on ]; then
		st=dim; echo 30 > $P; echo 0 > $K
	else
		st=off; echo 0 > $P; echo 0 > $K
	fi
done
