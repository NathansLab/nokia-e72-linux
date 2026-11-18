# 5. USB shell

With the cable plugged in before the boot, the host sees a **"CDC Composite Gadget"** (USB vendor ID 0x0525) with a serial port (CDC ACM) and a network interface (CDC ECM).

| Host | Serial port |
| --- | --- |
| macOS | `/dev/cu.usbmodem*` |
| Linux | `/dev/ttyACM0` |

```sh
picocom -b 115200 /dev/ttyACM0      # Linux
screen /dev/cu.usbmodem* 115200     # macOS
```

Press Enter once to get the prompt `e6:/#` (the prompt name comes from the upstream E6 init).

## Scripted sessions

For unattended tests the host tools drive the shell (Python 3 + pyserial). They use the first `/dev/cu.usbmodem*`; set `E72_TTY=/dev/ttyACM0` on Linux.

```sh
# start before LinuxE72; waits for the gadget, runs the commands, saves the output
tools/linux_session.py logs/session.txt tools/sessions/watchdog.cmds
# then poll uptime and watchdog messages every 30 s for up to 20 min
tools/session_watch.py logs/session.txt 20
```

`tools/sessions/display.cmds` and `watchdog.cmds` are the command lists used for the logs in `logs/`.

## Copying files to the phone

USB ethernet does not work yet (see below), so files go over the serial line, base64 encoded, at about 6 KB/s:

```sh
tools/put.py e72kp.ko /tmp/e72kp.ko     # prints "md5 ok" when the copy matches
```

## USB ethernet (not working)

`usb0` (CDC ECM) comes up with the fixed addresses from the device tree (phone `02:e7:20:00:00:02`, host `02:e7:20:00:00:01`). The phone sends, but receives only the first packet. Open issue.

## Useful commands on the phone

```sh
dmesg | grep -i swd                     # watchdog bridge calls
cat /proc/interrupts; free
zcat /proc/config.gz | grep KEXEC       # kernel config
devmem 0x20031900 32                    # read a register (/dev/mem is unrestricted)
```

`devmem` writes can hang or reset the phone. Read first.

Next: [6. Diagnostics](06-diagnostics.md)
