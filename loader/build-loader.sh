#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Builds the three Symbian apps for the E72 inside an upstream checkout that
# already has the E72 files (tools/apply-to-upstream.sh):
#   out/linuxe72.sis  LinuxE72: menu app, loads E:\Image + E:\e72.dtb, boots Linux
#   out/e72logs.sis   runs on install, copies the Linux RAM log to E:\klog.bin
#   out/e72dump.sis   runs on install, copies all 128 MB of RAM to E:\e72ram.bin
#
# needs: docker (or podman), the images "symbian-build" (upstream Dockerfile
# from the main branch) and "e72-kbuild" (tools/kbuild/Dockerfile), and a
# self-signed certificate in driver/sis/cert.pem + driver/sis/key_trad.pem
# (RSA 1024 / SHA-1, see docs/03-build.md; Symbian 9.3 rejects RSA 2048/SHA-256
# with "file corrupted").
#
# usage: loader/build-loader.sh <path to the rapuyama-linux checkout>
set -euo pipefail
B="$(cd "${1:?usage: $0 <rapuyama-linux checkout>}" && pwd)"
[ -f "$B/driver/sis/cert.pem" ] && [ -f "$B/driver/sis/key_trad.pem" ] || {
	echo "missing driver/sis/cert.pem or key_trad.pem"; exit 1; }

# 1. scatter trampoline -> linux/stage0/tramp_scatter.hdr (ARM, MMU-off code)
docker run --rm -v "$B:$B" -w "$B/linux/stage0" e72-kbuild bash -c '
set -e; C=arm-linux-gnueabi-
${C}gcc -march=armv6 -marm -mfloat-abi=soft -ffreestanding -nostdlib -c ../boot/tramp_scatter.S -o tramp_scatter.o
${C}ld -nostdlib -Ttext 0 --entry tramp_scatter tramp_scatter.o -o tramp_scatter.elf
${C}objcopy -O binary tramp_scatter.elf tramp_scatter.bin
{ printf "// auto-generated from tramp_scatter.bin -- do not edit\nstatic const unsigned char KTrampScatter[] = {\n"
  od -An -v -tu1 tramp_scatter.bin | sed "s/[0-9][0-9]*/&,/g; s/^/    /"
  printf "};\nstatic const unsigned KTrampScatterLen = sizeof(KTrampScatter);\n"; } > tramp_scatter.hdr'

# 2. the Symbian 9.3 header stage (driver/stage-e5) for the kernel-side driver
[ -d "$B/driver/stage-e5" ] || docker run --rm --platform=linux/amd64 -v "$B:$B" -w "$B" \
	symbian-build:latest bash -c driver/mkstage-e5.sh

# 3. the three apps. build_app.sh calls "podman run ... python:2.7 ensymble";
#    tools/podman-shim/podman turns that into a local python2 call
docker run --rm --platform=linux/amd64 -v "$B:$B" -w "$B/linux/stage0/symbian-loader" \
	-e PATH="$B/tools/podman-shim:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
	symbian-build:latest bash -c '
set -e
export STAGE='"$B"'/driver/stage-e5 LDD_SRC=e5boot_ldd.cpp NO_BLOBS=1
ENSYMBLE_NORUN=1 RB_DEFS="-DRB_IMAGE_BOOT -DRB_E5 -DRB_E5_ISAH -DRB_E72 -DRB_LOGPHYS=0x17000000u" \
	CAPTION=LinuxE72 ICON=../../../driver/sis/linuxe5.svg ./build_app.sh linuxe72 boot_app.cpp 0xe1000072
RB_DEFS="-DRB_E5 -DRB_LOGPHYS=0x17000000u" CAPTION=e72logs ./build_app.sh e72logs ramread_app.cpp 0xe1000074
RB_DEFS="-DRB_E5 -DRB_LOGPHYS=0x17000000u" CAPTION=e72dump ./build_app.sh e72dump e72dump_app.cpp 0xe1000076
'
ls -la "$B/out/linuxe72.sis" "$B/out/e72logs.sis" "$B/out/e72dump.sis"
