#!/usr/bin/env python3
# RapuYama pad function mux (E72 fw 091.004, static analysis, see NOTES.md):
#   word(pin) = 0x20031810 + (pin >> 3) * 0x10   read: current value
#   +0x4 write bits -> set, +0x8 write bits -> clear (no read-modify-write needed)
#   field = 4 bits per pin at (pin & 7) * 4, function in the low 3 bits
# Evidence: ISASW c6308004 (GenOut104 -> 1, GenIO78/79 -> 2), c637e2d2 (pin 98 -> 1),
# c637e284 (pin 51 -> 0), c63efc8c (pins 29/30 -> 1), Symbian campdd.pdd 0x801b6a74 (pin 86/87 -> 1),
# Linux videocore.c vc_pads_init (0x200318e0.. pins 106..126 -> 4).
# usage: padmux.py PIN...                 -> address / field of each pin
#        padmux.py dump FILE              -> decode "addr value" lines (busybox devmem output pairs)
import sys
def where(p): return 0x20031810 + (p >> 3) * 0x10, (p & 7) * 4
if len(sys.argv) > 2 and sys.argv[1] == 'dump':
    for l in open(sys.argv[2]):
        a, v = (int(x, 16) for x in l.split()[:2])
        base = (a - 0x20031810) // 0x10 * 8
        print('%08x %08x  ' % (a, v) + ' '.join('%d:%d' % (base + i, (v >> (4 * i)) & 7) for i in range(8)))
else:
    for s in sys.argv[1:]:
        p = int(s, 0); a, sh = where(p)
        print('pin %3d: word %08x bits %d..%d  set %08x clr %08x' % (p, a, sh, sh + 2, a + 4, a + 8))
