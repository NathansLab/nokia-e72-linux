#!/bin/sh
# kpress <keycode>...: inject key presses into the keypad's event device
ev() { # type code value
	printf "\\0\\0\\0\\0\\0\\0\\0\\0\\$(printf %o $1)\\0\\$(printf %o $2)\\0\\$(printf %o $3)\\0\\0\\0"
}
for k in "$@"; do
	{ ev 1 $k 1; ev 0 0 0; } > /dev/input/event1
	{ ev 1 $k 0; ev 0 0 0; } > /dev/input/event1
done
