#!/bin/busybox sh
# Nokia E72 bring-up /init: wraps the stock init.sh (usb shell on ttyGS0).
# the E72 has no working display/keypad driver yet, so everything we learn
# has to land in the ram log: 20 s after boot a hardware inventory goes to
# kmsg; if no pc has configured the usb gadget after 150 s the phone reboots
# so e72logs can read the log back under symbian.
BB=/bin/busybox
(
	$BB sleep 20
	k() { while IFS= read -r l; do echo "e72: $l" > /dev/kmsg; done; }
	echo "== interrupts" | k; $BB cat /proc/interrupts | k
	echo "== meminfo" | k; $BB head -n 6 /proc/meminfo | k
	echo "== iomem" | k; $BB cat /proc/iomem | k
	echo "== platform devices" | k; $BB ls /sys/bus/platform/devices | k
	echo "== drivers bound" | k
	for d in /sys/bus/platform/devices/*; do
		[ -e "$d/driver" ] && echo "$($BB basename "$d") -> $($BB basename "$($BB readlink "$d/driver")")"
	done | k
	echo "== udc" | k
	for u in /sys/class/udc/*; do [ -e "$u" ] && echo "$($BB basename "$u") $($BB cat "$u/state")"; done | k
	echo "== input" | k; $BB cat /proc/bus/input/devices 2>/dev/null | $BB grep -E "Name|Handlers" | k
	n=0
	while [ $n -lt 130 ]; do
		$BB grep -q configured /sys/class/udc/*/state 2>/dev/null && { echo "usb configured, staying up" | k; exit 0; }
		$BB sleep 1; n=$((n + 1))
	done
	echo "no usb host after 150 s, rebooting for the ram log" | k
	$BB sync; $BB sleep 1
	$BB reboot -f
) &
exec $BB sh /init.e5
