# SPDX-License-Identifier: MIT
import sys,struct; sys.path.insert(0,'.')
from ram import *
CO=0x480000; CL=0x3bb000
code=M[CO:CO+CL]
def cands(sig):
    b=struct.pack('<I',sig); i=0; s=set()
    while True:
        i=code.find(b,i)
        if i<0: break
        if i%2==0: s.add(i)
        i+=2
    return s
A=cands(0x4605b570);Fr=cands(0x4606b5f8);P=cands(0x4605b5fe)
# all thumb BLs
calls={}
for i in range(0,CL-4,2):
    h,l=struct.unpack_from('<HH',code,i)
    if h&0xf800==0xf000 and l&0xf800==0xf800:
        off=((h&0x7ff)<<12)|((l&0x7ff)<<1)
        if off&0x400000: off-=0x800000
        t=i+4+off
        calls.setdefault(t,[]).append(i)
for p in sorted(P):
    for c in calls.get(p,[]):
        # look in window around caller for alloc and free calls
        near=[ (t,s) for t,ss in calls.items() for s in ss if abs(s-c)<0x100 and (t in A or t in Fr)]
        a=[(hex(t),hex(s)) for t,s in near if t in A]; f=[(hex(t),hex(s)) for t,s in near if t in Fr]
        if a and f: print('pet',hex(p),'caller',hex(c),'alloc',a,'free',f)
