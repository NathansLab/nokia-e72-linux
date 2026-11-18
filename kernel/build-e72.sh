#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# Nokia E72 (RM-530, 128 MB) kernel + dtb, first bring-up.
# = the E5 wifi-only kernel config (build-e5.sh config(), E5_NOCELL path)
#   + CONFIG_RAPUYAMA_RAM_TOP=0x18000000 (ramcon/isah/shm move to the E72's top of RAM)
#   + a busybox initramfs: e72-init.sh (inventory to the ram log, reboot
#     without a usb host) wrapping the stock init.sh (usb shell on ttyGS0)
# runs in the e72-kbuild container (debian arm64, gcc-arm-linux-gnueabi).
# usage: ./build-e72.sh [config|build]
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
KSRC="$HERE/linux"
KOUT="${KOUT:-$HERE/build-e72}"
export ARCH=arm CROSS_COMPILE="${CROSS_COMPILE:-arm-linux-gnueabi-}"
mkdir -p "$KOUT"
MAKE=(make -C "$KSRC" O="$KOUT")
S() { "$KSRC/scripts/config" --file "$KOUT/.config" "$@"; }

config() {
	cp "$HERE/e6.config" "$KOUT/.config"
	S -d SOUND -d RAPUYAMA_MODEM -d FB_RAPUYAMA -d FB_SIMPLE
	for o in FB FB_DEVICE FRAMEBUFFER_CONSOLE FONTS FONT_8x8; do S -e "$o"; done
	for o in DRM DRM_KMS_HELPER DRM_FBDEV_EMULATION RAPUYAMA_E5_DISPLAY; do S -e "$o"; done
	S -d DRM_SIMPLEDRM -d FB_RAPUYAMA_E5
	for o in INPUT_KEYBOARD KEYBOARD_RAPUYAMA_E5; do S -e "$o"; done
	S -d USB_G_SERIAL -d USB_ETH -e USB_CDC_COMPOSITE
	for o in BRCMUTIL BRCMFMAC ZD1211RW; do S -d "$o"; done
	for o in WLAN WLAN_VENDOR_TI WL1251 WL1251_SPI SPI_RAPUYAMA_E5; do S -e "$o"; done
	for o in BACKLIGHT_CLASS_DEVICE BACKLIGHT_RAPUYAMA_E5; do S -e "$o"; done
	for o in DMADEVICES RAPUYAMA_GDMA; do S -e "$o"; done
	# slim (build-e5.sh slim(), same lists)
	for o in ARCH_MULTI_V7 ARCH_BCM ARCH_BCM2835 RASPBERRYPI_FIRMWARE BCM2835_MBOX MAILBOX \
		BCM_VIDEOCORE BCM2835_VCHIQ VCHIQ_CDEV CMA DMA_CMA; do S -d "$o"; done
	for o in INPUT_TOUCHSCREEN KEYBOARD_RAPUYAMA KEYBOARD_GPIO_POLLED LEDS_E6_KEYBOARD NEW_LEDS \
		I2C_BCM2835 I2C_BRCMSTB SPI_BCM2835 SPI_BCM2835AUX MMC_BCM2835 MMC_SDHCI MMC_SDHCI_IPROC \
		PWM_BCM2835 PINCTRL_BCM2835 GPIO_RASPBERRYPI_EXP BCM2711_THERMAL BCM2835_THERMAL THERMAL HWMON \
		SERIAL_8250 SERIAL_AMBA_PL011 PWRSEQ_EMMC; do S -d "$o"; done
	for o in USB HID SCSI ETHERNET PHYLIB SERIO INPUT_MOUSE KEYBOARD_ATKBD BT MEDIA_SUPPORT; do S -d "$o"; done
	for o in NFS_FS NFSD IP_PNP EXT2_FS RD_BZIP2 RD_LZMA RD_XZ RD_LZO RD_LZ4 RD_ZSTD; do S -d "$o"; done
	for o in KGDB KPROBES PROFILING PERF_EVENTS CPU_FREQ; do S -d "$o"; done
	S --set-val LOG_BUF_SHIFT 17
	for o in DYNAMIC_DEBUG SLUB_DEBUG SCHED_DEBUG IO_URING; do S -d "$o"; done
	# E72: kexec so a new kernel can be started over usb without symbian, /dev/mem
	# unrestricted for register and ram inspection from the shell
	# wl1251 firmware + this phone's nvs, cut from the E72 ram dump (not in the repo)
	E72_WLAN_FW="${E72_WLAN_FW:-/fw}"
	if [ -f "$E72_WLAN_FW/ti-connectivity/wl1251-nvs.bin" ]; then
		S --set-str EXTRA_FIRMWARE "ti-connectivity/wl1251-fw.bin ti-connectivity/wl1251-nvs.bin"
		S --set-str EXTRA_FIRMWARE_DIR "$E72_WLAN_FW"
	fi
	S -e RAPUYAMA_GDMA
	# E72 loader limit: Image <= 16 MB. xz initramfs, no btrfs, no full kallsyms
	S -e RD_XZ; S -d INITRAMFS_COMPRESSION_GZIP; S -e INITRAMFS_COMPRESSION_XZ
	S -d BTRFS_FS; S -d KALLSYMS_ALL
	# E72: tun + wireguard for a tailnet, 100 Hz tick (fewer wakeups than 1000)
	S -e TUN; S -e WIREGUARD; S -d HZ_1000; S -e HZ_100
	S -e KEXEC; S -d STRICT_DEVMEM; S -e IKCONFIG; S -e IKCONFIG_PROC
	# E72: 128 MB, top of ram at 0x18000000
	S --set-val RAPUYAMA_RAM_TOP 0x18000000
	I="$(cd "$HERE/../initramfs" && pwd)"; BB="$(realpath "$HERE/../../work/dl/busybox-armv5l")"
	cat > "$KOUT/initramfs.list" <<LIST
dir /dev 755 0 0
nod /dev/console 600 0 0 c 5 1
dir /bin 755 0 0
dir /sbin 755 0 0
dir /proc 755 0 0
dir /sys 755 0 0
dir /tmp 1777 0 0
dir /etc 755 0 0
dir /root 700 0 0
file /bin/busybox $BB 755 0 0
slink /bin/sh busybox 777 0 0
file /init $I/e72-init.sh 755 0 0
file /init.e5 $I/init.sh 755 0 0
file /sbin/init $I/init 755 0 0
file /bin/e6sh $I/e6sh.sh 755 0 0
LIST
	# alpine armhf userland (initramfs/e72-rootfs.sh): wlan tools, dbclient, kexec, apk
	W="$(realpath "$HERE/../../work/rootfs-e72")"
	(cd "$W" && find lib usr sbin etc/apk etc/ssl -path usr/share/udhcpc -prune -o -print | sort) |
	while read -r f; do
		if [ "$f" = sbin ] || [ "$f" = etc ]; then continue
		elif [ -L "$W/$f" ]; then echo "slink /$f $(readlink "$W/$f") 777 0 0"
		elif [ -d "$W/$f" ]; then echo "dir /$f $(stat -c %a "$W/$f") 0 0"
		else echo "file /$f $W/$f $(stat -c %a "$W/$f") 0 0"; fi
	done >> "$KOUT/initramfs.list"
	cat >> "$KOUT/initramfs.list" <<LIST
dir /usr/share/udhcpc 755 0 0
file /usr/bin/wifi $I/e5-wifi.sh 755 0 0
file /usr/share/udhcpc/default.script $I/e5-dhcp.sh 755 0 0
slink /usr/bin/ssh dbclient 777 0 0
LIST
	S --set-str INITRAMFS_SOURCE "$KOUT/initramfs.list"
	"${MAKE[@]}" olddefconfig
	grep -q '^CONFIG_RAPUYAMA_RAM_TOP=0x18000000$' "$KOUT/.config" || { echo "RAM_TOP not set"; exit 1; }
}
case "${1:-build}" in
	config) config ;;
	build)  [ -f "$KOUT/.config" ] || config
		"${MAKE[@]}" -j"$(nproc)" Image
		dtc -I dts -O dtb -o "$KOUT/e72.dtb" "$HERE/../boot/e72.dts"
		ls -la "$KOUT/arch/arm/boot/Image" "$KOUT/e72.dtb" ;;
	*) echo "usage: $0 [config|build]"; exit 1 ;;
esac
