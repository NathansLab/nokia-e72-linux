# WLAN and card slot

**Status: built, untested on the device.**

## Hardware (from a RAM dump of the running Symbian, fw 091.004)

All values are the same as on the E5-00, so the upstream E5 device-tree nodes are used unchanged.

| Item | Value | Found in |
| --- | --- | --- |
| WLAN chip | TI WL1251, firmware Rev 4.0.4.12.12 (CRC32 `0x38a5a30d`, identical to the E5's) | heap copy in the dump |
| SPI block | SPI 2, `P:0x20020600` | literals in `spi2.dll` |
| power pin | GPIO 100 | `wlanhpa.dll`, table at ROM `0x80268818` |
| IRQ pin | GPIO 73 (INTC 389) | same table, `egpio` table `0x800a7830` |
| card slot | `P:0x20032800`, IRQ 173, power resource `0x23`, 96 MHz | `EPBUSMV.DLL` |
| card detect | GPIO 0 (`broken-cd` in the DT, i.e. polled) | `EPBUSMV.DLL` `0x8014ce54` |

Symbian loads `wlanpdd.pdd` + `wlanhpa.dll`; `pltwlanpdd.pdd` (production test) is not loaded.

## Firmware and NVS

The Linux `wl1251` driver needs two files from the phone:

- `ti-connectivity/wl1251-fw.bin`: the chip firmware (TI/Nokia property, 200460 bytes)
- `ti-connectivity/wl1251-nvs.bin`: calibration data, **including this phone's WLAN MAC address**

Neither may be redistributed, so they are not in this repository. Get them from your own phone:

On the E5, upstream's loader copies them out of `wlanhwinit.dll` in the ROM. On the E72 that DLL sits in the demand-paged part of the ROM and is not in a RAM dump, but a Symbian user process keeps both files as a heap copy (chunk at `V:0x00600000`, firmware at offset `0x42f8`, NVS at offset `0x584`, 729 bytes). `tools/wlan/extract_fw_nvs.py` finds that chunk in a dump made with `e72dump` and checks the firmware by its CRC:

```sh
tools/wlan/extract_fw_nvs.py e72ram.bin --out work/wlan-fw
# -> work/wlan-fw/ti-connectivity/wl1251-fw.bin, wl1251-nvs.bin
```

This was done once, on one dump of fw 091.004. If your firmware places the files elsewhere, the script says "firmware not found". The repository's `.gitignore` blocks these file names; keep them out of any public tree. Then build the kernel as in [03-build.md](03-build.md) (`E72_WLAN_FW`); the files are built in with `CONFIG_EXTRA_FIRMWARE`.

## Userland

The initramfs carries Alpine's `wpa_supplicant`, `iw`, `udhcpc` (BusyBox), the SSH client `dbclient` (also as `ssh`), `scp` and `apk`. The `wifi` command is upstream's E5 script (`linux/initramfs/e5-wifi.sh`):

```sh
wifi scan                      # numbered list of networks
wifi '<name>' '<password>'     # WPA/WPA2: save and connect
wifi <number> '<password>'     # network number from the last scan
wifi                           # status
wifi off | on | forget
```

Then, for the intended use as a terminal:

```sh
ssh user@host                  # dropbear's dbclient
```

Nothing is saved across reboots (the initramfs lives in RAM), so `wifi` has to be run again after every boot.

## Idle

`e6.idle=1` prepares the WFI idle path, `nohlt` keeps polling during boot. `echo 1 > /sys/module/idle/parameters/wfi` switches to WFI at run time (patch 0004). If the phone hangs after that, the next boot polls again. Untested.
