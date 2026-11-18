# SPDX-License-Identifier: MIT
import os
src=open('emu.py').read()
pre,post=src.split("req=call(ALLOC,8)")
exec(pre)
ZERO=os.environ.get('ZERO')=='1'
RET=int(os.environ.get('RET','0'),0)
rom=[]
def romblk(uc,addr,size,ud):
    if 0xc6071000<=addr<0xc6080000:
        r=[uc.reg_read(UC_ARM_REG_R0+i) for i in range(4)]
        lr=uc.reg_read(UC_ARM_REG_LR); sp=uc.reg_read(UC_ARM_REG_SP)
        st=struct.unpack('<6I',bytes(uc.mem_read(sp,24)))
        rom.append((addr,r,lr))
        print('ROM entry %08x r0-3 %s lr %08x sp %08x stack %s'%(addr,' '.join('%08x'%x for x in r),lr,sp,' '.join('%08x'%x for x in st)))
        # fake response: stack[1] is resp phys? write into resp va
        uc.mem_write(RESP[0],struct.pack('<IHH',1,240,240))
        uc.reg_write(UC_ARM_REG_R0,RET)
uc.hook_add(UC_HOOK_BLOCK,romblk)
RESP=[0]
mapin(0xc6071000,'x'); uc.mem_write(0xc6071000,b'\x70\x47'*0x800)
if ZERO:
    mapin(0xc8001b1c,'r'); uc.mem_write(0xc8001b1c,b'\0'*256)
req=call(ALLOC,8); resp=call(ALLOC,8); RESP[0]=resp
uc.mem_write(req+4,struct.pack('<H',240))
r=call(PET,req,resp); print('pet -> %08x'%r,'resp',bytes(uc.mem_read(resp,8)).hex())
call(FREE,resp); call(FREE,req)
print('stack low %08x used %x'%(minsp[0],SP-minsp[0]))
for pg in sorted(pages):
    pa,k=pages[pg]
    if 0x11600000<=pa<0x17000000 or os.environ.get('ALL'): print('%08x -> %08x %s'%(pg,pa,''.join(sorted(k))))
print('npages',len(pages)); print('MMIO:')
for k,pa,v,pc in mmio[:80]: print(' ',k,'%08x'%pa,'' if v is None else '%08x'%(v&0xffffffff),'pc %08x'%pc)
