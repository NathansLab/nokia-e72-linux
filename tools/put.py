#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Copy a file to the E72 over the USB serial shell (base64 over the tty) and check its md5.

Usage: put.py <local file> <target path on the phone>
Serial port: $E72_TTY, default the first /dev/cu.usbmodem* (macOS); on Linux e.g. E72_TTY=/dev/ttyACM0.
About 6 KB/s. Needs pyserial."""
import base64, glob, hashlib, os, serial, sys, time

def port():
    return os.environ.get('E72_TTY') or glob.glob('/dev/cu.usbmodem*')[0]

src, dst = sys.argv[1], sys.argv[2]
data = open(src, 'rb').read()
s = serial.Serial(port(), 115200, timeout=0.5)

def rd(t=1.0):
    end = time.time() + t; out = b''
    while time.time() < end:
        d = s.read(65536)
        if d: out += d; end = time.time() + 0.4
    return out.decode(errors='replace')

s.write(b'\r'); rd()
s.write(b'stty -echo; base64 -d > %s.b64tmp <<"__EOF__"\r' % dst.encode()); time.sleep(0.3)
t0 = time.time()
b = base64.encodebytes(data).replace(b'\n', b'\r')
for i in range(0, len(b), 4096):
    s.write(b[i:i + 4096]); s.flush()
s.write(b'__EOF__\r'); rd(2)
s.write(b'stty echo; mv %s.b64tmp %s; md5sum %s\r' % (dst.encode(), dst.encode(), dst.encode()))
r = rd(8)
ok = hashlib.md5(data).hexdigest() in r
print('%d bytes in %.1f s, md5 %s' % (len(data), time.time() - t0, 'ok' if ok else 'MISMATCH: ' + r[-200:]))
sys.exit(0 if ok else 1)
