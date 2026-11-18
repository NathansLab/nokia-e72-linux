# 3. Build kernel, device tree, initramfs and loader

All commands run from the upstream checkout unless noted. `E72` stands for the path of this repository.

```sh
E72=/path/to/this/repository
```

## 3.1 Get upstream

The E72 port is tested against rapuyama-linux branch `e5-port`, commit `2e30eb9`, with the kernel submodule at `c87fd3697` (fluffleswaffles/linux, branch `e5`, Linux 6.12.0). Keep the tree under `$HOME` if you use Colima.

```sh
git clone https://github.com/fluffleswaffles/rapuyama-linux.git
cd rapuyama-linux
git checkout 2e30eb97081d9f0b42864fd720043f527add1343
# some submodules use ssh URLs; rewrite them to https
git -c url."https://github.com/".insteadOf=git@github.com: submodule update --init --depth 1 \
    linux/kernel/linux tools/src/ensymble tools/src/elf2e32_next \
    symbian/oss.FCL.sf.os.kernelhwsrv symbian/FCL.sf.incubator.modemadaptation
# the Symbian toolchain image is defined on the main branch
git show origin/main:Dockerfile > Dockerfile
```

If `--depth 1` cannot fetch the pinned submodule commit, run the same command without `--depth 1`.

## 3.2 Add the E72 files

```sh
$E72/tools/apply-to-upstream.sh .
```

This copies `e72.dts` to `linux/boot/`, `build-e72.sh` to `linux/kernel/`, the two initramfs scripts to `linux/initramfs/`, the build helpers to `tools/`, and applies

- `kernel/patches/0001..0004` to `linux/kernel/linux` (`git apply`),
- `loader/0001-loader-e72.patch` to the upstream tree,
- `tools/ensymble-run-on-install.patch` to `tools/src/ensymble`.

| Patch | What it does |
| --- | --- |
| 0001-rapuyama-ram-top-configurable | `CONFIG_RAPUYAMA_RAM_TOP`: every fixed top-of-RAM address (RAM log, isah handoff block, modem shared memory) follows it; 0x18000000 for the 128 MB E72 |
| 0002-secure-wdt-e72-fw-091.004 | E72 entry in the secure-watchdog bridge, per-firmware list of Symbian pages to keep, BTrace filter clearing |
| 0003-keypad-pins-from-device-tree | keypad driver takes rows/columns from `nokia,row-gpios` / `nokia,col-gpios` |
| 0004-idle-e72-runtime-switch | WFI idle switchable at run time (`/sys/module/idle/parameters/wfi`) |
| loader/0001-loader-e72 | LinuxE72: reads `E:\e72.dtb`, RAM log and isah block relative to `RB_LOGPHYS`, scatter boot (`tramp_scatter.S`), error report instead of a silent exit; new `e72dump_app.cpp` |
| ensymble-run-on-install | `.exe` files in `sys\bin` run once during installation (diagnostic apps); `ENSYMBLE_NORUN=1` turns that off for menu apps such as LinuxE72 |

## 3.3 Build the two container images

```sh
docker build --platform=linux/amd64 -t symbian-build:latest .
docker build --platform=linux/arm64 -t e72-kbuild tools/kbuild
```

The first one downloads GCCE 4.6.3 from the Internet Archive and checks its SHA-256.

## 3.4 BusyBox and the Alpine userland

```sh
mkdir -p work/dl
curl -fL -o work/dl/busybox-armv5l \
    https://busybox.net/downloads/binaries/1.31.0-defconfig-multiarch-musl/busybox-armv5l
chmod +x work/dl/busybox-armv5l

docker run --rm -v "$PWD:$PWD" -w "$PWD/linux/initramfs" e72-kbuild ./e72-rootfs.sh
```

`e72-rootfs.sh` installs Alpine v3.22 armhf packages (`wpa_supplicant`, `iw`, `dropbear-dbclient`, `dropbear-scp`, `kexec-tools`, `apk-tools`, BusyBox, musl, CA certificates) into `work/rootfs-e72` and prunes them to what the listed programs need (upstream `tools/prune_rootfs.py`). It runs once; delete `work/rootfs-e72.pruned` to redo it.

## 3.5 WLAN firmware (optional)

The WL1251 firmware and the NVS file (with your phone's MAC address) are built into the kernel if they exist. They are not in this repository; [wlan.md](wlan.md) shows how to get them from your own phone. Put them here:

```text
work/wlan-fw/ti-connectivity/wl1251-fw.bin
work/wlan-fw/ti-connectivity/wl1251-nvs.bin
```

Without them the kernel builds and boots, WLAN just has no firmware. A kernel `Image` built with them contains Nokia/TI code and your MAC address: do not publish it.

## 3.6 Kernel and device tree

```sh
docker run --rm -v "$PWD:$PWD" -w "$PWD/linux/kernel" \
    -e E72_WLAN_FW="$PWD/work/wlan-fw" e72-kbuild ./build-e72.sh config
docker run --rm -v "$PWD:$PWD" -w "$PWD/linux/kernel" e72-kbuild ./build-e72.sh build
```

Output:

```text
linux/kernel/build-e72/arch/arm/boot/Image   (uncompressed, about 18 MB with the userland)
linux/kernel/build-e72/e72.dtb
```

`config` starts from upstream's `e6.config` with the E5 changes (display, keypad, WL1251 on SPI, GDMA, USB CDC composite gadget, slimmed down) and adds `RAPUYAMA_RAM_TOP=0x18000000`, kexec, unrestricted `/dev/mem`, `/proc/config.gz`, TUN, WireGuard, 100 Hz and the initramfs list (BusyBox `/init`, `e72-init.sh`, Alpine files, the upstream `wifi` script as `/usr/bin/wifi`). `build` only runs `config` if there is no `.config` yet, so rerun `config` after you change the script or add the WLAN files.

## 3.7 Signing certificate

The `.sis` packages are signed with your own certificate. Symbian 9.3 needs RSA 1024 with SHA-1 and Ensymble needs the key in the traditional PKCS#1 format (`BEGIN RSA PRIVATE KEY`):

```sh
openssl req -x509 -newkey rsa:1024 -sha1 -keyout key_pk8.pem -out driver/sis/cert.pem \
    -days 7300 -nodes -subj "/CN=rapuyama-dev"
openssl rsa -in key_pk8.pem -out driver/sis/key_trad.pem   # OpenSSL 3: add -traditional
rm key_pk8.pem
```

Keep the key private and out of git (upstream's `.gitignore` already ignores `driver/sis/*.pem`).

## 3.8 Loader and diagnostic apps

```sh
$E72/loader/build-loader.sh .
```

This assembles the scatter trampoline into `linux/stage0/tramp_scatter.hdr`, creates the Symbian 9.3 header stage `driver/stage-e5` and builds:

| File | UID | Installed | Does |
| --- | --- | --- | --- |
| `out/linuxe72.sis` | 0xE1000072 | menu app **LinuxE72** | loads `E:\Image` + `E:\e72.dtb`, hands the phone to Linux, logs to `E:\boot.log` |
| `out/e72logs.sis` | 0xE1000074 | runs during installation | copies 1 MB of RAM from 0x17000000 (the Linux RAM log) to `E:\klog.bin` |
| `out/e72dump.sis` | 0xE1000076 | runs during installation | copies 128 MB of RAM from 0x10000000 to `E:\e72ram.bin` (log `E:\e72dump.log`) |

The apps contain upstream code; upstream declares no licence, so do not redistribute the built packages without the upstream authors' permission.

Next: [4. Copy to the card and boot](04-install-and-boot.md)
