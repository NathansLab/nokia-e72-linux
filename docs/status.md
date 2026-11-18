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

- WLAN (WPA2, DHCP), microSD read/write, built-in keypad driver, WFI idle, kexec: see the table in the README.
- Boot without any input: `initramfs/e72-boot.sh` mounts the card, brings up WLAN from `E:\linux\wpa\`, starts the dropbear SSH server (keys only, `E:\linux\authorized_keys`), switches WFI on, dims the lights.
- Battery level and charging from a USB host: [charging.md](charging.md).
- Keyboard light and panel brightness through `/sys/class/backlight`.
- Current drawn from the battery (Gazoo meter, 2 s averages): 284 mA after boot, 147 mA with WLAN power save, panel brightness 40, keyboard light off and WFI.

## Built, untested

- Built-in keypad driver with E72 pins and keymap from the device tree (patch 0003, `e72.dts`).
- WLAN: WL1251 on SPI 2, firmware + NVS built in, `wpa_supplicant`/`iw`/`wifi`.
- microSD slot (MMC at `0x20032800`) and general DMA (GDMA).
- WFI idle switch at run time (patch 0004).
- kexec (kernel option and `kexec` binary).
- Alpine userland: `dbclient`/`ssh`, `scp`, `apk`.
- TUN and WireGuard, 100 Hz tick.
- Console keymap with one-shot Shift/Ctrl/Fn/Sym layers (`initramfs/e72.kmap`), checked by injecting key events over SSH; display dims after 15 s and switches off after 45 s without a key (`e72-lights`); `bat` shows the battery state.

## Not working / not done

- **USB ethernet:** `usb0` sends, but receives only the first packet. Files go over the serial line for now (`tools/put.py`).
- **Timer:** the hardware tick wakes the CPU 1000 times per second. Patch 0006 adds a one-shot mode (`e6.oneshot=1`); with WFI enabled the WLAN chip then gets almost no interrupts, so it is off by default. The counters themselves keep running in WFI and wake the CPU on time (measured).
- **Modem, calls, SMS, mobile data:** kernel side prepared (`build-e72-cell.sh`, patch 0012), userspace runtime not ported, nothing run.
- **kexec:** works shortly after boot, failed twice later; suspected cause and an untested fix (patch 0009) in [idle-and-kexec.md](idle-and-kexec.md).
- **Vibra, microphones:** a vibra driver (patch 0008) and a silent microphone probe module are built but have not run on the device; speaker, earpiece and headset are not started. See [audio-vibra.md](audio-vibra.md).
- **Power saving:** `nohlt` at boot, keyboard polled; WFI and interrupt-driven input are the next steps.
- **Other firmware versions / E72 variants:** only RM-530 with 091.004 has a watchdog entry.

## Next steps

1. Boot the kernel with WLAN, card slot and keypad nodes; test `wifi` and `ssh`.
2. Fix USB ethernet receive.
3. Battery level and power-off on low battery.
4. Power: WFI by default, interrupt-driven keyboard, display blanking.
5. kexec from the USB shell, so new kernels can be tried without Symbian.
