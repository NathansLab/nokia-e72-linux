#!/bin/sh
# e72-power-steps.sh - DRAFT, never run on the phone. Step-by-step idle current hunt for
# Linux on the Nokia E72 (RM-530, fw 091.004). Every step can be switched off (= saving
# applied) and on (= back to the state found) on its own. Most harmless first.
#
#   e72-power-steps.sh list            steps with risk class
#   e72-power-steps.sh snap [file]     read-only register snapshot (cgc, pll, gpio, idle, irqs)
#   e72-power-steps.sh measure [n]     average battery current over n readings (default 10, 3 s apart)
#   e72-power-steps.sh <step> off      apply the saving, then measure
#   e72-power-steps.sh <step> on       restore, then measure
#   e72-power-steps.sh walk            all SAFE + LOW steps in order, measure after each, then
#                                      restore everything in reverse order (asks before each step)
#
# Run it over ssh (wlan), USB cable unplugged (the reading would include charging), phone lying
# still, screen untouched. Write down "measure" before the first step. Notes: NOTES.md here.
#
# Never touched here: internal flash, secure watchdog, PMIC watchdog/cbus, charger, modem memory.
# Register facts: cgc = 0x20032f00, every gate reg R has R+4 = set bits, R+8 = clear bits
# (clk-rapuyama.c, power_resources.dll fw 091.004). Gate polarity: 0x20033150 bits are ON when CLEAR.

BB=busybox
LOG=${LOG:-/card/linux/power-steps.log}
CUR=/sys/class/power_supply/battery/current_now
STATE=/tmp/e72-power-steps.state
touch $STATE

log() { echo "$(date +%H:%M:%S) $*" | tee -a $LOG; }
rd() { $BB devmem $1 32; }
wr() { log "  devmem $1 32 $2   (was $(rd $1) at ${3:-$1})"; $BB devmem $1 32 $2; }
bit_set() { [ $(( $(rd $1) & $2 )) -ne 0 ]; }
save() { grep -v "^$1=" $STATE > $STATE.n; echo "$1=$2" >> $STATE.n; mv $STATE.n $STATE; }
saved() { sed -n "s/^$1=//p" $STATE; }
param() { for p in /sys/module/*/parameters/$1; do [ -e "$p" ] && { echo $p; return 0; }; done; return 1; }

measure() {
	n=${1:-10}; i=0; s=0
	while [ $i -lt $n ]; do
		v=$(cat $CUR); s=$((s + v)); i=$((i + 1)); sleep 3
	done
	log "measure: $((s / n / 1000)) mA average of $n (last $((v / 1000)) mA)"
}

# cbus sanity after any clock step: the PMIC watchdog kick and the ADC share the cbus.
# A failed kick is logged by rapuyama_wdt as "pmic kick failed". Reading the battery
# voltage goes through the same cbus, so a fresh value means the cbus still works.
cbus_ok() {
	a=$(cat /sys/class/power_supply/battery/voltage_now 2>/dev/null); sleep 4
	b=$(cat /sys/class/power_supply/battery/voltage_now 2>/dev/null)
	if dmesg | tail -n 20 | grep -q "pmic kick failed"; then log "  !! pmic kick failed"; return 1; fi
	[ -n "$b" ] || { log "  !! battery voltage not readable"; return 1; }
	return 0
}

snap() {
	out=${1:-/dev/stdout}
	{
	echo "# snap $(date) uptime $(cut -d' ' -f1 /proc/uptime)"
	echo "# cgc 0x20033000..0x200331fc (gate regs at +0x80..+0x1f0, step 0x10)"
	a=$((0x20033000)); while [ $a -lt $((0x20033200)) ]; do printf '%08x %s\n' $a $(rd $a); a=$((a + 16)); done
	echo "# pll block 0x20032600..0x2003267c (0x604 = ARM pll M<<5|N per power_resources; 0x60c ctrl)"
	a=$((0x20032600)); while [ $a -lt $((0x20032680)) ]; do printf '%08x %s\n' $a $(rd $a); a=$((a + 4)); done
	echo "# 0x20020804 (EdCommon ext gate, spi/wlan) and 0x200331f0 (pll lock bit 3)"
	printf '20020804 %s\n200331f0 %s\n' $(rd 0x20020804) $(rd 0x200331f0)
	echo "# gpio out latches 0x20031990.. (bank k at +0x10k), bank 6 0x20031ab0; inputs 0x200319f0.."
	for a in 0x20031990 0x200319a0 0x200319b0 0x200319c0 0x200319d0 0x200319e0 0x20031ab0 \
	         0x200319f0 0x20031a00 0x20031a10 0x20031a20 0x20031a30; do printf '%s %s\n' $a $(rd $a); done
	echo "# musb otg wrapper sysconfig/forcestdby, power/devctl"
	printf '20038c04 %s\n20038c14 %s\n20038800 %s\n20038860 %s\n' $(rd 0x20038c04) $(rd 0x20038c14) $(rd 0x20038800) $(rd 0x20038860)
	cat /sys/kernel/debug/rapuyama-idle 2>/dev/null
	cat /proc/interrupts
	for p in deep wfi sec_poll_ms poll_ms irq; do q=$(param $p) && echo "$q = $(cat $q)"; done
	cat /sys/class/power_supply/usb/online 2>/dev/null | sed 's/^/usb online /'
	} > $out
}

# ---------------------------------------------------------------- SAFE (software only)

# 1 fbcon cursor blink: every blink is a panel push (rows changed), 5 wakeups/s + rfbi/dispc work
s_blink() {
	f=/sys/class/graphics/fbcon/cursor_blink
	case $1 in off) save blink $(cat $f); echo 0 > $f ;; on) echo $(saved blink) > $f ;; esac
}

# 2 secondary interrupt bank poll (100 wakeups/s), patch 0011
s_secpoll() {
	f=$(param sec_poll_ms) || { log "  no sec_poll_ms parameter in this kernel"; return 1; }
	case $1 in off) save secpoll $(cat $f); echo 0 > $f ;; on) echo $(saved secpoll) > $f ;; esac
}

# 3 lights: stop e72-lights, panel brightness 0, gazoo pwm0 (keyboard) and pwm1 0
s_lights() {
	P=/sys/class/backlight/panel/brightness
	case $1 in
	off) save panelbl $(cat $P); pkill -f e72-lights; echo 0 > $P
	     for k in /sys/class/backlight/gazoo-pwm*/brightness; do save $(basename $(dirname $k)) $(cat $k); echo 0 > $k; done ;;
	on)  echo $(saved panelbl) > $P
	     for k in /sys/class/backlight/gazoo-pwm*/brightness; do echo $(saved $(basename $(dirname $k))) > $k; done
	     /bin/e72-lights </dev/null >/dev/null 2>&1 & ;;
	esac
}

# 4 panel sleep: DCS display off + sleep in (e5-display pipe disable). Brightness 0 alone
#   leaves the panel controller running. A key does NOT wake it here: "on" does.
s_panel() {
	f=/sys/class/graphics/fb0/blank
	case $1 in off) echo 1 > $f ;; on) echo 0 > $f ;; esac
}

# ---------------------------------------------------------------- LOW (clock gates)
# Both resources below are level 0 in Symbian's resource manager at the dump (idle) and were
# switched on by Symbian before (ever-on 1), so Symbian gates them off itself. Linux turns them
# on at boot because clk-rapuyama.c marks them CLK_IS_CRITICAL (E6 reasons: bt uart, i2c-omap),
# and no E72 driver uses them.

# 5 res 0x1f EHwClkASIBT = gate 0x22, cgc+0x1d0 bit 12 (0x200330d0)
s_asibt() {
	case $1 in
	off) bit_set 0x200330d0 0x1000 || { log "  gate 0x22 already off"; return 0; }
	     wr 0x200330d8 0x1000 0x200330d0; cbus_ok || { wr 0x200330d4 0x1000 0x200330d0; log "  restored"; return 1; } ;;
	on)  wr 0x200330d4 0x1000 0x200330d0 ;;
	esac
}

# 6 res 0x11 EHwClkI2C0 (i2c_0 client) = gate 0x07 cgc+0x1d0 bit 6 + gate 0x12 cgc+0x1b0 bit 4.
#   RAPU I2C0 = magnetometer AK8974 bus (schematic p18); Linux has no driver on it.
s_i2c0() {
	case $1 in
	off) ls /sys/bus/platform/devices | grep -qi "i2c" && log "  note: platform i2c devices: $(ls /sys/bus/platform/devices | grep -i i2c | tr '\n' ' ')"
	     wr 0x200330d8 0x40 0x200330d0; wr 0x200330b8 0x10 0x200330b0
	     cbus_ok || { s_i2c0 on; log "  restored"; return 1; } ;;
	on)  wr 0x200330b4 0x10 0x200330b0; wr 0x200330d4 0x40 0x200330d0 ;;
	esac
}

# 7 idle deep bit (0x200331a0 bit 1 around WFI, Symbian modes 3/4), patch 0011, untested.
#   Only pays with the one-shot tick (e6.oneshot=1); with the 1 kHz tick it is never used.
s_deep() {
	f=$(param deep) || { log "  no idle deep parameter"; return 1; }
	case $1 in off) save deep $(cat $f); echo 1 > $f ;; on) echo $(saved deep) > $f ;; esac
}

# ---------------------------------------------------------------- MEDIUM (usb, no cable only)

usb_cable() { [ "$(cat /sys/class/power_supply/usb/online 2>/dev/null)" = 1 ]; }

# 8 musb otg wrapper forced standby (0x20038c14 bit 0), omap2430 style. The usb shell and
#   charging stop while it is set. Only without a cable.
s_usbstdby() {
	case $1 in
	off) usb_cable && { log "  usb cable present, skipped"; return 1; }
	     wr 0x20038c14 1 ;;
	on)  wr 0x20038c14 0 ;;
	esac
}

# ---------------------------------------------------------------- EXPERIMENTAL (needs "force")

# 9 usb clocks: unbind the musb glue, then the gates Symbian's usb.dll ("USB PSL") holds:
#   res 0x10 EHwClkHSUSB      gate 0x06 cgc+0x1d0 bit 4, 0x2c cgc+0x290 bit 9, 0x11 cgc+0x180 bit 11
#   res 0x21 ExtSysClk19M2    gate 0x27 cgc+0x180 bit 4  (19.2 MHz, ISP1707 ulpi phy reference)
#   res 0x0f EHwClkDomHSUSB   gate 0x1e cgc+0x250 bit 3, 0x15 cgc+0x250 bit 13 (power domain, 1 = off)
#   Lost until "on" (rebind): usb gadget, usb shell, charging. A wrong guess = external abort
#   on the next musb access -> oops -> panic=10 -> reboot into Symbian.
s_usbclk() {
	G=/sys/bus/platform/drivers/musb-rapuyama
	case $1 in
	off) [ "$FORCE" = 1 ] || { log "  experimental: FORCE=1 $0 usbclk off"; return 1; }
	     usb_cable && { log "  usb cable present, skipped"; return 1; }
	     d=$(ls $G 2>/dev/null | grep 20038800) || { log "  musb glue not bound"; return 1; }
	     save usbdev $d; echo $d > $G/unbind; sleep 1
	     wr 0x200330d8 0x10 0x200330d0; wr 0x20033198 0x200 0x20033190; wr 0x20033088 0x800 0x20033080
	     wr 0x20033088 0x10 0x20033080
	     wr 0x20033154 0x8 0x20033150; wr 0x20033154 0x2000 0x20033150 ;;
	on)  wr 0x20033158 0x2000 0x20033150; sleep 1; wr 0x20033158 0x8 0x20033150
	     wr 0x20033084 0x10 0x20033080
	     wr 0x20033084 0x800 0x20033080; wr 0x20033194 0x200 0x20033190; wr 0x200330d4 0x10 0x200330d0
	     sleep 1; d=$(saved usbdev); [ -n "$d" ] && echo $d > $G/bind ;;
	esac
}

# 10 gdma (res 0x22 gate 0x28 cgc+0x1b0 bit 3, plus cgc+0x180 bit 3): rapuyama-gdma.c switches
#    them per channel use, so they should already be off when the card is idle. Read-only check.
s_gdma() {
	log "  gdma gates: 0x200330b0 bit3 $(( ($(rd 0x200330b0) >> 3) & 1 )), 0x20033080 bit3 $(( ($(rd 0x20033080) >> 3) & 1 )) (1 = on; on while idle = a channel kept its clock)"
}

STEPS="blink:SAFE secpoll:SAFE lights:SAFE panel:SAFE asibt:LOW i2c0:LOW deep:LOW usbstdby:MEDIUM usbclk:EXPERIMENTAL gdma:READ"

run_step() {
	log "step $1 $2"
	s_$1 $2 && measure ${N:-10}
}

case $1 in
list) for s in $STEPS; do echo "$s"; done ;;
snap) snap $2 ;;
measure) measure $2 ;;
walk)
	log "walk start"; snap $LOG.snap0; measure ${N:-10}
	done_list=
	for s in $STEPS; do
		name=${s%%:*}; cls=${s##*:}
		case $cls in SAFE|LOW) ;; *) continue ;; esac
		printf 'step %s (%s) off? [y/N] ' $name $cls; read a
		[ "$a" = y ] || continue
		run_step $name off && done_list="$name $done_list"
	done
	snap $LOG.snap1
	printf 'restore all (%s)? [Y/n] ' "$done_list"; read a
	[ "$a" = n ] || for s in $done_list; do run_step $s on; done ;;
*)
	[ -n "$2" ] || { sed -n '2,16p' $0; exit 1; }
	run_step $1 $2 ;;
esac
