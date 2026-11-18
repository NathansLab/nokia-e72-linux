# Mobile data (preparation)

Status 2026-11-18. Built and tested on a PC against a RAM image. Nothing of this has run on the phone.

## Approach

As in the upstream E5 port: the modem software (ISASW) keeps running under Linux inside a userspace runtime; Linux talks to the DSP through the MDI rings and to the modem through Phonet/ISI. E72 firmware 091.004 is a close sibling of the E5's (same tasks, timers, rings, interrupts), but nearly every address moved, and not by one common offset. `cell/e72-addr-table.tsv` lists every address with its evidence (71 confirmed, 26 inferred).

## What exists

- Kernel: `kernel/build-e72-cell.sh`, `kernel/e72-cell.dts`, patch 0012 (VMSPLIT_3G25, Phonet, MDI driver, SIM bridge). Image 15.24 MB.
- Runtime: `cell/0001-e5-cell-e72-fw-091.004.patch` builds E5 and E72 from the same sources (`-DE72_FW091004`). Before touching anything it checks 88 code sites byte for byte and refuses to start on a mismatch. The E5 build stays byte-identical.
- `cell/e72mem/`: module exposing the modem memory windows. `cell/e72-mobile-boot.sh`: start from the card (`/card/linux/cell/`); nothing is added to the initramfs.
- The IMEI comes only from a file written by the user; it is never read from Symbian and never printed.

## Offline tests (qemu, image of running Symbian)

Passed: OS timers, KASUMI, version query through the real firmware path (100 cycles), SIM with a simulated card, DSP descriptors, a 120 s soak. The E5 binary refuses the E72 images; one flipped code byte gives a clean refusal.

The byte checks come from the same image. They prove "same firmware", not that every inferred address means what we think.

## Charger bus

The modem software drives the I2C bus at `0x20032500` itself: charger (0x6b), a sensor (0x29, probably ambient light), earpiece codec (0x18), FM radio (0x22). Under Linux the kernel owns that bus, so the runtime makes the six I2C request entries return "queue full"; the charger and sensor services give up after a few retries without a reset.

Side result: codec, headphone amplifier (0x60), light sensor and radio are reachable from Linux on `i2c3`.

## Signal-level "waterfall"

No raw receiver data reaches the ARM side, so a real spectrum is not possible. The runtime can record the DSP's measurement reports (levels of about 6-32 neighbour channels, roughly once a second): `E5RT_MEAS_TAP=<file or fifo>`, record format in `cell/sim/meas_tap.h`. No viewer yet.

## Order on the phone

1. Boot the cell kernel, load `e72mem.ko`, compare the windows with the image, run the self-tests on the phone.
2. SIM bridge: talk to the card (ATR).
3. Start without an IMEI within 60-90 s of boot, run for 90 s.
4. Start with the IMEI file, watch registration, then a data connection.

Never write network-mode settings (they persist into Symbian). If the runtime dies, only a reboot helps.
