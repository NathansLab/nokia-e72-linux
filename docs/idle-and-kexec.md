# Idle, wake-up and kexec

Status 2026-11-18. Findings from static analysis of Symbian's `power.dll`, GPIO and WLAN drivers in a RAM image. The Linux changes that follow from them are built but have not run on the device.

## How Symbian idles

- `CpuIdle` takes the idle time in ms and picks a mode 0-6: >= 1 ms mode 6, >= 2 ms mode 4, >= 3 ms mode 2, >= 4 ms mode 1, about >= 7 ms mode 0. Drivers and the modem can limit the mode.
- Mode 6: plain WFI (what Linux does today).
- Modes 3-5: WFI with a stretched tick. The 7.68 MHz counter keeps running; (N-1)*7680 is added through `0x200401a4` before sleeping and the elapsed time is taken from the same counter afterwards. Modes 3/4 also set bit 1 of `0x200331a0` around the WFI (set `0x200331a4`, clear `0x200331a8`). Limit 279 s.
- Modes 0-2: deep sleep through the secure world (context save, sleep timer `0x2003362c` in 8192 Hz units, interrupt 247). Time is recovered from the 32768 Hz counter.
- "Constrained" is bit 3 of `0x20033140`. Which clocks it keeps is not determined.

## Wake-up

- There is no wake-enable mask: any unmasked interrupt line wakes the CPU from WFI.
- Every GPIO pin has its own interrupt line (GPIO 73 -> 389).
- Symbian runs the WLAN pin (GPIO 73) as a level interrupt: mask in the ISR, unmask after the deferred work. Keyboard and Bluetooth do the same. Linux's wl1251 forces a rising edge.
- Suspected reason for the WLAN stall with the one-shot tick: an edge is lost during longer WFI periods and the chip then holds its line high. Not proven.
- Register map correction: in the GPIO interrupt block, +0x0c is the enable state, not +0x18.

## Kernel changes (not yet run)

- `0010-wl1251-level-irq.patch` with `kernel/e72-level.dts`: WLAN interrupt as a level interrupt, as a separate dtb so the known-good path stays.
- `0011-idle-deep-bit-sec-poll-param.patch`: `/sys/module/idle/parameters/deep` (mode 3/4 bit when the next event is >= 2 ms away) and `sec_poll_ms` (the 10 ms poll of the secondary interrupt bank wakes the CPU 100 times a second; 0 stops it).
- Still open: interrupt-driven keyboard, unconstrained idle, deep sleep (modes 0-2).

## kexec failures

- Observation: four kernel switches 1-2 minutes after boot worked, two later ones (> 3.5 minutes) ended in a reset to Symbian.
- Finding: the modem software stores the token returned by the secure watchdog back into its slot; the Linux bridge kept it only in its own memory. A kexec'd kernel therefore read Symbian's old token, which is two steps stale after two calls (5 s and 215 s).
- That this is the cause is not proven (it assumes a token one step old is still accepted). `0009-secure-wdt-token-write-back.patch` writes the token back.
- Ruled out: page reservations. All pages the bridge needs lie below Linux RAM.

## Keyboard by interrupt

`0013-keypad-row-interrupts-gpio-enable-reg.patch`: with `rapuyama_e5_keypad.irq=1` and `e72-level.dtb` the driver waits for a level interrupt on the eight row pins while no key is down and scans every 20 ms only while a key is held. Without the parameter it polls as before. Not yet run.

The GPIO interrupt block counts in "logical" pin numbers: 0-87 unchanged, 106-137 as pin - 18 (pin 119 -> line 303, bank 3 bit 5). An interrupt on pin 119 is therefore `<&gpio 101 ...>` in the device tree.
