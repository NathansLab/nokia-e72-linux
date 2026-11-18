# 7. Kernel modules without rebooting

Each boot goes through Symbian and the card, so trying a driver change by rebooting is slow. A module built against the running kernel can be copied over the USB shell and loaded with `insmod`. This is how the keyboard matrix was found.

## Build

In the upstream tree, after the kernel build (`linux/kernel/build-e72` exists):

```sh
docker run --rm -v "$PWD:$PWD" -v "$E72:$E72" -w "$PWD/linux/kernel" e72-kbuild bash -c '
  make -C linux O=$PWD/build-e72 ARCH=arm CROSS_COMPILE=arm-linux-gnueabi- modules_prepare
  make -C linux O=$PWD/build-e72 ARCH=arm CROSS_COMPILE=arm-linux-gnueabi- \
       M='"$E72"'/kernel/e72kp-testmodule KBUILD_MODPOST_WARN=1 modules'
```

`modules_prepare` does not change the kernel image. `KBUILD_MODPOST_WARN=1` turns missing-symbol errors into warnings, because the build tree has no `Module.symvers` from a full `make modules`.

## Copy and load

```sh
tools/put.py kernel/e72kp-testmodule/e72kp.ko /tmp/e72kp.ko
```

On the phone:

```sh
insmod /tmp/e72kp.ko                 # E72 pins and keymap are the defaults
dmesg | tail                         # "8x7 matrix, polled 20 ms ..."
# every key change is logged as "key rN cM down/up" (learn=1 by default)
rmmod e72kp
```

## The keyboard test module

`kernel/e72kp-testmodule/e72kp.c` is derived from the upstream E5 keypad driver (`rapuyama-e5-keypad.c`, GPL-2.0). For testing it registers its own platform device (GPIO block 0x20031900, IRQ block 0x20033400), so it works without a device-tree node, and every setting is a module parameter:

| Parameter | Default | Meaning |
| --- | --- | --- |
| `rows=` | `26,119,35,24,120,121,38,36` | row GPIOs (inputs) |
| `cols=` | `61,60,59,58,62,57,56` | column GPIOs (outputs) |
| `keymap=` | E72 table | `linux,keymap` style entries (row << 24 \| col << 16 \| keycode) |
| `learn=` | 1 | log every key change with row/column |
| `hiz=` | 1 | float idle columns while scanning |
| `poll_ms=` | 20 | scan interval |
| `col_delay_us=` | 5 | settle time after driving a column |

Do not load it while the built-in keypad driver is bound to the same pins (kernels with the keypad node in `e72.dts` and patch 0003); both would scan the matrix.

The same workflow applies to any driver: copy its source next to a two-line `Makefile` (`obj-m := name.o`), build with `M=`, copy, `insmod`.
