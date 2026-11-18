#!/bin/sh
# kpress <keycode>...: inject key presses into the keypad's event device
ev() { # type code value
	printf "\\0\\0\\0\\0\\0\\0\\0\\0\\$(printf %o $1)\\0\\$(printf %o $2)\\0\\$(printf %o $3)\\0\\0\\0"
}
E=/dev/input/event1
for n in /sys/class/input/event*/device/name; do
	case "$(cat $n 2>/dev/null)" in *keyboard*) E=/dev/input/$(basename ${n%/device/name}) ;; esac
done
for k in "$@"; do
	{ ev 1 $k 1; ev 0 0 0; } > $E
	{ ev 1 $k 0; ev 0 0 0; } > $E
done
