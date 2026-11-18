# SPDX-License-Identifier: MIT
import struct, sys, mmap, os
# RAM image from e72dump (file offset = phys - 0x10000000), path in $E72RAM
F=open(os.environ.get('E72RAM','e72ram.bin'),'rb')
M=mmap.mmap(F.fileno(),0,access=mmap.ACCESS_READ)
BASE=0x10000000; SIZE=len(M)
L1=0x10000000
def p32(pa):
    o=pa-BASE
    if o<0 or o+4>SIZE: return None
    return struct.unpack_from('<I',M,o)[0]
def va2pa(va):
    d=p32(L1+(va>>20)*4)
    if d is None: return None
    if d&3==2 and not d&(1<<18): return (d&0xfff00000)|(va&0xfffff)
    if d&3!=1: return None
    e=p32((d&~0x3ff)+((va>>12)&0xff)*4)
    if e is None: return None
    if e&2: return (e&0xfffff000)|(va&0xfff)
    if e&1: return (e&0xffff0000)|(va&0xffff)
    return None
def v32(va):
    pa=va2pa(va)
    return None if pa is None else p32(pa)
def vbytes(va,n):
    out=b''
    while n>0:
        pa=va2pa(va); k=min(n,0x1000-(va&0xfff))
        if pa is None or pa-BASE<0 or pa-BASE+k>SIZE: out+=b'\0'*k
        else: out+=M[pa-BASE:pa-BASE+k]
        va+=k;n-=k
    return out
