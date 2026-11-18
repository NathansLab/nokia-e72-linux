#!/usr/bin/env bash
# Nokia E72 (RM-530) cellular development kernel: build-e72.sh's config + what
# build-e5.sh adds for the E5 3G build (VMSPLIT_3G25 so the userspace ISASW runtime
# can map the firmware VAs c60f0000..cb6fc000, Phonet + rapuyama_isi + the MDI ring
# driver + the SIM bridge module). Own output dir build-e72-cell, so build-e72 stays
# untouched. Two dtbs: e72.dtb (e72-cell.dts) and e72-3g.dtb (+ e5.mobile=1).
# Needs kernel/e72-cell-mdi.patch in the source tree (the mdi driver has no E72
# layout otherwise and refuses to probe); this script does not apply it.
# Image limit of the E72 loader: 16 MB (checked below).
# runs in the e72-kbuild container like build-e72.sh. usage: ./build-e72-cell.sh [config|build]
# NOT run yet (2026-11-18): prepared from the E72 RAM dump, see e5-cell/sim/e72_fw091004.h
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
KSRC="$HERE/linux"
export KOUT="${KOUT:-$HERE/build-e72-cell}"
export ARCH=arm CROSS_COMPILE="${CROSS_COMPILE:-arm-linux-gnueabi-}"
MAKE=(make -C "$KSRC" O="$KOUT")
S() { "$KSRC/scripts/config" --file "$KOUT/.config" "$@"; }

grep -q '"nokia,e72", RY_TOP(0x1fd50000)' "$KSRC/drivers/soc/rapuyama/mdi.c" || {
	echo "mdi.c has no E72 layout: apply kernel/e72-cell-mdi.patch first (patch -p1 -d linux)" >&2
	exit 1
}

config() {
	"$HERE/build-e72.sh" config
	S -d VMSPLIT_3G -e VMSPLIT_3G25
	for o in PHONET RAPUYAMA_ISI SOC_RAPUYAMA_MDI; do S -e "$o"; done
	S -m RAPUYAMA_SIM_BRIDGE
	"${MAKE[@]}" olddefconfig
	grep -qx 'CONFIG_VMSPLIT_3G25=y' "$KOUT/.config" || { echo "VMSPLIT_3G25 not set"; exit 1; }
	grep -qx 'CONFIG_SOC_RAPUYAMA_MDI=y' "$KOUT/.config" || { echo "MDI driver not set"; exit 1; }
	grep -q '^CONFIG_RAPUYAMA_RAM_TOP=0x18000000$' "$KOUT/.config" || { echo "RAM_TOP not set"; exit 1; }
}
case "${1:-build}" in
	config) config ;;
	build)  [ -f "$KOUT/.config" ] || config
		"${MAKE[@]}" -j"$(nproc)" Image modules
		sz=$(stat -c %s "$KOUT/arch/arm/boot/Image")
		[ "$sz" -le 16777216 ] || { echo "Image $sz bytes > 16 MB loader limit"; exit 1; }
		dtc -I dts -O dtb -o "$KOUT/e72.dtb" "$HERE/../boot/e72-cell.dts"
		cp "$KOUT/e72.dtb" "$KOUT/e72-3g.dtb"
		fdtput -t s "$KOUT/e72-3g.dtb" /chosen bootargs \
			"$(fdtget -t s "$KOUT/e72.dtb" /chosen bootargs) e5.mobile=1"
		ls -la "$KOUT/arch/arm/boot/Image" "$KOUT/e72.dtb" "$KOUT/e72-3g.dtb" \
			"$KOUT/drivers/misc/rapuyama_sim.ko" ;;
	*) echo "usage: $0 [config|build]"; exit 1 ;;
esac
