# Hardware notes (Nokia E72-1, RM-530)

Measured on the device unless noted.

| Item | Value |
| --- | --- |
| SoC | Nokia RapuYama (same family as E5-00, E6, N8, E7) |
| CPU | ARM1176JZF-S, MIDR `0x410fb764` (with TrustZone) |
| RAM | 128 MB, `0x10000000`-`0x17ffffff` (the E5 has 256 MB) |
| L2 cache | L2C-220 at `0x20500000`, 256 KB, `CACHE_ID 0x41000486`, `AUX_CTRL 0x02050249`, enabled by Symbian |
| Display | 320x240, RFBI/DISPC registers read back the E5 values (RFBI CONTROL 4, CONFIG0 `0x00100460`, DISPC CONTROL `0x8b08`), DCS command mode |
| Keyboard | 8x7 GPIO matrix, see [keyboard.md](keyboard.md) |
| WLAN, card slot | see [wlan.md](wlan.md) |
| Interrupt controller, E5 system timer, watchdogs, USB (MUSB) | work unchanged with the E5 drivers |
| OS | Symbian 9.3 (S60 3rd edition FP2), firmware 091.004 |

## Memory layout used by Linux

| Range | Use |
| --- | --- |
| `0x10000000`-`0x115fffff` | Symbian kernel, ROM sections, modem code; kept intact (the watchdog bridge needs parts of it) |
| `0x11600000`-`0x16ffffff` | Linux RAM (90 MB); kernel at `0x11600000` + `0x8000` |
| `0x17000000`-`0x170fffff` | RAM log (`ramcon`), isah handoff block at `0x170f1000`, trampoline trace words at `0x170ff000` |
| `0x17100000`-`0x17ffffff` | not used by Linux; ISASW data at `0x17d50000`, secure message pool at `0x17fe0000` |

On the E5 the same objects sit `0x08000000` higher. Patch 0001 makes the kernel side configurable (`CONFIG_RAPUYAMA_RAM_TOP`), the loader gets `RB_LOGPHYS=0x17000000`.

## Boot traps found on the way

- **E5 build on the E72:** the E5 kernel and loader assume RAM up to `0x20000000`. The loader ran to "about-to-Boot", then the phone reset immediately and the RAM log stayed empty (it was written into non-existing memory).
- **No contiguous block:** Symbian on the E72 never had 16 MB of contiguous free RAM ("no free ram block -4"). LinuxE72 therefore loads Image and dtb into single 4 KB pages; `tramp_scatter.S` copies them into place after switching the MMU off.
- **Cache maintenance:** `mcr p15, 0, rX, c7, c6, 0` (invalidate the whole D-cache without cleaning) is undefined in the non-secure world; Symbian silently killed the app thread. The trampoline uses clean+invalidate (`c7, c14, 0`), the loader flushes the D-cache for every new page, and after the copy the L2 is invalidated by way without touching its control register.
- **USB:** the USB block is off if no cable is connected when Linux starts.
- **Secure watchdog:** reset 240 s after Symbian's last service call, see [secure-watchdog.md](secure-watchdog.md).
