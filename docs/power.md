# Idle current

Status 2026-11-18. Measured: about 147 mA idle (WLAN in power save, display dark, 97 % of the time in WFI). The analysis below is static; the mA figures are guesses and none of it has been measured yet.

## Findings

- Clock gates are not the reason: under Linux they are almost the same as Symbian's at handoff. Dropping `clk_ignore_unused` changes nothing (every clock is registered as "do not gate").
- Still on when Linux starts: SDRAM vote, performance level 32, Vaux1 (navigation key, display), VMEM (card), the USB domain with its 19.2 MHz clock.
- The names in `clk-rapuyama.c` are shifted by one for ids 0x0b-0x28 (labels only, the gate numbers are right).
- The card controller clock is never gated.

## Ranking (saving divided by risk)

1. Put the panel to sleep instead of brightness 0 (3-15 mA, no risk). Done in `e72-lights`.
2. Radio/DSP may keep running: start Linux once from the Offline profile with Bluetooth off and compare (0-60 mA, no risk).
3. Fewer wake-ups: one-shot tick, `sec_poll_ms=0`, keyboard interrupts, cursor blink off (2-8 mA).
4. USB standby without a cable, clocks off (5-15 mA, medium risk).
5. Unconstrained WFI (maybe 10+ mA, medium to high risk).
6. Lower the ARM PLL when idle (5-20 mA, high risk; sequence known, not scripted).
7. Two clocks forced on for nothing (< 1 mA), card clock off between requests (1-3 mA).
8. Deep sleep as Symbian does it (the largest item, a large project).

## Measuring

`tools/e72-power-steps.sh` (never run): `measure`, `snap` (read-only), then single steps `<step> off|on`, or `walk` for all harmless steps. Run it over SSH with the USB cable unplugged. After each clock step it checks the PMIC bus and undoes the step if that fails.

## Open

Regulator bits for Vaux1/Vaux2/VMEM, whether radio or DSP are active after the jump, GPIOs for Bluetooth reset, GPS, navigation key and camera, the real current per block.
