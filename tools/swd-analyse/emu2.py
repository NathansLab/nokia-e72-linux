# SPDX-License-Identifier: MIT
exec(open('emu.py').read().split("req=call(ALLOC,8)")[0])
log=[]
def acc2(uc,a,addr,size,val,ud):
    pg=addr&~0xfff
    if pg in pages and (0x11600000<=pages[pg][0]<0x17000000 or pg in(0xc0030000,0xc1003000,0xc2002000,0xc2004000,0xfc201000,0xfc22a000,0xcb294000,0xc8000000,0xc8001000,0xc8011000)):
        v=struct.unpack('<I',bytes(uc.mem_read(addr&~3,4)))[0]
        log.append('%s %08x = %08x pc %08x lr %08x'%('w' if a==UC_MEM_WRITE else 'r',addr,v,uc.reg_read(UC_ARM_REG_PC),uc.reg_read(UC_ARM_REG_LR)))
uc.hook_add(UC_HOOK_MEM_READ|UC_HOOK_MEM_WRITE,acc2)
req=call(ALLOC,8); resp=call(ALLOC,8)
uc.mem_write(req+4,struct.pack('<H',240))
call(PET,req,resp)
print('\n'.join(log))
