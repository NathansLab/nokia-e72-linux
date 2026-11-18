# Secure watchdog (PA_SWD) on the E72, firmware 091.004

## The problem

The secure-side service PA_SWD resets the phone 240 s after it was last serviced. Symbian services it every 210 s through the modem software (ISASW). After the handoff nobody does, so Linux died 3-4 minutes after boot.

The upstream E5 port has a bridge for this (`arch/arm/mach-rapuyama/secure_wdt.c`): Linux calls the ISASW functions themselves, with Symbian's page tables, on a borrowed ISASW task stack. That needs one table entry per firmware build. Patch `0002-secure-wdt-e72-fw-091.004.patch` adds the E72 entry; `e6.swd=1` in `e72.dts` turns the bridge on.

## Result on the device (2026-11-18)

```text
rapuyama-swd: call 1 stage 60 transport 1 result 1 timeout 240 token 240
```

Then Linux ran for more than 15 minutes without a reset (before: 3-4 minutes). Later calls are only logged with `pr_debug`; an error would be logged. Full session: `logs/2026-11-18-watchdog-bridge-session.txt`.

## Values for the E72 (fw 091.004) and the E5 (fw 101.003)

Source: a RAM dump of the running Symbian (`e72dump`, 128 MB from phys 0x10000000; not in this repository).

| Item | E72 091.004 | E5 101.003 |
| --- | --- | --- |
| ISASW code | `V:0xc6300000` = `P:0x10480000` | same |
| ISASW data | `V:0xc6800000` = `P:0x17d50000` | `P:0x1fd50000` |
| message pool | `V:0xc6b00000` = `P:0x17fe0000` | `P:0x1ffe0000` |
| alloc / free | `0xc636eb72` / `0xc636ea6c` | `0xc6369442` / `0xc636933c` |
| call, command `0x1f` | `0xc636fa1e` | `0xc636a2ee` |
| wrapper (alloc, call, restart timer) | `0xc6366a20` | `0xc6361988` |
| handle / token | `0xc6831552` (handle `0x33`), token 240 at `+2` | `0xc6830fc2` |
| literal pointing to the token | code offset `0x66afc` | `0x61a64` |
| task table | 48 entries of 20 bytes from `0xc68362f0`, sp at `+8` | from `0xc6835d44` |
| borrowed stack | task `0x10`, sp word `0xc6836438` | task `0x1d` |
| pointer to the PA table | `0xc68316cc` -> `0xcb294000` | `0xc6831104` |
| PA_SWD in that table | entry 4, offset `0x32b0`, length `0x23d0` | same |
| host table (VA->PA) | `V:0xc80088f4`, entry 3 = `0x80108098` | `0x80107988` |
| jump into the public ROM | `V:0xc607120c` = `P:0xfffd120c` | |

Function addresses are Thumb (the table in the kernel stores them with bit 0 set). The E72 ISASW is the E5's, with the code moved by `+0x5730` and the data by `+0x590`.

## How the addresses were found

All with the RAM dump and the scripts in `tools/swd-analyse/` (Python 3 with `unicorn` and `capstone`; `E72RAM=path/to/e72ram.bin`):

1. **`ram.py`** maps the dump: physical access, and virtual-to-physical translation through Symbian's L1 table at `P:0x10000000`.
2. **`findswd.py`** finds the candidates for alloc, free and the call by their Thumb prologues (the E5 functions start with `0x4605b570`, `0x4606b5f8`, `0x4605b5fe`) and keeps call sites where alloc, call and free are used together.
3. **`callers.py <va>`** walks the call graph upwards and marks the ISASW task loops, to find the wrapper and a task whose stack can be borrowed.
4. **`emu.py [sp]`** runs alloc, alloc, call, free, free in Unicorn on the dump (ARM1176 model) and logs every page touched and every MMIO access. **`emu2.py`** logs the individual accesses in interesting pages, **`emu3.py`** stubs the jump into the secure ROM and prints its arguments (`ZERO=1` clears the BTrace filter first, `ALL=1` lists all pages).

What the emulation showed:

- Everything the call reads lies below `0x11600000` (ROM sections from `P:0x10900000`, kernel tables, ISASW code) or above `0x17000000` (ISASW data, pool), so it survives Linux. Exception: BTrace, below.
- Stack use up to the ROM call: `0x128` bytes.
- Registers touched: `P:0x2040008c` / `0x20400088` (interrupt controller) and `P:0x20030300`, as on the E5.
- Handover to the ROM: `r0 = 0x17fe0000` (pool), command `0x1f` and `P:0x101c72b0` (the PA_SWD image) on the stack.

**BTrace trap.** The host function calls `0x80066b28` (BTrace). On this firmware a handler is installed (`*(0xc8001c1c) = 0x802aa350`) and the category is enabled. The handler reads kernel-heap objects (`V:0xc80cd000`, `0xc80d1000`, `0xc80d5000`, at `P:0x129xxxxx` in the dump), which is in the middle of Linux RAM. Instead of finding and reserving those pages, the kernel clears the 256 filter bytes at `V:0xc8001b1c` (`P:0x10011b1c`); BTrace then returns immediately and the emulated call touches no Linux RAM page any more.

The L1 entries of all megabytes involved were the same in two different Symbian boots, so the values do not depend on one boot.

## Another firmware version

With a different firmware the kernel prints `rapuyama-swd: unknown ISASW build (not in swd_fws[]), nothing kept` and the phone resets after 3-4 minutes. To add it:

1. Boot Symbian, install `e72dump.sis`, copy `E:\e72ram.bin` to the host.
2. Check where ISASW code and data are (`ram.py`: translate `0xc6300000` and `0xc6800000`), find alloc/free/call with `findswd.py`, the token literal and handle, the task table and a parked task's stack word, the PA table pointer.
3. Run `emu.py` / `emu3.py` with your addresses (edit the constants at the top of `emu.py`). Check that no page in Linux RAM (`0x11600000`-`0x17000000`) is touched; if one is, find out why (as with BTrace) before going on.
4. Add an entry to `swd_fws[]` in `secure_wdt.c` (see the E72 entry in patch 0002): `sig_off`/`sig` (prologue offsets and words of alloc, free, call), `token_lit`, `sp_off`, the three function addresses (Thumb bit set), `pat_ptr`, the `keep_va` list (every Symbian page outside the ISASW areas that the emulated call read) and, if needed, `btrace_filter`.
5. Rebuild, boot, check for `call 1 ... result 1` in `dmesg` and let the phone run for more than 4 minutes.

The entry is chosen at boot by its prologue signatures, so a wrong firmware is detected and the bridge stays off instead of calling random code.
