#!/bin/sh
# e5rt offline builds in the e72-cellrt container: E5 from the pre-e72 copies and from the switched
# sources (must be byte-identical), the E72 variant (+ measurement tap) and the tap selftest.
# gcc armel static, non-PIE (qemu-arm tests); the phone build is e5-cell/build.sh (clang + musl).
set -e
CC="arm-linux-gnueabi-gcc -static -fno-pie -no-pie -O2 -march=armv6kz -marm -Wall"
SRC="e5rt-sim.c sim_runtime.c os_timer_runtime.c identity_runtime.c kasumi_runtime.c"
W=/w/work/e72cell
(cd $W/pre && $CC -I. -o $W/e5-before/e5rt $SRC 2>/dev/null)
cd /w/linux/e5-cell/sim
$CC -I. -o $W/e5-after/e5rt $SRC 2>/dev/null
$CC -I. -pthread -DE72_FW091004 -o $W/e72/e72rt $SRC meas_tap.c 2>/dev/null
$CC -I. -pthread -DMEAS_TAP=1 -o $W/e72/meas_tap_test meas_tap_test.c meas_tap.c
cmp $W/e5-before/e5rt $W/e5-after/e5rt && echo "E5 build byte-identical"
ls -la $W/e72/
