#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Cut the WL1251 firmware and this phone's NVS out of an E72 RAM dump (e72dump).

Usage: extract_fw_nvs.py e72ram.bin [--l2 0x13193000] [--out DIR]

On fw 091.004 a Symbian user process keeps both files as a heap copy in the
chunk at VA 0x00600000 (56 pages): firmware at chunk offset 0x42f8 (200460
bytes, CRC32 0x38a5a30d), NVS at offset 0x584 (729 bytes). The physical pages
of that chunk are listed in an L2 page table whose address changes with every
Symbian boot. Without --l2 the script tries every page-table candidate in the
dump and keeps the one whose firmware CRC matches.

The output files are Nokia/TI property and the NVS contains your phone's WLAN
MAC address: keep them local, never commit or publish them.
"""
import argparse, mmap, os, struct, zlib

BASE = 0x10000000
FW_OFF, FW_LEN, FW_CRC = 0x42f8, 200460, 0x38a5a30d
NVS_OFF, NVS_LEN = 0x584, 729
PAGES = 56

ap = argparse.ArgumentParser()
ap.add_argument('dump')
ap.add_argument('--l2', type=lambda s: int(s, 0), help='phys address of the chunk\'s L2 table')
ap.add_argument('--out', default='.')
a = ap.parse_args()
f = open(a.dump, 'rb'); M = mmap.mmap(f.fileno(), 0, access=mmap.ACCESS_READ); SIZE = len(M)

def chunk(l2):
    if l2 < BASE or l2 - BASE + 4 * PAGES > SIZE:
        return None
    out = []
    for j in range(PAGES):
        e = struct.unpack_from('<I', M, l2 - BASE + 4 * j)[0]
        if not e & 2:                      # small page descriptor expected
            return None
        pa = e & 0xfffff000
        if pa < BASE or pa - BASE + 0x1000 > SIZE:
            return None
        out.append(M[pa - BASE:pa - BASE + 0x1000])
    return b''.join(out)

def ok(buf):
    return buf is not None and zlib.crc32(buf[FW_OFF:FW_OFF + FW_LEN]) == FW_CRC

if a.l2 is not None:
    found = a.l2 if ok(chunk(a.l2)) else None
else:
    found = None
    # L2 tables are 1 KB aligned; the chunk's L2 is pointed to by an L1 entry
    # (index 6 = VA 0x00600000) of the owning process
    for off in range(0x18, SIZE - 4, 0x4000):
        d = struct.unpack_from('<I', M, off)[0]
        if d & 3 != 1:
            continue
        l2 = d & ~0x3ff
        if ok(chunk(l2)):
            found = l2
            break
if found is None:
    raise SystemExit('firmware not found (different firmware version or layout?)')
buf = chunk(found)
os.makedirs(os.path.join(a.out, 'ti-connectivity'), exist_ok=True)
open(os.path.join(a.out, 'ti-connectivity/wl1251-fw.bin'), 'wb').write(buf[FW_OFF:FW_OFF + FW_LEN])
open(os.path.join(a.out, 'ti-connectivity/wl1251-nvs.bin'), 'wb').write(buf[NVS_OFF:NVS_OFF + NVS_LEN] + b'\0' * 3)
print('L2 table at %#x, firmware CRC ok, files in %s/ti-connectivity/' % (found, a.out))
