#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""E72: klog.bin (1 MB from phys 0x17000000, written by e72logs) -> ramcon header,
isah handoff block and the scatter trampoline's trace words.
Usage: check_trace.py klog.bin   (the log text itself: upstream tools/parse_klog.py)"""
import struct, sys
d = open(sys.argv[1], "rb").read()
print("ramcon 'E6LG' at:", [hex(i) for i in range(0, len(d) - 4, 4) if d[i:i+4] == b"E6LG"][:4] or "nowhere")
w = struct.unpack_from("<13I", d, 0xf1000)
print("isah  magic=%08x ver=%d ttbr0=%08x ttbr1=%08x" % (w[0], w[1], w[2], w[3]))
print("L2    id=%08x ctrl=%08x aux=%08x" % (w[10], w[11], w[12]))
t = struct.unpack_from("<3I", d, 0xff000)
print("trace [0]=%08x (0x11600000 = MMU off reached)" % t[0])
print("      [1]=%08x (0x12600000 = copy done, jumping into Linux)" % t[1])
print("      [2]=%08x (L2 base, 0 = L2 not touched)" % t[2])
s = struct.unpack_from("<3I", d, 0xf1000 + 13 * 4)
print("stage %08x (b007000N: 1 start, 2 page, 3 copied, 4 idmap, 5 IMB, 6 read test ok, 7 jump)" % s[0])
print("      tramp page=%08x  first word/old L1 entry=%08x" % (s[1], s[2]))
