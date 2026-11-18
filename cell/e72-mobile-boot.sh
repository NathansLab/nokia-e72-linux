#!/bin/sh
# E72 3G boot step: the E72 version of initramfs/e5-mobile-boot.sh, kept on the card so that nothing is added
# to the initramfs (16 MB Image limit). NOT phone-tested. Start it from /card/linux/boot.sh:
#   grep -q 'e5\.mobile=1' /proc/cmdline && sh /card/linux/cell/e72-mobile-boot.sh &
# (e72-3g.dtb from kernel/build-e72-cell.sh sets e5.mobile=1; a by-hand start with CMDLINE=/dev/null FORCE=1
#  works too, within MAXUP seconds of boot). Card layout, E:\linux\cell\ = /card/linux/cell/:
#   e72rt            e5rt built with -DE72_FW091004 (checks fw 091.004 byte for byte before it patches anything)
#   pnping e5gprs    from e5-cell/build.sh
#   e72mem.ko        e5-cell/e72mem, built against build-e72-cell
#   rapuyama_sim.ko  build-e72-cell/drivers/misc/rapuyama_sim.ko (same kernel build as the Image)
#   imei             15 digits, written by hand; read only by e72rt (E5RT_IMEI_FILE), never printed here
# Steps: same-boot ISASW images (e72mem debugfs) -> /run/e72img (8 MB tmpfs, removed once e72rt has
# loaded them), sim bridge, phonet0 up at >= 60 s uptime, e72rt live, registration (pnping 20 x 5 s).
# /run/e72-mobile/state = starting, registered, not-registered, no-imei, bad-imei, too-late, unavailable,
# stopped. Optional: MEAS=<file|fifo under /run> turns the measurement tap on (E5RT_MEAS_TAP, meas_tap.h),
# MEAS_FILTER=dev:res,.. (default 7c:38). Debug traces stay off (they stall the DSP link on the E5).
CELL=${CELL:-/card/linux/cell}
RUN=${RUN:-/run/e72-mobile}
CMDLINE=${CMDLINE:-/proc/cmdline}
UPTIME=${UPTIME:-/proc/uptime}
SLEEP=${SLEEP:-sleep}
DBG=${DBG:-/sys/kernel/debug}
IMG=${IMG:-/run/e72img}
KMSG=${KMSG:-/dev/kmsg}
MAXUP=${MAXUP:-90}
LOG_MAX=262144 LOG_KEEP=65536

[ -n "$FORCE" ] || grep -q 'e5\.mobile=1' "$CMDLINE" || exit 0
mkdir -p "$RUN"
log() {
	printf 'mobile: %s\n' "$*" >> "$RUN/boot.log"
	{ printf 'e72: mobile: %s\n' "$*" > "$KMSG"; } 2>/dev/null
}
state() { echo "$1" > "$RUN/state"; log "$1${2:+ ($2)}"; }
up() { cut -d. -f1 "$UPTIME"; }

[ -e "$RUN/started" ] && { log "the modem runtime already ran in this boot"; exit 0; }
[ -s "$CELL/imei" ] || { state no-imei "no $CELL/imei (15 digits)"; exit 0; }
case "$(tr -d '\r\n' < "$CELL/imei")" in
[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]) ;;
*) state bad-imei "$CELL/imei is not 15 digits"; exit 0 ;;
esac
# tmpfs copy without CR (FAT editors), private to root; e72rt checks the Luhn digit itself
umask 077
tr -d '\r\n' < "$CELL/imei" > "$RUN/imei"
umask 022
[ "$(up)" -gt "$MAXUP" ] && { state too-late "uptime $(up) s, the modem must start within $MAXUP s of boot: reboot"; exit 0; }
for f in e72rt pnping e72mem.ko rapuyama_sim.ko; do
	[ -e "$CELL/$f" ] || { state unavailable "$CELL/$f missing"; exit 0; }
done
touch "$RUN/started"
state starting

mount -t debugfs debugfs "$DBG" 2>/dev/null
grep -q '^e72mem ' /proc/modules || insmod "$CELL/e72mem.ko" || { state unavailable "insmod e72mem.ko failed"; exit 0; }
mkdir -p "$IMG"
for f in 10480000 17d50000 17fe0000 17b60000 100db000; do
	cat "$DBG/e72mem/$f" > "$IMG/$f.bin" || { state unavailable "image $f unreadable"; exit 0; }
done
# e72mem stays loaded (the runtime reads the uplink puts back through it)
grep -q '^rapuyama_sim ' /proc/modules || insmod "$CELL/rapuyama_sim.ko" || { state unavailable "insmod rapuyama_sim.ko failed"; exit 0; }
while [ "$(up)" -lt 60 ]; do $SLEEP 2; done
ip link set phonet0 up

# own session (CPU autogroup) + nice -10, like the E5 (DSP answers within its 1 s budget at boot)
cp "$CELL/e72rt" "$RUN/e72rt" && chmod 700 "$RUN/e72rt"	# run from tmpfs: vfat exec bits depend on the mount options
setsid nice -n -10 env -i PATH="$PATH" E5RT_QUIET=1 E5RT_IMEI_FILE="$RUN/imei" \
	E5RT_SIM_DEVICE=/dev/rapuyama-sim E5RT_OS_CLOCK=1 \
	${MEAS:+E5RT_MEAS_TAP="$MEAS"} ${MEAS_FILTER:+E5RT_MEAS_FILTER="$MEAS_FILTER"} \
	"$RUN/e72rt" "$IMG" --mdi /dev/rapuyama-mdi --backend /dev/rapuyama-isi --seconds 0 \
	>> "$RUN/e72rt.log" 2>&1 &
rt=$!
echo $rt > "$RUN/e72rt.pid"
log "modem runtime started (pid $rt, uptime $(up) s)"

# log cap + death watch for the whole boot
(
	while kill -0 $rt 2>/dev/null; do
		if [ "$(wc -c < "$RUN/e72rt.log")" -gt $LOG_MAX ]; then
			tail -c $LOG_KEEP "$RUN/e72rt.log" > "$RUN/e72rt.log.tmp"
			cat "$RUN/e72rt.log.tmp" > "$RUN/e72rt.log"
			rm -f "$RUN/e72rt.log.tmp"
		fi
		$SLEEP 30
	done
	state stopped "the modem runtime exited (see $RUN/e72rt.log): reboot to try again"
) &

# once e72rt has its private copies (the RAM drive line comes after all image loads), give the 8 MB of
# tmpfs back (no swap on the E72)
n=0
while [ $n -lt 10 ] && ! grep -q 'SBIF RAM drives' "$RUN/e72rt.log"; do $SLEEP 1; n=$((n + 1)); done
grep -q 'SBIF RAM drives' "$RUN/e72rt.log" && rm -f "$IMG"/*.bin
$SLEEP 5
pnping=$RUN/pnping
cp "$CELL/pnping" "$pnping" && chmod 700 "$pnping"
reg=
n=0
while [ $n -lt 20 ]; do
	n=$((n + 1))
	case "$("$pnping" --send 0a e000 2>&1)" in
	*"42 e1 00 "*" 00 24 00 "*|*"42 e1 00 "*" 00 24 01 "*) reg=1; break ;;
	esac
	kill -0 $rt 2>/dev/null || exit 0
	$SLEEP 5
done
[ -n "$reg" ] || { state not-registered "no network after 20 tries (SIM, coverage?)"; exit 0; }
"$pnping" --send 0a 3600 > /dev/null 2>&1
state registered
[ -x /usr/bin/mobile ] && /usr/bin/mobile on >> "$RUN/boot.log" 2>&1
exit 0
