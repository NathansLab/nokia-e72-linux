# SPDX-License-Identifier: MIT
import sys,struct; sys.path.insert(0,'.')
from ram import *
from unicorn import *
from unicorn.arm_const import *
SP=int(sys.argv[1],16) if len(sys.argv)>1 else 0xc68e9e6c
ALLOC,FREE,PET=0xc636eb73,0xc636ea6d,0xc636fa1f
uc=Uc(UC_ARCH_ARM,UC_MODE_ARM)
try: uc.ctl_set_cpu_model(UC_CPU_ARM_1176)
except Exception as e: print('cpu model',e)
pages={}   # va page -> (pa, kinds)
order=[]
MAGIC=0x00100000
uc.mem_map(MAGIC,0x1000); uc.mem_write(MAGIC,b'\xfe\xff\xff\xea'*16)
def mapin(va,kind):
    pg=va&~0xfff
    if pg in pages: return True
    pa=va2pa(pg)
    if pa is None:
        print('UNMAPPED va %08x (%s) pc %08x'%(va,kind,uc.reg_read(UC_ARM_REG_PC))); return False
    uc.mem_map(pg,0x1000)
    if BASE<=pa<BASE+SIZE: uc.mem_write(pg,M[pa-BASE:pa-BASE+0x1000])
    pages[pg]=[pa,set()]; order.append(pg)
    return True
def unm(uc,acc,addr,size,val,ud):
    kind={UC_MEM_READ_UNMAPPED:'r',UC_MEM_WRITE_UNMAPPED:'w',UC_MEM_FETCH_UNMAPPED:'x'}.get(acc,'?')
    ok=mapin(addr,kind)
    if ok and (addr&0xfff)+size>0x1000: ok=mapin(addr+size-1,kind)
    return ok
uc.hook_add(UC_HOOK_MEM_UNMAPPED,unm)
mmio=[]
def acc(uc,a,addr,size,val,ud):
    pg=addr&~0xfff
    if pg in pages:
        k='w' if a==UC_MEM_WRITE else 'r'
        pages[pg][1].add(k)
        if pages[pg][0]>=0x18000000 or pages[pg][0]<0x10000000:
            mmio.append((k,pages[pg][0]|(addr&0xfff),val if k=='w' else None,uc.reg_read(UC_ARM_REG_PC)))
uc.hook_add(UC_HOOK_MEM_READ|UC_HOOK_MEM_WRITE,acc)
def blk(uc,addr,size,ud):
    pg=addr&~0xfff
    if pg in pages: pages[pg][1].add('x')
uc.hook_add(UC_HOOK_BLOCK,blk)
smcs=[]
def intr(uc,no,ud):
    pc=uc.reg_read(UC_ARM_REG_PC)
    r=[uc.reg_read(UC_ARM_REG_R0+i) for i in range(8)]
    print('INTR',no,'pc %08x'%pc,' '.join('%08x'%x for x in r),'sp %08x lr %08x cpsr %08x'%(uc.reg_read(UC_ARM_REG_SP),uc.reg_read(UC_ARM_REG_LR),uc.reg_read(UC_ARM_REG_CPSR)))
    smcs.append((pc,r))
    ud['n']+=1
    if ud['n']>20: uc.emu_stop()
ctx={'n':0}
uc.hook_add(UC_HOOK_INTR,intr,ctx)
def call(fn,*args,limit=2000000):
    for i,a in enumerate(args): uc.reg_write(UC_ARM_REG_R0+i,a)
    uc.reg_write(UC_ARM_REG_LR,MAGIC)
    cpsr=0xd3|(0x20 if fn&1 else 0)
    uc.reg_write(UC_ARM_REG_CPSR,cpsr)
    uc.reg_write(UC_ARM_REG_SP,SP)
    try:
        uc.emu_start(fn,MAGIC,count=limit)
    except UcError as e:
        print('ERR',e,'pc %08x'%uc.reg_read(UC_ARM_REG_PC))
    pc=uc.reg_read(UC_ARM_REG_PC)
    if pc!=MAGIC: print('stopped at pc %08x lr %08x sp %08x'%(pc,uc.reg_read(UC_ARM_REG_LR),uc.reg_read(UC_ARM_REG_SP)))
    return uc.reg_read(UC_ARM_REG_R0)
minsp=[SP]
def code(uc,addr,size,ud):
    s=uc.reg_read(UC_ARM_REG_SP)
    if 0xc6800000<=s<minsp[0]: minsp[0]=s
uc.hook_add(UC_HOOK_CODE,code)
req=call(ALLOC,8); print('req %08x'%req)
resp=call(ALLOC,8); print('resp %08x'%resp)
tok=struct.unpack('<H',vbytes(0xc6831554,2))[0]
uc.mem_write(req+4,struct.pack('<H',tok))
n0=len(order)
r=call(PET,req,resp); print('pet -> %08x'%r, 'resp', bytes(uc.mem_read(resp,8)).hex(),'req',bytes(uc.mem_read(req,8)).hex())
call(FREE,resp); call(FREE,req)
print('stack low %08x used %x'%(minsp[0],SP-minsp[0]))
for pg in sorted(pages):
    pa,k=pages[pg]
    where='below-kernel' if pa<0x11600000 else ('LINUX-RAM' if pa<0x17000000 else ('top' if pa<0x18000000 else 'MMIO'))
    print('%08x -> %08x %-3s %s'%(pg,pa,''.join(sorted(k)),where))
print('MMIO:')
for k,pa,v,pc in mmio[:80]: print(' ',k,'%08x'%pa,'' if v is None else '%08x'%(v&0xffffffff),'pc %08x'%pc)
