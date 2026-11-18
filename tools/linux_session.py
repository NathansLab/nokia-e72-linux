#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Wait for the E72's Linux USB gadget, run a list of commands in its shell and save everything.

Usage: linux_session.py <output file> <command file>   (one command per line, '#' = comment)
Start it before booting Linux; it waits up to 4 h for the serial port.
Serial port: $E72_TTY, default the first /dev/cu.usbmodem* (macOS). On macOS it also
waits until ioreg lists the gadget (USB vendor 0x0525 = 1317). Needs pyserial."""
import glob, os, serial, shutil, subprocess, sys, time

out = sys.argv[1]
cmds = [l.rstrip('\n') for l in open(sys.argv[2]) if l.strip() and not l.startswith('#')]

def ports():
    p = os.environ.get('E72_TTY')
    return ([p] if p and os.path.exists(p) else []) if p else glob.glob('/dev/cu.usbmodem*')

def gadget():
    if not shutil.which('ioreg'):
        return True
    r = subprocess.run(['ioreg', '-p', 'IOUSB', '-l', '-w0'], capture_output=True, text=True).stdout
    return '"idVendor" = 1317' in r

deadline = time.time() + 4 * 3600
while not (gadget() and ports()):
    if time.time() > deadline: sys.exit('TIMEOUT')
    time.sleep(1)
time.sleep(1.5)
probe = serial.Serial(ports()[0], 115200, timeout=0.5)
for _ in range(60):
    probe.write(b"\r"); time.sleep(0.7)
    if b"# " in probe.read(4096): break
probe.close()
s = serial.Serial(ports()[0], 115200, timeout=0.3)
f = open(out, 'w')

def rd(quiet=0.8, maxt=25):
    end = time.time() + quiet; stop = time.time() + maxt; b = b''
    while time.time() < end and time.time() < stop:
        d = s.read(8192)
        if d: b += d; end = time.time() + quiet
    return b.decode(errors='replace')

t0 = time.time()
try:
    s.write(b'\r'); rd(1.5)
    for c in cmds:
        s.write(c.encode() + b'\r')
        r = rd()
        f.write('### [%5.1fs] %s\n%s\n' % (time.time() - t0, c, r)); f.flush()
    f.write('### done after %.1fs\n' % (time.time() - t0))
except Exception as e:
    f.write('\n### ABORTED after %.1fs: %r\n' % (time.time() - t0, e))
f.close(); print(open(out).read()[-6000:])
