#!/bin/sh
# /bin/e72-lights: display and keyboard light follow the keys.
# full on a key press, dimmed after $1 s (15), off after another $2 s (45)
P=/sys/class/backlight/panel/brightness
K=/sys/class/backlight/gazoo-pwm0/brightness
ON=${3:-120}
st=on; echo $ON > $P; echo 15 > $K
while :; do
	case $st in
	on)  t=${1:-15} ;;
	dim) t=${2:-45} ;;
	off) t=86400 ;;
	esac
	if busybox timeout $t dd if=/dev/input/event1 of=/dev/null bs=16 count=1 2>/dev/null; then
		[ $st = on ] || { echo $ON > $P; echo 15 > $K; }
		st=on
	elif [ $st = on ]; then
		st=dim; echo 30 > $P; echo 0 > $K
	else
		st=off; echo 0 > $P; echo 0 > $K
	fi
done
