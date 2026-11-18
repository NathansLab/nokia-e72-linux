#!/bin/busybox sh
# E72 persistent state on the card's first partition (fat, symbian's E:):
#   E:\linux\wpa\wpa_supplicant.conf  saved wlan (written by `wifi <name> <password>`)
#   E:\linux\dropbear\                 ssh host keys, made on first boot
#   E:\linux\authorized_keys           public keys allowed to log in as root
#   E:\linux\boot.sh                   optional, run at the end
# then: wlan up, ssh server (keys only), wfi idle instead of the nohlt poll,
# keymap, light timeout, low battery guard
BB=/bin/busybox
(
	export PATH=/bin:/sbin:/usr/bin:/usr/sbin
	k() { echo "e72: $*" > /dev/kmsg; }
	n=0
	while [ ! -b /dev/mmcblk0p1 ] && [ $n -lt 20 ]; do $BB sleep 1; n=$((n + 1)); done
	$BB mkdir -p /card /etc/dropbear /root/.ssh
	if $BB mount -t vfat -o rw,noatime,flush /dev/mmcblk0p1 /card 2>/dev/null; then
		$BB mkdir -p /card/linux/wpa /card/linux/dropbear
		$BB rm -rf /etc/wpa_supplicant /etc/dropbear
		$BB ln -s /card/linux/wpa /etc/wpa_supplicant
		$BB ln -s /card/linux/dropbear /etc/dropbear
		[ -f /card/linux/authorized_keys ] && { $BB cp /card/linux/authorized_keys /root/.ssh/; $BB chmod 700 /root /root/.ssh; $BB chmod 600 /root/.ssh/authorized_keys; }
		k "card mounted on /card"
	else
		k "no card: nothing is saved across boots"
	fi
	$BB sleep 6
	[ -w /sys/module/idle/parameters/wfi ] && echo 1 > /sys/module/idle/parameters/wfi && k "wfi idle on"
	if [ -f /etc/wpa_supplicant/wpa_supplicant.conf ] && [ -e /sys/class/net/wlan0 ]; then
		/usr/bin/wifi on 2>&1 | while IFS= read -r l; do k "wifi: $l"; done
	fi
	if [ -x /usr/sbin/dropbear ] && [ -s /root/.ssh/authorized_keys ]; then
		/usr/sbin/dropbear -R -s -p 22 2>&1 | while IFS= read -r l; do k "ssh: $l"; done
		k "ssh server on port 22 (keys only)"
	fi
	# energy: wlan power save (about 60 mA less); the lights follow the keys
	command -v iw >/dev/null && iw dev wlan0 set power_save on 2>/dev/null
	[ -r /etc/e72.kmap ] && $BB loadkmap < /etc/e72.kmap && k "keymap /etc/e72.kmap loaded"
	# a blinking cursor redraws (and wakes the cpu) twice a second
	[ -w /sys/class/graphics/fbcon/cursor_blink ] && echo 0 > /sys/class/graphics/fbcon/cursor_blink
	[ -e /dev/input/event0 ] && /bin/e72-lights </dev/null >/dev/null 2>&1 &
	# the bq24151 only charges from an enumerated usb host. on a wall charger
	# (usb power present, no charging) go back to symbian below 3500 mV, it
	# can charge there. on battery alone the kernel powers off at 3300 mV
	(
		n=0
		P=/sys/class/power_supply
		while [ -r $P/battery/voltage_now ]; do
			mv=$(($($BB cat $P/battery/voltage_now) / 1000))
			if [ "$mv" -lt 3500 ] && [ "$($BB cat $P/usb/online 2>/dev/null)" = 1 ] &&
			   [ "$($BB cat $P/battery/status)" != Charging ]; then n=$((n + 1)); else n=0; fi
			[ "$n" -ge 3 ] && { k "battery $mv mV on a charger linux cannot use, rebooting to symbian"; $BB sync; $BB reboot; }
			$BB sleep 60
		done
	) &
	[ -f /card/linux/boot.sh ] && $BB sh /card/linux/boot.sh 2>&1 | while IFS= read -r l; do k "boot.sh: $l"; done
) &
