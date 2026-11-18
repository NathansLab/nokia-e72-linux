#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Send a file to the E72 over WLAN. On the phone first: nc -l -p 9000 > target
Usage: wput.py <file> <ip> [port]"""
import socket, sys, time
d = open(sys.argv[1], 'rb').read(); t = time.time()
s = socket.create_connection((sys.argv[2], int(sys.argv[3]) if len(sys.argv) > 3 else 9000), timeout=10)
s.settimeout(120); s.sendall(d); s.shutdown(socket.SHUT_WR)
while s.recv(4096): pass
print('%d bytes in %.1f s, %.0f kB/s' % (len(d), time.time() - t, len(d) / 1024 / (time.time() - t)))
