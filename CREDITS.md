# Credits

## Upstream port

**rapuyama-linux** - <https://github.com/fluffleswaffles/rapuyama-linux>

Linux for the Nokia RapuYama phones, started from a running Symbian. Everything here builds on it: the Symbian loader and its kernel driver, the RapuYama kernel support (interrupts, timers, GPIO, clocks, watchdogs), the E5 display, keypad, MMC and WL1251/SPI drivers, the RAM log, the secure-watchdog bridge, the initramfs scripts and the build tooling. The E72 port uses branch `e5-port` at commit `2e30eb9`.

- **fluffleswaffles** (<https://github.com/fluffleswaffles>) - creator of the project and the Nokia E6 port, owner of the kernel fork and the tool forks below.
- **Kapina-Dev** (<https://github.com/Kapina-Dev>) - the Nokia E5-00 port (branch `e5-port`), which is the direct base of this work.

Licence: the repository declares no licence of its own (no LICENSE file, GitHub shows none, checked 2026-11-18). Its kernel code is GPL-2.0 (SPDX headers, and it is part of the Linux kernel); a few of its tools carry `GPL-2.0-only` headers.

**Kernel fork** - <https://github.com/fluffleswaffles/linux>, branch `e5` (commit `c87fd3697`, Linux 6.12.0), the tree the patches in `kernel/patches/` apply to.

## Software used in the build or on the phone

| Project | Use | Licence | Link |
| --- | --- | --- | --- |
| Linux kernel | the kernel | GPL-2.0 WITH Linux-syscall-note | <https://www.kernel.org/> |
| BusyBox | `/bin/busybox` in the initramfs (official static `busybox-armv5l` 1.31.0 build) | GPL-2.0 | <https://busybox.net/> |
| Alpine Linux | armhf packages for the userland (v3.22) | per package | <https://alpinelinux.org/> |
| musl | C library of the Alpine userland | MIT | <https://musl.libc.org/> |
| apk-tools | Alpine package manager | GPL-2.0 | <https://gitlab.alpinelinux.org/alpine/apk-tools> |
| wpa_supplicant | WLAN authentication | BSD-3-Clause | <https://w1.fi/wpa_supplicant/> |
| iw | WLAN configuration | ISC | <https://wireless.wiki.kernel.org/en/users/documentation/iw> |
| Dropbear | SSH client `dbclient`, `scp` | MIT-style (see its LICENSE) | <https://matt.ucc.asn.au/dropbear/dropbear.html> |
| kexec-tools | `kexec` | GPL-2.0 | <https://git.kernel.org/pub/scm/utils/kernel/kexec/kexec-tools.git> |
| Unicorn | CPU emulation for the secure-watchdog analysis | GPL-2.0 | <https://www.unicorn-engine.org/> |
| Capstone | disassembler for the analysis | BSD-3-Clause | <https://www.capstone-engine.org/> |
| pyserial | host tools over the USB serial port | BSD-3-Clause | <https://github.com/pyserial/pyserial> |
| Ensymble | `.sis` packaging; original by Jussi Ylänen, used via the fork of fluffleswaffles (from essaic/ensymble) | GPL-2.0-or-later | <https://github.com/fluffleswaffles/ensymble>, <https://github.com/essaic/ensymble> |
| elf2e32_next | ELF to Symbian E32 image converter (fork of fedor4ever/elf2e32_next) | EPL-1.0 (file headers) | <https://github.com/fedor4ever/elf2e32_next> |
| GCCE 4.6.3 | Symbian toolchain, Sourcery CodeBench Lite 2012.03-42 (`arm-none-symbianelf`), from the Internet Archive's "Symbian and Nokia Development Tools" collection | GPL (GCC, binutils) | <https://archive.org/details/symbian_dev> |
| Symbian Foundation sources | kernel headers (`oss.FCL.sf.os.kernelhwsrv`) and modem adaptation headers used to build the loader driver | EPL-1.0 | <https://github.com/SymbianSource> |
| Debian | base of the kernel build container (`gcc-arm-linux-gnueabi`, `dtc`) | per package | <https://www.debian.org/> |

## Unlocking

The Symbian unlock (Trend Micro method, RomPatcher+ with the Install Server and Open4All patches) follows the LPC wiki page [Jailbreaking S60 devices](https://lpcwiki.miraheze.org/wiki/Jailbreaking_S60_devices). Those tools are third-party software and are not distributed here.

## This repository

E72 port by **NathansLab**.
