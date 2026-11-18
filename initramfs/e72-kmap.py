#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Nokia E72 console keymap -> busybox loadkmap binary (e72.kmap).

Keycodes are the ones in linux,keymap of e72.dts. Layers (kernel keymap
modifier bits): shift 1, altgr 2 (= Fn), ctrl 4, alt 8, ctrlr 128 (= second
symbol layer on the right softkey). All modifiers are one-shot ("sticky"):
press and release the modifier, then the key; holding works too.

  Fn  + R T Y / F G H / V B N / M   1 2 3 / 4 5 6 / 7 8 9 / 0  (as printed)
  Fn  + U J                         * #                        (as printed)
  Fn  + arrows                      Home End PgUp PgDn
  Fn  + backspace                   Delete
  left softkey  Esc      call key  Tab     end key  Delete
  right softkey second symbol layer (brackets, slash, pipe ...)
  menu key      Alt (one-shot)

The symbols outside the digit block are a choice for a terminal, they are not
what is printed on the E72.
usage: e72-kmap.py <out.kmap>
"""
import struct
import sys

NR_KEYS, MAX_MAPS = 128, 256
SHIFT, FN, CTRL, ALT, SYM2 = 1, 2, 4, 8, 128
HOLE = 0x200

ROWS = {  # keycode -> letter
    16: 'q', 17: 'w', 18: 'e', 19: 'r', 20: 't', 21: 'y', 22: 'u', 23: 'i',
    24: 'o', 25: 'p', 30: 'a', 31: 's', 32: 'd', 33: 'f', 34: 'g', 35: 'h',
    36: 'j', 37: 'k', 38: 'l', 44: 'z', 45: 'x', 46: 'c', 47: 'v', 48: 'b',
    49: 'n', 50: 'm',
}
PUNCT = {39: (';', ':'), 40: ("'", '"'), 51: (',', '<'), 52: ('.', '>'), 57: (' ', ' ')}
FN_L = {
    'q': '!', 'w': '@', 'e': '|', 'r': '1', 't': '2', 'y': '3', 'u': '*',
    'i': '+', 'o': '=', 'p': '-', 'a': '~', 's': '$', 'd': '%', 'f': '4',
    'g': '5', 'h': '6', 'j': '#', 'k': '(', 'l': ')', 'z': '<', 'x': '>',
    'c': '&', 'v': '7', 'b': '8', 'n': '9', 'm': '0',
}
FN_P = {39: '\\', 40: '@', 51: '/', 52: '?', 57: '\t'}
SYM2_L = {
    'q': '`', 'w': '^', 'e': '_', 'r': '[', 't': ']', 'y': '{', 'u': '}',
    'i': '_', 'o': '\\', 'p': '/', 'a': '"', 's': "'", 'd': ':', 'f': ';',
    'g': '?', 'h': '!', 'j': '=', 'k': '+', 'l': '-', 'z': '<', 'x': '>',
    'c': '|', 'v': '&', 'b': '%', 'n': '$', 'm': '#',
}
SYM2_P = {39: '|', 40: '`', 51: '[', 52: ']', 57: ' '}
FIXED = {
    42: 0xc00,    # shift: one-shot
    100: 0xc01,   # fn left  (KEY_RIGHTALT): one-shot AltGr = Fn layer
    97: 0xc01,    # fn right (KEY_RIGHTCTRL)
    29: 0xc02,    # ctrl: one-shot
    56: 0xc03,    # menu key (KEY_LEFTALT): one-shot Alt
    125: 0xc07,   # right softkey (KEY_LEFTMETA): one-shot second symbol layer
    1: 0x01b,     # left softkey: Esc
    15: 0x009,    # call key: Tab
    107: 0x116,   # end key: Delete
    28: 0x201,    # enter (key and navi centre)
    14: 0x07f,    # backspace
    103: 0x603, 108: 0x600, 105: 0x601, 106: 0x602,   # up down left right
    59: 0x100, 60: 0x101, 61: 0x102, 62: 0x103, 63: 0x104, 64: 0x105,
    65: 0x106, 66: 0x107,                              # one-touch keys: F1..F8
}
FN_FIXED = {103: 0x118, 108: 0x119, 105: 0x114, 106: 0x117, 14: 0x116}


def value(kc, m):
    if m & FN and kc in FN_FIXED:
        return FN_FIXED[kc]
    if kc in FIXED:
        return FIXED[kc]
    if kc in ROWS:
        c = ROWS[kc]
        if m & FN:
            return ord(FN_L[c])
        if m & SYM2:
            return ord(SYM2_L[c])
        if m & CTRL:
            return ord(c) & 0x1f
        if m & ALT:
            return 0x800 | ord(c.upper() if m & SHIFT else c)
        return 0xb00 | ord(c.upper() if m & SHIFT else c)
    if kc in PUNCT:
        if m & FN:
            return ord(FN_P[kc])
        if m & SYM2:
            return ord(SYM2_P[kc])
        if m & CTRL and kc == 57:
            return 0
        c = PUNCT[kc][1 if m & SHIFT else 0]
        return (0x800 | ord(c)) if m & ALT else ord(c)
    return HOLE


maps = [0, SHIFT, FN, FN | SHIFT, CTRL, CTRL | SHIFT, ALT, ALT | SHIFT,
        SYM2, SYM2 | SHIFT, CTRL | ALT]
out = b'bkeymap' + bytes(1 if i in maps else 0 for i in range(MAX_MAPS))
for m in sorted(maps):
    out += struct.pack('<%dH' % NR_KEYS, *[value(k, m) for k in range(NR_KEYS)])
open(sys.argv[1], 'wb').write(out)
print(len(out), 'bytes,', len(maps), 'maps')
