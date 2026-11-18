# 4. Copy to the card and boot

## Files on the memory card

Copy to the root of the card (`E:\` in Symbian), with a card reader or the phone's USB mass-storage mode:

| File on the card | From |
| --- | --- |
| `E:\Image` | `linux/kernel/build-e72/arch/arm/boot/Image` |
| `E:\e72.dtb` | `linux/kernel/build-e72/e72.dtb` |
| `E:\linuxe72.sis` | `out/linuxe72.sis` |
| `E:\e72logs.sis` | `out/e72logs.sis` (for a failed boot, see [06-diagnostics.md](06-diagnostics.md)) |

The names are fixed in the loader. Eject the card cleanly before putting it back into the phone.

## Install

1. Open `linuxe72.sis` from the card in Symbian's file manager and install it to the **phone memory (C:)**.
2. LinuxE72 appears in the menu (usually in the Installations folder).

## Boot

1. Charge the battery in Symbian.
2. For the USB shell: plug the USB cable into the host **now**. In Symbian, choose **PC Suite** as the USB mode (not mass storage: the card must stay mounted in the phone).
3. Close other apps.
4. Start **LinuxE72**. It shows "LinuxE72 v3b", then "loading ... %" while it reads Image and dtb into single 4 KB pages, then hands over. The screen switches to the Linux console a few seconds later.

If Symbian has no free memory for the boot buffer, LinuxE72 asks "no free ram block ... close apps and retry?". If the handoff fails, it shows "handoff failed" and writes the reason to `E:\boot.log`.

## What happens

```text
Symbian
  |_ LinuxE72 (exe + kernel driver e5boot_ldd)
       |_ reads E:\Image and E:\e72.dtb into single 4 KB pages
       |_ saves Symbian's page-table info (isah block at 0x170f1000) for the watchdog bridge
       |_ MMU off, tramp_scatter copies the pages to 0x11600000
       |_ jumps into Linux (one way)
Linux 6.12
  |_ early log in RAM at 0x17000000 (earlycon=ramcon)
  |_ secure watchdog bridge (e6.swd=1) keeps PA_SWD happy
  |_ initramfs /init = e72-init.sh -> upstream init.sh
       |_ USB gadget: serial shell on ttyGS0 (+ CDC ECM usb0)
       |_ shell on tty1 (display + keyboard)
       |_ 20 s after boot: hardware inventory into the kernel log
       |_ no USB host configured after 150 s: reboot, so the RAM log can be read back
```

Everything runs from RAM. The phone's flash is not written. `reboot` returns to Symbian.

**Reboot without a USB host.** `e72-init.sh` reboots the phone after 150 s if no PC has configured the USB gadget. This was meant for the early bring-up without display. If you want to use the phone without a cable, remove that block from `initramfs/e72-init.sh` and rebuild.

## Changing the boot arguments

The kernel command line is in `kernel/e72.dts` (`chosen/bootargs`). Important ones:

| Argument | Meaning |
| --- | --- |
| `earlycon=ramcon,0x17000000 keep_bootcon` | kernel log into RAM, readable after a reset with e72logs |
| `e6.swd=1` | secure-watchdog bridge on |
| `e6.lowmem=0` | no reuse of RAM below the kernel (all of 0x11600000-0x17000000 is Linux's anyway) |
| `nohlt e6.idle=1` | poll at idle, WFI prepared and switchable at run time |
| `e6.usbsh` | serial shell on the USB gadget |
| `g_cdc.host_addr / dev_addr` | fixed, locally administered MAC addresses for USB ethernet |
| `panic=10` | reboot 10 s after a panic |

After editing, rebuild the dtb (`./build-e72.sh build` also does it) and copy `e72.dtb` to the card. The kernel image does not need to change.

Next: [5. USB shell](05-usb-shell.md)
