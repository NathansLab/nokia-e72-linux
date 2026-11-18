# Status (2026-11-18)

Three levels: **verified on device** (seen working on the E72), **built, untested** (in the kernel/initramfs/device tree, never run on the phone), **not done**.

## Verified on device

- Boot from Symbian with LinuxE72 (scatter boot), Linux 6.12.0 up to the BusyBox shell. Logs: `logs/2026-11-18-first-boot-*`, `logs/2026-11-18-usb-shell-dmesg.txt`.
- RAM log read back with e72logs after a reset.
- Display: DRM/fbdev driver from the E5 port, 320x240 XRGB8888, fbcon 40x30, frame pushed by DMA with completion IRQ (about 27 ms per full frame). Photo: `images/e72-first-linux-image.jpg`, log: `logs/2026-11-18-display-session.txt`.
- USB serial shell (CDC ACM).
- Secure-watchdog bridge, fw 091.004: more than 15 min uptime. `logs/2026-11-18-watchdog-bridge-session.txt`.
- Keyboard matrix: 8 of 55 keys pressed and seen at the expected row/column with the test module.
- Power key input device (from the E5 watchdog driver) registers; not tested by pressing.

## Built, untested

- Built-in keypad driver with E72 pins and keymap from the device tree (patch 0003, `e72.dts`).
- WLAN: WL1251 on SPI 2, firmware + NVS built in, `wpa_supplicant`/`iw`/`wifi`.
- microSD slot (MMC at `0x20032800`) and general DMA (GDMA).
- WFI idle switch at run time (patch 0004).
- kexec (kernel option and `kexec` binary).
- Alpine userland: `dbclient`/`ssh`, `scp`, `apk`.
- TUN and WireGuard, 100 Hz tick.

## Not working / not done

- **USB ethernet:** `usb0` sends, but receives only the first packet. Files go over the serial line for now (`tools/put.py`).
- **Battery:** no level, no charging under Linux. The E5 battery node is removed from the E72 device tree.
- **Lights:** keyboard light and backlight control not checked; the E5 light nodes are removed.
- **Modem, calls, SMS, mobile data, audio:** not started.
- **Keyboard layout:** Fn/Sym layers and the special keys still need a real layout.
- **Power saving:** `nohlt` at boot, keyboard polled; WFI and interrupt-driven input are the next steps.
- **Reboot without USB host:** `e72-init.sh` reboots after 150 s if no PC configured the gadget (a bring-up aid; remove it for cable-free use).
- **Other firmware versions / E72 variants:** only RM-530 with 091.004 has a watchdog entry.

## Next steps

1. Boot the kernel with WLAN, card slot and keypad nodes; test `wifi` and `ssh`.
2. Fix USB ethernet receive.
3. Battery level and power-off on low battery.
4. Power: WFI by default, interrupt-driven keyboard, display blanking.
5. kexec from the USB shell, so new kernels can be tried without Symbian.
