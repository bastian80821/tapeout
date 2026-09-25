#!/usr/bin/env python3
"""Assemble a small RV32E self-test using only x0..x15, and emit hex."""
prog=[]; labels={}; fixups=[]

def R(f7,rs2,rs1,f3,rd,op): return (f7<<25)|(rs2<<20)|(rs1<<15)|(f3<<12)|(rd<<7)|op
def I(imm,rs1,f3,rd,op):    return ((imm&0xfff)<<20)|(rs1<<15)|(f3<<12)|(rd<<7)|op
def S(imm,rs2,rs1,f3,op):
    return (((imm>>5)&0x7f)<<25)|(rs2<<20)|(rs1<<15)|(f3<<12)|((imm&0x1f)<<7)|op
def B(imm,rs2,rs1,f3,op):
    return (((imm>>12)&1)<<31)|(((imm>>5)&0x3f)<<25)|(rs2<<20)|(rs1<<15)|(f3<<12)|\
           (((imm>>1)&0xf)<<8)|(((imm>>11)&1)<<7)|op
def U(imm,rd,op): return ((imm&0xfffff)<<12)|(rd<<7)|op
def J(imm,rd,op):
    return (((imm>>20)&1)<<31)|(((imm>>1)&0x3ff)<<21)|(((imm>>11)&1)<<20)|\
           (((imm>>12)&0xff)<<12)|(rd<<7)|op

def emit(w): prog.append(w)
def label(n): labels[n]=len(prog)*4
def br(f3,rs1,rs2,tgt):
    fixups.append((len(prog),'B',tgt,f3,rs1,rs2)); prog.append(0)
def jal(rd,tgt):
    fixups.append((len(prog),'J',tgt,0,rd,0)); prog.append(0)

# --- register budget: x0..x15 only (RV32E) ---
emit(I(5,0,0,1,0x13))          # addi x1,x0,5
emit(I(3,0,0,2,0x13))          # addi x2,x0,3
emit(R(0x00,2,1,0,3,0x33))     # add  x3,x1,x2      = 8
emit(I(8,0,0,4,0x13))
br(1,3,4,'fail')               # bne x3,x4 -> fail
emit(R(0x20,2,1,0,5,0x33))     # sub  x5,x1,x2      = 2
emit(I(2,0,0,6,0x13))
br(1,5,6,'fail')
emit(R(0x00,2,1,4,7,0x33))     # xor  x7,x1,x2      = 6
emit(I(6,0,0,8,0x13))
br(1,7,8,'fail')
emit(R(0x00,2,1,6,9,0x33))     # or   x9,x1,x2      = 7
emit(I(7,0,0,10,0x13))
br(1,9,10,'fail')
emit(R(0x00,2,1,7,11,0x33))    # and  x11,x1,x2     = 1
br(1,11,1,'nope')              # 1 != 5 so this branch IS taken -> skip fail
label('nope')
emit(I(2,1,1,12,0x13))         # slli x12,x1,2      = 20
emit(I(20,0,0,13,0x13))
br(1,12,13,'fail')
emit(I(2,12,5,14,0x13))        # srli x14,x12,2     = 5
br(1,14,1,'fail')
emit(I(0x800|2,12,5,15,0x13))  # srai x15,x12,2     = 5
br(1,15,1,'fail')
emit(R(0x00,2,1,2,3,0x33))     # slt  x3,x1,x2      = 0 (5<3 false)
br(1,3,0,'fail')
emit(R(0x00,1,2,3,3,0x33))     # sltu x3,x2,x1      = 1 (3<5 true)
emit(I(1,0,0,4,0x13))
br(1,3,4,'fail')
# memory: word, halfword, byte  (base x6 = 0x200)
emit(I(0x200,0,0,6,0x13))      # addi x6,x0,0x200
emit(U(0xABCDE,7,0x37))        # lui  x7,0xABCDE
emit(I(0x123,7,0,7,0x13))      # addi x7,x7,0x123
emit(S(0,7,6,2,0x23))          # sw   x7,0(x6)
emit(I(0,6,2,8,0x03))          # lw   x8,0(x6)
br(1,7,8,'fail')
emit(I(0x5A,0,0,9,0x13))       # addi x9,x0,0x5A
emit(S(4,9,6,0,0x23))          # sb   x9,4(x6)
emit(I(4,6,4,10,0x03))         # lbu  x10,4(x6)
br(1,9,10,'fail')
emit(I(4,6,0,11,0x03))         # lb   x11,4(x6)     (0x5A positive)
br(1,9,11,'fail')
emit(I(0x7F0,0,0,12,0x13))     # addi x12,x0,0x7F0
emit(S(8,12,6,1,0x23))         # sh   x12,8(x6)
emit(I(8,6,5,13,0x03))         # lhu  x13,8(x6)
br(1,12,13,'fail')
# jal / jalr
jal(1,'sub1')
br(0,0,0,'after')              # beq x0,x0 -> after
label('sub1')
emit(I(0,1,0,0,0x67))          # jalr x0,0(x1)  return
label('after')
# auipc
emit(U(0,14,0x17))             # auipc x14,0  -> x14 = pc
# PASS: store 'P' to UART 0x1000
emit(I(0x50,0,0,5,0x13))       # addi x5,x0,'P'
emit(U(1,6,0x37))              # lui  x6,0x1  -> x6 = 0x1000
emit(S(0,5,6,0,0x23))          # sb   x5,0(x6)
label('halt')
br(0,0,0,'halt')               # beq x0,x0,halt
label('fail')
emit(I(0x46,0,0,5,0x13))       # 'F'
emit(U(1,6,0x37))              # lui x6,0x1
emit(S(0,5,6,0,0x23))
emit(I(0x30,0,0,5,0x13))       # '0'
emit(S(0,5,6,0,0x23))
emit(S(0,5,6,0,0x23))
label('fhalt')
br(0,0,0,'fhalt')

for idx,kind,tgt,f3,a,b in fixups:
    off = labels[tgt] - idx*4
    prog[idx] = B(off,b,a,f3,0x63) if kind=='B' else J(off,a,0x6f)

with open('rv32e_test.hex','w') as f:
    for w in prog: f.write(f"{w & 0xFFFFFFFF:08x}\n")
print(f"assembled {len(prog)} instructions -> rv32e_test.hex")

# confirm the RV32E constraint
mx=0
for w in prog:
    op=w&0x7f
    for fld in ((w>>7)&0x1f,(w>>15)&0x1f,(w>>20)&0x1f):
        pass
    if op in (0x33,): mx=max(mx,(w>>7)&0x1f,(w>>15)&0x1f,(w>>20)&0x1f)
    elif op in (0x13,0x03,0x67): mx=max(mx,(w>>7)&0x1f,(w>>15)&0x1f)
    elif op in (0x23,0x63): mx=max(mx,(w>>15)&0x1f,(w>>20)&0x1f)
    elif op in (0x37,0x17,0x6f): mx=max(mx,(w>>7)&0x1f)
print(f"highest register used: x{mx}  ({'RV32E-safe' if mx<16 else 'TOO HIGH'})")
