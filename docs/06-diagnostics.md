# 6. Diagnostics: RAM log and RAM dump

When Linux dies before the display or the USB shell works, the only trace is in RAM. A watchdog reset is warm, so the RAM survives until the next power loss. **Do not pull the battery** if you want to read it.

## Loader log

LinuxE72 writes `E:\boot.log` up to the handoff. A good run ends like this (`logs/2026-11-18-first-boot-loader.log`):

```text
LoadLogicalDevice=0
AllocBoot=0 phys=11600000
...
l2 id=41000486 ctrl=00000001 aux=02050249
about-to-Boot (one-way)
```

## Linux RAM log (e72logs)

The kernel mirrors its log to phys `0x17000000` (`earlycon=ramcon`). After a reset back to Symbian:

1. Install `e72logs.sis` again. It only does its work **during installation**, so reinstall it every time.
2. It writes `E:\klog.bin` (1 MB from 0x17000000).
3. On the host:

```sh
python3 tools/parse_klog.py klog.bin > klog.txt   # upstream tool, in the rapuyama-linux tree
$E72/tools/check_trace.py klog.bin                # header, isah block, trampoline trace words
```

`check_trace.py` shows how far the handoff got: the trampoline's stage word (`b0070001` start ... `b0070007` jump into Linux) and its trace words (MMU off reached, copy done, L2 base). If the kernel log is empty but the stage is 7, Linux started and died before its console.

## Full RAM dump (e72dump)

`e72dump.sis` copies the whole 128 MB RAM (0x10000000-0x17feffff) to `E:\e72ram.bin` while Symbian runs, reading through the loader's kernel driver. Progress goes to `E:\e72dump.log`; unreadable blocks are written as zeros. It runs during installation and takes a while; keep at least 128 MB free on the card.

The dump is the basis for the secure-watchdog addresses ([secure-watchdog.md](secure-watchdog.md)), the keyboard table ([keyboard.md](keyboard.md)) and the WLAN firmware ([wlan.md](wlan.md)). File offset = physical address - 0x10000000.

**The dump contains Nokia code, your phone's identifiers and whatever personal data Symbian had in RAM. Keep it private.**

## CPU ID (ptdump, optional)

Upstream's `ptdump.sis` reads the MIDR and Symbian's page tables and writes `ptdump.log`/`ptdump.bin`. For Symbian 9.3 it has to be built against the 9.3 header stage (`driver/stage-e5`); built against the default (Symbian^3) headers it installs but writes nothing. The E72 used here reported MIDR `0x410fb764` (ARM1176JZF-S) in the Linux boot log as well, which is the simpler check.

Next: [7. Kernel modules without rebooting](07-module-workflow.md)
