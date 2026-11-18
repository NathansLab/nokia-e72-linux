#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""After linux_session.py: ask for uptime and secure-watchdog messages every 30 s until
the device disappears or maxmin minutes have passed.

Usage: session_watch.py <output file> [maxmin, default 12]
Serial port: $E72_TTY, default the first /dev/cu.usbmodem* (macOS). Needs pyserial."""
import glob, os, serial, sys, time

out = sys.argv[1]; maxmin = float(sys.argv[2]) if len(sys.argv) > 2 else 12
f = open(out, 'a'); t0 = time.time()

def one(cmd):
    p = [os.environ['E72_TTY']] if os.environ.get('E72_TTY') else glob.glob('/dev/cu.usbmodem*')
    if not p or not os.path.exists(p[0]): return None
    try:
        s = serial.Serial(p[0], 115200, timeout=0.3)
        s.write(b'\r'); time.sleep(0.3); s.read(8192)
        s.write(cmd.encode() + b'\r'); end = time.time() + 1.5; b = b''
        while time.time() < end:
            d = s.read(8192)
            if d: b += d; end = time.time() + 0.6
        s.close(); return b.decode(errors='replace')
    except Exception:
        return None

while time.time() - t0 < maxmin * 60:
    r = one("uptime; dmesg | grep -iE 'swd' | tail -3")
    f.write('### watch +%.0fs\n%s\n' % (time.time() - t0, r)); f.flush()
    if r is None:
        f.write('### DEVICE GONE after %.0fs\n' % (time.time() - t0)); break
    time.sleep(30)
else:
    f.write('### STILL RUNNING after %.0f min\n' % maxmin)
f.close(); print(open(out).read()[-3000:])
