# SPDX-License-Identifier: MIT
import sys,struct,bisect; sys.path.insert(0,'.')
from ram import *
CO=0x480000; CL=0x3bb000; V=0xc6300000
code=M[CO:CO+CL]
calls={}  # target -> [sites]
for i in range(0,CL-4,2):
    h,l=struct.unpack_from('<HH',code,i)
    if h&0xf800==0xf000 and l&0xf800==0xf800:
        off=((h&0x7ff)<<12)|((l&0x7ff)<<1)
        if off&0x400000: off-=0x800000
        calls.setdefault(i+4+off,[]).append(i)
starts=sorted(t for t in calls if 0<=t<CL and code[t+1]&0xfe==0xb4 or (0<=t<CL))
def fstart(site):
    i=bisect.bisect_right(starts,site)-1
    return starts[i]
loops={0x16:0xc6307525,0x17:0xc634b98b,0x28:0xc6394c0d,0x18:0xc631db89,0x1a:0xc63cf959,0x1b:0xc63cf9b1,0x1c:0xc632aae1,0x1d:0xc635364b,0x1e:0xc6327339,0x23:0xc635fdb1,0x21:0xc63605f1,0x2c:0xc6360b11,0x2d:0xc6360aff,0x27:0xc635457b,0x2a:0xc6355221,0x26:0xc63553d9,0x1f:0xc634f85d,0x24:0xc63bd9db,0x25:0xc63be291,0x2e:0xc63bdb05,0x29:0xc63b9f3f,0x22:0xc63ce435,0x20:0xc63eff6d,0x19:0xc63d1199,0x2b:0xc63d6195}
tgt=int(sys.argv[1],16)-V
seen={tgt}; frontier=[tgt]; depth=0
while frontier and depth<8:
    nf=[]
    for f in frontier:
        for s in calls.get(f,[]):
            fs=fstart(s)
            print('  '*depth+'%x called at %x (fn ~%x)'%(f+V,s+V,fs+V))
            for t,ra in loops.items():
                if 0<=ra-V-s<8: print('   *** task %x loop'%t)
            if fs not in seen: seen.add(fs); nf.append(fs)
    frontier=nf; depth+=1
print('loop fns:')
for t,ra in sorted(loops.items()):
    print(' task %x ra %x fn ~%x %s'%(t,ra,fstart(ra-V-2)+V,'<== in chain' if fstart(ra-V-2) in seen else ''))
