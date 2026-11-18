# 1. Prerequisites

## Phone

- **Nokia E72-1, RM-530.** Other E72 variants (RM-529, RM-584) were not tested.
- **Firmware 091.004.** Check with `*#0000#`. The secure-watchdog bridge needs addresses that are specific to one firmware build; with another version Linux boots but resets after 3-4 minutes until you have added your firmware (see [secure-watchdog.md](secure-watchdog.md)).
- **CPU check (optional):** the kernel is built for the ARM1176JZF-S (MIDR `0x410fb764`), which is what this E72 reported. Upstream's `ptdump.sis` reads the MIDR on any phone (see [06-diagnostics.md](06-diagnostics.md)).
- A **charged battery.** Linux does not monitor or charge it. Do not pull the battery after a failed boot if you want the RAM log: it survives a warm reset, not a power loss.
- Use a phone without personal data on it. Unlocking (step 2) patches Symbian's installer.

## Memory card

- A **microSD card**, FAT formatted as Symbian does it. It appears as `E:` in Symbian. The loader reads `E:\Image` and `E:\e72.dtb` from it, the diagnostic apps write their files to it.
- Linux does not write to the card unless you mount it yourself.

## Cable

- A **micro-USB data cable**. It must be plugged in **before** you start LinuxE72: without a cable at boot the USB block stays switched off and there is no shell.

## Host

Everything was done on macOS (Apple silicon) with Docker via Colima; a Linux host works the same way.

- `git`, `python3` (with `pyserial` for the serial tools)
- **Docker** (or Podman) with two images:
  - `symbian-build` (linux/amd64): Symbian toolchain (GCCE 4.6.3, elf2e32_next, Ensymble), from upstream's `Dockerfile` on the `main` branch. On Apple silicon it runs emulated, which is slow but works.
  - `e72-kbuild` (linux/arm64): Debian with `gcc-arm-linux-gnueabi` and `dtc` for the kernel, from [`tools/kbuild.Dockerfile`](../tools/kbuild.Dockerfile). On an x86-64 host change the `--platform` line or build natively.
- With Colima: only your home directory is shared into the VM, so keep the build tree under `$HOME`. Give the VM all cores, e.g. `colima start --cpu 10 --memory 6`, and check with `docker run --rm e72-kbuild nproc`.
- `openssl` to create the self-signed certificate for the `.sis` packages.
- A card reader, or the phone's USB mass-storage mode, to copy files to the card.

Next: [2. Allow self-signed apps](02-unlock-symbian.md)
