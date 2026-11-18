# Keyboard

**Status (2026-11-18):** with the test module (`kernel/e72kp-testmodule`) these keys arrived at exactly the expected positions on the device: Q (r0c0), A (r1c0), Z (r2c0), P (r3c2), Space (r6c1), Enter (r5c2), Up (r7c0), Centre (r7c4). The other 47 keys follow Symbian's table and have not been pressed one by one. `kernel/e72.dts` now carries the matrix for the built-in driver (patch 0003); that kernel has been built but not yet booted.

## Source

The data area of Symbian's `ekeyb.dll` (ROM `0x8015db70`, data `V:0xc8009a20`) in a RAM dump.

- Matrix of 8 rows x 7 columns, scanned like on the E5: columns are outputs and rest at 0, rows are read from the GPIO interrupt block's raw state.
- Row GPIOs: 26, 119, 35, 24, 120, 121, 38, 36. Column GPIOs: 61, 60, 59, 58, 62, 57, 56 (list from `0xc8009a28`).
- Checked under Linux: all rows read 1, the column outputs are at 0.
- Scan table (`0xc8009a68`, index row*8+column, Symbian scan codes):

| Row | Columns 0..6 |
| --- | --- |
| 0 | Q W E R(1) T(2) Y(3) U(*) |
| 1 | A S D F(4) G(5) H(6) J(#) |
| 2 | Z X C V(7) B(8) N(9) M(0) |
| 3 | I O P `17` `7e` `a4` `c4` |
| 4 | K L `01` `a2` `12` `ec` `b4` |
| 5 | `79` `7a` `03` `a5` `c5` `7d` `a3` |
| 6 | `18` `05` `81` `e8` `e4` `82` `19` |
| 7 | `10` `11` `0e` `0f` `a7` - `f2` |

`01` Backspace, `03` Enter, `05` Space, `0e/0f/10/11` left/right/up/down, `12` Shift, `17` Ctrl, `18/19` Fn, `a4/a5` soft keys, `a7` centre, `c4/c5` call/end.

The Linux keycodes chosen for these positions are the `linux,keymap` entries in `kernel/e72.dts` (format `row << 24 | col << 16 | keycode`). Keys without an obvious Linux equivalent (Fn, Sym, soft keys, call keys) were mapped to substitutes such as Esc, Tab, Alt and F1-F8; a proper layout with Fn/Sym layers like the upstream E5 port is still to do.

## Driver

- Built-in: upstream `rapuyama-e5-keypad.c` with patch 0003, pins from `nokia,row-gpios` / `nokia,col-gpios` (u8 arrays) in the device tree. Polled (the test module defaults to 20 ms).
- Test module: [07-module-workflow.md](07-module-workflow.md).

Polling costs power; an interrupt-driven scan is a later step.
