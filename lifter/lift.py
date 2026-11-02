#!/usr/bin/env python3
"""Static recompiler: i386 Mach-O (HID rastertofargoHDP5000) -> portable C.

Every function of the original filter becomes a C function that operates on a
flat 32-bit guest address space (MEM) with guest registers/flags as globals.
Calls/returns map onto C calls/returns; the guest stack lives in MEM so the
original code's stack-relative addressing keeps working unchanged.

usage: lift.py <binary> <outdir>
"""
import os, struct, sys
from capstone import Cs, CS_ARCH_X86, CS_MODE_32, CS_OP_REG, CS_OP_IMM, CS_OP_MEM
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'emu'))
from macho import MachO

md = Cs(CS_ARCH_X86, CS_MODE_32); md.detail = True

TEXT_SECTS = ('__text', '__textcoal_nt', '__StaticInit')

class LiftError(Exception): pass

# ---------------------------------------------------------------- registers
R32 = {'eax': 'EAX', 'ebx': 'EBX', 'ecx': 'ECX', 'edx': 'EDX', 'esi': 'ESI', 'edi': 'EDI', 'ebp': 'EBP', 'esp': 'ESP'}
R16 = {'ax': 'EAX', 'bx': 'EBX', 'cx': 'ECX', 'dx': 'EDX', 'si': 'ESI', 'di': 'EDI', 'bp': 'EBP', 'sp': 'ESP'}
R8L = {'al': 'EAX', 'bl': 'EBX', 'cl': 'ECX', 'dl': 'EDX'}
R8H = {'ah': 'EAX', 'bh': 'EBX', 'ch': 'ECX', 'dh': 'EDX'}
MASK = {1: '0xffu', 2: '0xffffu', 4: '0xffffffffu'}

def reg_read(name):
    if name in R32: return R32[name]
    if name in R16: return f'({R16[name]} & 0xffffu)'
    if name in R8L: return f'({R8L[name]} & 0xffu)'
    if name in R8H: return f'(({R8H[name]} >> 8) & 0xffu)'
    raise LiftError(f'register {name}')

def reg_write(name, v):
    if name in R32: return f'{R32[name]} = (uint32_t)({v});'
    if name in R16: r = R16[name]; return f'{r} = ({r} & 0xffff0000u) | ((uint32_t)({v}) & 0xffffu);'
    if name in R8L: r = R8L[name]; return f'{r} = ({r} & 0xffffff00u) | ((uint32_t)({v}) & 0xffu);'
    if name in R8H: r = R8H[name]; return f'{r} = ({r} & 0xffff00ffu) | (((uint32_t)({v}) & 0xffu) << 8);'
    raise LiftError(f'register {name}')

def streg(reg):
    n = md.reg_name(reg)   # 'st(3)'
    return int(''.join(c for c in n if c.isdigit()) or 0)

def xmm(name):
    if name.startswith('xmm'): return f'XMM[{int(name[3:])}]'
    raise LiftError(f'xmm {name}')

# ---------------------------------------------------------------- lifter
class FuncLifter:
    def __init__(self, img, start, end, name, ctx):
        self.img, self.start, self.end, self.name, self.ctx = img, start, end, name, ctx
        self.insns = {}; self.targets = set(); self.tables = {}; self.picbase = {}

    def decode(self, addr):
        off = addr - self.img.base
        for i in md.disasm(self.img.mem[off:off + 16], addr, 1): return i
        return None

    def discover(self):
        work = [self.start]; picbase = None
        while work:
            a = work.pop()
            while self.start <= a < self.end and a not in self.insns:
                i = self.decode(a)
                if i is None: self.insns[a] = None; break
                self.insns[a] = i; nxt = a + i.size; m = i.mnemonic
                if m == 'call' and i.operands[0].type == CS_OP_IMM:
                    t = i.operands[0].imm & 0xffffffff
                    if t == self.ctx.thunk_bx: picbase = nxt; self.picbase['ebx'] = nxt
                    if t == self.ctx.thunk_cx: self.picbase['ecx'] = nxt
                if m == 'jmp':
                    op = i.operands[0]
                    if op.type == CS_OP_IMM:
                        t = op.imm & 0xffffffff
                        if self.start <= t < self.end: self.targets.add(t); work.append(t)
                    elif op.type == CS_OP_REG:
                        tbl = self.find_table(a)
                        if tbl:
                            self.tables[a] = tbl
                            for t in tbl: self.targets.add(t); work.append(t)
                    break
                if m.startswith('j') and m != 'jmp':
                    t = i.operands[0].imm & 0xffffffff
                    if self.start <= t < self.end: self.targets.add(t); work.append(t)
                if m in ('ret', 'hlt', 'ud2'): break
                a = nxt

    def find_table(self, jaddr):
        """Recognise gcc's PIC switch: cmp N / ja ; ... lea eax,[ebx+OFF] ; mov eax,[edx+eax] ; add eax,ebx ; jmp eax"""
        prev = sorted(k for k in self.insns if k < jaddr)[-12:]
        lea_off = bound = None; base_reg = None
        for k in reversed(prev):
            i = self.insns[k]
            if i is None: continue
            if lea_off is None and i.mnemonic == 'lea' and i.operands[1].mem.base and \
               md.reg_name(i.operands[1].mem.base) in ('ebx', 'ecx') and not i.operands[1].mem.index:
                lea_off = i.operands[1].mem.disp; base_reg = md.reg_name(i.operands[1].mem.base)
            if bound is None and i.mnemonic == 'cmp' and i.operands[1].type == CS_OP_IMM:
                bound = i.operands[1].imm
        if lea_off is None or bound is None or base_reg not in self.picbase or not (0 <= bound < 4096):
            return None
        pb = self.picbase[base_reg]; tab = (pb + lea_off) & 0xffffffff; out = []
        for k in range(bound + 1):
            e = struct.unpack_from('<i', self.img.mem, tab - self.img.base + 4 * k)[0]
            t = (pb + e) & 0xffffffff
            if not (self.start <= t < self.end): return None
            out.append(t)
        return out

    # ----- operand helpers
    def ea(self, op):
        m = op.mem
        if m.segment and md.reg_name(m.segment) in ('fs', 'gs'): raise LiftError('segment override')
        parts = []
        if m.base: parts.append(reg_read(md.reg_name(m.base)))
        if m.index:
            idx = reg_read(md.reg_name(m.index))
            parts.append(f'{idx}*{m.scale}u' if m.scale != 1 else idx)
        if m.disp or not parts: parts.append(f'0x{m.disp & 0xffffffff:x}u')
        return '(uint32_t)(' + ' + '.join(parts) + ')'

    def rd(self, op, size=None):
        size = size or op.size
        if op.type == CS_OP_REG: return reg_read(md.reg_name(op.reg))
        if op.type == CS_OP_IMM: return f'0x{op.imm & int(MASK[size][:-1], 16):x}u'
        if op.type == CS_OP_MEM: return f'RD{size * 8}({self.ea(op)})'
        raise LiftError('operand')

    def wr(self, op, v, size=None):
        size = size or op.size
        if op.type == CS_OP_REG: return reg_write(md.reg_name(op.reg), v)
        if op.type == CS_OP_MEM: return f'WR{size * 8}({self.ea(op)}, {v});'
        raise LiftError('write operand')

    def sx(self, v, size):
        return {1: f'(int32_t)(int8_t)({v})', 2: f'(int32_t)(int16_t)({v})', 4: f'(int32_t)({v})'}[size]

    def xop(self, op):
        """xmm register or memory as an lvalue-ish expression for reading (returns C expr of xmm_t)"""
        if op.type == CS_OP_REG: return xmm(md.reg_name(op.reg))
        return f'RDX({self.ea(op)})'

    COND = {'e': 'ZF', 'z': 'ZF', 'ne': '!ZF', 'nz': '!ZF', 'l': '(SF != OF)', 'nge': '(SF != OF)',
            'le': '(ZF || SF != OF)', 'ng': '(ZF || SF != OF)', 'g': '(!ZF && SF == OF)', 'nle': '(!ZF && SF == OF)',
            'ge': '(SF == OF)', 'nl': '(SF == OF)', 'b': 'CF', 'c': 'CF', 'nae': 'CF', 'be': '(CF || ZF)',
            'na': '(CF || ZF)', 'a': '(!CF && !ZF)', 'nbe': '(!CF && !ZF)', 'ae': '!CF', 'nb': '!CF', 'nc': '!CF',
            's': 'SF', 'ns': '!SF', 'p': 'PF', 'pe': 'PF', 'np': '!PF', 'po': '!PF', 'o': 'OF', 'no': '!OF'}

    def lift_insn(self, i):
        m = i.mnemonic; ops = i.operands; nxt = (i.address + i.size) & 0xffffffff
        o = lambda k: ops[k]
        sz = ops[0].size if ops else 4
        bits = sz * 8
        ctx = self.ctx
        if m in ('nop', 'cld') or m.startswith('nop'): return ''
        if m == 'mov':
            return self.wr(o(0), self.rd(o(1)))
        if m == 'movzx': return self.wr(o(0), self.rd(o(1)))
        if m == 'movsx': return self.wr(o(0), self.sx(self.rd(o(1)), o(1).size))
        if m == 'lea': return self.wr(o(0), self.ea(o(1)))
        if m in ('add', 'sub', 'cmp', 'adc', 'sbb'):
            a, b = self.rd(o(0)), self.rd(o(1), sz)
            if o(1).type == CS_OP_IMM: b = f'0x{o(1).imm & int(MASK[sz][:-1], 16):x}u'
            fn = {'add': 'ADD', 'sub': 'SUB', 'cmp': 'SUB', 'adc': 'ADC', 'sbb': 'SBB'}[m]
            s = f'{{ uint32_t _a = {a}, _b = {b}; uint32_t _r = {fn}{bits}(_a, _b);'
            if m != 'cmp': s += ' ' + self.wr(o(0), '_r')
            return s + ' }'
        if m in ('and', 'or', 'xor', 'test'):
            op = {'and': '&', 'or': '|', 'xor': '^', 'test': '&'}[m]
            b = self.rd(o(1), sz)
            s = f'{{ uint32_t _r = ({self.rd(o(0))} {op} {b}) & {MASK[sz]}; LOGIC{bits}(_r);'
            if m != 'test': s += ' ' + self.wr(o(0), '_r')
            return s + ' }'
        if m in ('inc', 'dec'):
            return f'{{ uint32_t _r = {m.upper()}{bits}({self.rd(o(0))}); {self.wr(o(0), "_r")} }}'
        if m == 'neg': return f'{{ uint32_t _r = NEG{bits}({self.rd(o(0))}); {self.wr(o(0), "_r")} }}'
        if m == 'not': return self.wr(o(0), f'~{self.rd(o(0))}')
        if m in ('shl', 'sal', 'shr', 'sar', 'rol', 'ror'):
            cnt = self.rd(o(1), 1) if len(ops) > 1 else '1u'
            fn = {'sal': 'SHL'}.get(m, m.upper())
            return f'{{ uint32_t _r = {fn}{bits}({self.rd(o(0))}, {cnt}); {self.wr(o(0), "_r")} }}'
        if m == 'imul':
            if len(ops) == 1:
                return f'IMUL1_{bits}({self.rd(o(0))});'
            src = self.rd(o(1)) if len(ops) == 2 else self.rd(o(1))
            mul = self.rd(o(0)) if len(ops) == 2 else f'0x{o(2).imm & 0xffffffff:x}u'
            return f'{{ uint32_t _r = IMUL{bits}({src}, {mul}); {self.wr(o(0), "_r")} }}'
        if m == 'mul': return f'MUL1_{bits}({self.rd(o(0))});'
        if m == 'idiv': return f'IDIV{bits}({self.rd(o(0))});'
        if m == 'div': return f'UDIV{bits}({self.rd(o(0))});'
        if m == 'cdq': return 'EDX = (EAX & 0x80000000u) ? 0xffffffffu : 0;'
        if m == 'cwde': return 'EAX = (uint32_t)(int32_t)(int16_t)(EAX & 0xffff);'
        if m == 'cbw': return reg_write('ax', '(uint32_t)(int32_t)(int8_t)(EAX & 0xff)')
        if m == 'push':
            v = self.rd(o(0)) if o(0).type != CS_OP_IMM else f'0x{o(0).imm & 0xffffffff:x}u'
            return f'{{ uint32_t _v = {v}; PUSH(_v); }}'
        if m == 'pop':
            return f'{{ uint32_t _v = POP(); {self.wr(o(0), "_v")} }}'
        if m == 'leave': return 'ESP = EBP; EBP = POP();'
        if m == 'ret':
            n = ops[0].imm if ops else 0
            return f'ESP += {4 + n}u; return;'
        if m == 'call':
            op = o(0)
            if op.type == CS_OP_IMM:
                t = op.imm & 0xffffffff
                if t == ctx.thunk_bx: return f'EBX = 0x{nxt:x}u;'
                if t == ctx.thunk_cx: return f'ECX = 0x{nxt:x}u;'
                return f'PUSH(0x{nxt:x}u); {ctx.call_expr(t)};'
            return f'{{ uint32_t _t = {self.rd(op, 4)}; PUSH(0x{nxt:x}u); call_addr(_t); }}'
        if m == 'jmp':
            op = o(0)
            if op.type == CS_OP_IMM:
                t = op.imm & 0xffffffff
                if self.start <= t < self.end: return f'goto L_{t:x};'
                return f'{ctx.call_expr(t)}; return;'
            v = self.rd(op, 4)
            tbl = self.tables.get(i.address)
            if tbl:
                cases = ' '.join(f'case 0x{t:x}u: goto L_{t:x};' for t in sorted(set(tbl)))
                return f'switch ({v}) {{ {cases} default: call_addr({v}); return; }}'
            return f'{{ uint32_t _t = {v}; call_addr(_t); return; }}'
        if m == 'jecxz':
            return f'if (ECX == 0) goto L_{o(0).imm & 0xffffffff:x};'
        if m.startswith('j'):
            cc = self.COND[m[1:]]; t = o(0).imm & 0xffffffff
            if not (self.start <= t < self.end): return f'if ({cc}) {{ {ctx.call_expr(t)}; return; }}'
            return f'if ({cc}) goto L_{t:x};'
        if m.startswith('set'):
            return self.wr(o(0), f'({self.COND[m[3:]]}) ? 1u : 0u')
        if m.startswith('cmov'):
            return f'if ({self.COND[m[4:]]}) {{ {self.wr(o(0), self.rd(o(1)))} }}'
        if m == 'xchg':
            return f'{{ uint32_t _a = {self.rd(o(0))}, _b = {self.rd(o(1))}; {self.wr(o(0), "_b")} {self.wr(o(1), "_a")} }}'
        # string instructions (capstone folds the prefix into the mnemonic)
        if m.startswith('rep'):
            pre, op = m.split(' ', 1) if ' ' in m else (m, '')
            n = {'b': 1, 'w': 2, 'd': 4}[op[-1]]
            if op.startswith('movs'): return f'STRMOVS({n}, 1);'
            if op.startswith('stos'): return f'STRSTOS({n}, 1);'
            if op == 'scasb' and pre == 'repne': return 'REPNE_SCASB();'
            if op == 'cmpsb' and pre == 'repe': return 'REPE_CMPSB();'
            raise LiftError(f'unsupported {m}')
        if m in ('movsb', 'movsw', 'movsd') and (not ops or ops[0].type == CS_OP_MEM and ops[1].type == CS_OP_MEM):
            n = {'movsb': 1, 'movsw': 2, 'movsd': 4}[m]
            rep = 'rep' in i.op_str or i.prefix[0] in (0xf3, 0xf2)
            return f'STRMOVS({n}, {1 if rep else 0});'
        if m in ('stosb', 'stosw', 'stosd'):
            n = {'stosb': 1, 'stosw': 2, 'stosd': 4}[m]
            rep = i.prefix[0] in (0xf3, 0xf2)
            return f'STRSTOS({n}, {1 if rep else 0});'
        if m == 'scasb' and i.prefix[0] == 0xf2: return 'REPNE_SCASB();'
        if m == 'lodsd': return 'EAX = RD32(ESI); ESI += 4;'
        # ---------------- SSE
        if m in ('movss', 'movsd'):
            w = 4 if m == 'movss' else 8; lane = 'u[0]' if w == 4 else 'q[0]'
            d, s = o(0), o(1)
            if d.type == CS_OP_REG and s.type == CS_OP_MEM:
                ld = f'RD32({self.ea(s)})' if w == 4 else f'RD64({self.ea(s)})'
                return f'{{ xmm_t _x = {{0}}; _x.{lane} = {ld}; {xmm(md.reg_name(d.reg))} = _x; }}'
            if d.type == CS_OP_REG and s.type == CS_OP_REG:
                return f'{xmm(md.reg_name(d.reg))}.{lane} = {xmm(md.reg_name(s.reg))}.{lane};'
            if d.type == CS_OP_MEM:
                st = 'WR32' if w == 4 else 'WR64'
                return f'{st}({self.ea(d)}, {xmm(md.reg_name(s.reg))}.{lane});'
        if m in ('movaps', 'movapd', 'movdqa', 'movups', 'movupd', 'movdqu'):
            d, s = o(0), o(1)
            if d.type == CS_OP_REG: return f'{xmm(md.reg_name(d.reg))} = {self.xop(s)};'
            return f'WRX({self.ea(d)}, {xmm(md.reg_name(s.reg))});'
        if m == 'movd':
            d, s = o(0), o(1)
            if d.type == CS_OP_REG and md.reg_name(d.reg).startswith('xmm'):
                return f'{{ xmm_t _x = {{0}}; _x.u[0] = {self.rd(s, 4)}; {xmm(md.reg_name(d.reg))} = _x; }}'
            return self.wr(d, f'{xmm(md.reg_name(s.reg))}.u[0]', 4)
        if m == 'movhpd':
            d, s = o(0), o(1)
            if d.type == CS_OP_REG: return f'{xmm(md.reg_name(d.reg))}.q[1] = RD64({self.ea(s)});'
            return f'WR64({self.ea(d)}, {xmm(md.reg_name(s.reg))}.q[1]);'
        SCAL = {'addss': '+', 'subss': '-', 'mulss': '*', 'divss': '/', 'addsd': '+', 'subsd': '-', 'mulsd': '*', 'divsd': '/'}
        if m in SCAL:
            d = xmm(md.reg_name(o(0).reg))
            if m.endswith('ss'):
                src = f'{xmm(md.reg_name(o(1).reg))}.f[0]' if o(1).type == CS_OP_REG else f'RDF32({self.ea(o(1))})'
                return f'{d}.f[0] = {d}.f[0] {SCAL[m]} {src};'
            src = f'{xmm(md.reg_name(o(1).reg))}.d[0]' if o(1).type == CS_OP_REG else f'RDF64({self.ea(o(1))})'
            return f'{d}.d[0] = {d}.d[0] {SCAL[m]} {src};'
        if m in ('maxss', 'minss', 'maxsd', 'minsd', 'sqrtss', 'sqrtsd'):
            d = xmm(md.reg_name(o(0).reg)); f = 'f' if m.endswith('ss') else 'd'
            src = (f'{xmm(md.reg_name(o(1).reg))}.{f}[0]' if o(1).type == CS_OP_REG
                   else (f'RDF32({self.ea(o(1))})' if f == 'f' else f'RDF64({self.ea(o(1))})'))
            if m.startswith('sqrt'): return f'{d}.{f}[0] = {"sqrtf" if f == "f" else "sqrt"}({src});'
            cmp = '>' if m.startswith('max') else '<'
            return f'{{ __typeof__({d}.{f}[0]) _s = {src}; {d}.{f}[0] = ({d}.{f}[0] {cmp} _s) ? {d}.{f}[0] : _s; }}'
        if m == 'cvtss2sd':
            src = f'{xmm(md.reg_name(o(1).reg))}.f[0]' if o(1).type == CS_OP_REG else f'RDF32({self.ea(o(1))})'
            return f'{xmm(md.reg_name(o(0).reg))}.d[0] = (double)({src});'
        if m == 'cvtsd2ss':
            src = f'{xmm(md.reg_name(o(1).reg))}.d[0]' if o(1).type == CS_OP_REG else f'RDF64({self.ea(o(1))})'
            return f'{xmm(md.reg_name(o(0).reg))}.f[0] = (float)({src});'
        if m == 'cvtsi2ss': return f'{xmm(md.reg_name(o(0).reg))}.f[0] = (float)(int32_t)({self.rd(o(1), 4)});'
        if m == 'cvtsi2sd': return f'{xmm(md.reg_name(o(0).reg))}.d[0] = (double)(int32_t)({self.rd(o(1), 4)});'
        if m in ('cvttss2si', 'cvttsd2si'):
            f = 'f' if m == 'cvttss2si' else 'd'
            src = (f'{xmm(md.reg_name(o(1).reg))}.{f}[0]' if o(1).type == CS_OP_REG
                   else (f'RDF32({self.ea(o(1))})' if f == 'f' else f'RDF64({self.ea(o(1))})'))
            return self.wr(o(0), f'CVTT((double)({src}))')
        if m == 'cvttps2dq':
            d, s = xmm(md.reg_name(o(0).reg)), self.xop(o(1))
            return f'{{ xmm_t _s = {s}; for (int _k = 0; _k < 4; _k++) {d}.u[_k] = CVTT((double)_s.f[_k]); }}'
        if m == 'cvttpd2dq':
            d, s = xmm(md.reg_name(o(0).reg)), self.xop(o(1))
            return f'{{ xmm_t _s = {s}; {d}.u[0] = CVTT(_s.d[0]); {d}.u[1] = CVTT(_s.d[1]); {d}.q[1] = 0; }}'
        if m in ('ucomiss', 'ucomisd', 'comiss', 'comisd'):
            f = 'f' if 'ss' in m else 'd'
            a = f'{xmm(md.reg_name(o(0).reg))}.{f}[0]'
            b = (f'{xmm(md.reg_name(o(1).reg))}.{f}[0]' if o(1).type == CS_OP_REG
                 else (f'RDF32({self.ea(o(1))})' if f == 'f' else f'RDF64({self.ea(o(1))})'))
            return f'UCOMI((double)({a}), (double)({b}));'
        if m in ('cmpless', 'cmplesd', 'cmpltss', 'cmpltsd', 'cmpeqss', 'cmpeqsd', 'cmpnless', 'cmpnltss'):
            f = 'f' if m.endswith('ss') else 'd'; rel = m[3:-2]
            op = {'le': '<=', 'lt': '<', 'eq': '==', 'nle': '<=', 'nlt': '<'}[rel]; neg = rel.startswith('n')
            d = xmm(md.reg_name(o(0).reg))
            b = (f'{xmm(md.reg_name(o(1).reg))}.{f}[0]' if o(1).type == CS_OP_REG
                 else (f'RDF32({self.ea(o(1))})' if f == 'f' else f'RDF64({self.ea(o(1))})'))
            res = f'({"!" if neg else ""}({d}.{f}[0] {op} {b}))'
            if f == 'f': return f'{d}.u[0] = {res} ? 0xffffffffu : 0u;'
            return f'{d}.q[0] = {res} ? ~0ull : 0ull;'
        if m in ('andps', 'andpd', 'pand', 'xorps', 'xorpd', 'pxor', 'orps', 'orpd', 'por', 'andnps', 'andnpd', 'pandn'):
            d, s = xmm(md.reg_name(o(0).reg)), self.xop(o(1))
            if 'andn' in m: return f'{{ xmm_t _s = {s}; {d}.q[0] = ~{d}.q[0] & _s.q[0]; {d}.q[1] = ~{d}.q[1] & _s.q[1]; }}'
            op = '&' if 'and' in m else ('^' if 'xor' in m else '|')
            return f'{{ xmm_t _s = {s}; {d}.q[0] {op}= _s.q[0]; {d}.q[1] {op}= _s.q[1]; }}'
        if m in ('addps', 'subps', 'mulps', 'divps'):
            op = {'add': '+', 'sub': '-', 'mul': '*', 'div': '/'}[m[:3]]
            d, s = xmm(md.reg_name(o(0).reg)), self.xop(o(1))
            return f'{{ xmm_t _s = {s}; for (int _k = 0; _k < 4; _k++) {d}.f[_k] = {d}.f[_k] {op} _s.f[_k]; }}'
        if m in ('addpd', 'subpd', 'mulpd', 'divpd'):
            op = {'add': '+', 'sub': '-', 'mul': '*', 'div': '/'}[m[:3]]
            d, s = xmm(md.reg_name(o(0).reg)), self.xop(o(1))
            return f'{{ xmm_t _s = {s}; {d}.d[0] = {d}.d[0] {op} _s.d[0]; {d}.d[1] = {d}.d[1] {op} _s.d[1]; }}'
        if m == 'paddd':
            d, s = xmm(md.reg_name(o(0).reg)), self.xop(o(1))
            return f'{{ xmm_t _s = {s}; for (int _k = 0; _k < 4; _k++) {d}.u[_k] += _s.u[_k]; }}'
        if m in ('pslld', 'psllq', 'psrld', 'psrlq'):
            d = xmm(md.reg_name(o(0).reg)); n = self.rd(o(1), 1) if o(1).type == CS_OP_IMM else f'{xmm(md.reg_name(o(1).reg))}.q[0]'
            if m.endswith('d'):
                sh = '<<' if 'sll' in m else '>>'
                return f'{{ uint64_t _n = {n}; for (int _k = 0; _k < 4; _k++) {d}.u[_k] = _n > 31 ? 0 : {d}.u[_k] {sh} _n; }}'
            sh = '<<' if 'sll' in m else '>>'
            return f'{{ uint64_t _n = {n}; for (int _k = 0; _k < 2; _k++) {d}.q[_k] = _n > 63 ? 0 : {d}.q[_k] {sh} _n; }}'
        if m == 'punpckldq':
            d, s = xmm(md.reg_name(o(0).reg)), self.xop(o(1))
            return f'{{ xmm_t _s = {s}, _d = {d}; {d}.u[0] = _d.u[0]; {d}.u[1] = _s.u[0]; {d}.u[2] = _d.u[1]; {d}.u[3] = _s.u[1]; }}'
        if m == 'unpcklps':
            d, s = xmm(md.reg_name(o(0).reg)), self.xop(o(1))
            return f'{{ xmm_t _s = {s}, _d = {d}; {d}.u[0] = _d.u[0]; {d}.u[1] = _s.u[0]; {d}.u[2] = _d.u[1]; {d}.u[3] = _s.u[1]; }}'
        # ---------------- x87 (only used for float/double returns and a few ops)
        if m == 'fld':
            s = o(0)
            if s.type == CS_OP_MEM:
                ld = f'(double)RDF32({self.ea(s)})' if s.size == 4 else (f'RDF64({self.ea(s)})' if s.size == 8 else None)
                if ld is None: raise LiftError('fld80')
                return f'FPUSH({ld});'
            return f'FPUSH(FST({streg(s.reg)}));'
        if m in ('fstp', 'fst'):
            d = o(0); pop = m == 'fstp'
            if d.type == CS_OP_MEM:
                st = f'WRF32({self.ea(d)}, (float)FST(0));' if d.size == 4 else f'WRF64({self.ea(d)}, FST(0));'
                return st + (' FPOP();' if pop else '')
            k = streg(d.reg)
            return f'FSTSET({k}, FST(0));' + (' FPOP();' if pop else '')
        if m in ('fadd', 'fsub', 'fmul', 'fdiv', 'fidiv', 'fiadd', 'fimul', 'fisub'):
            if len(ops) == 1 and ops[0].type == CS_OP_MEM:
                s = ops[0]
                if m.startswith('fi'): v = f'(double)(int32_t)RD32({self.ea(s)})' if s.size == 4 else f'(double)(int16_t)RD16({self.ea(s)})'
                else: v = f'(double)RDF32({self.ea(s)})' if s.size == 4 else f'RDF64({self.ea(s)})'
                op = {'add': '+', 'sub': '-', 'mul': '*', 'div': '/'}[m[-3:]]
                return f'FSTSET(0, FST(0) {op} {v});'
            raise LiftError(f'x87 form {m} {i.op_str}')
        if m == 'fxch':
            k = streg(o(0).reg) if ops else 1
            return f'{{ double _t = FST(0); FSTSET(0, FST({k})); FSTSET({k}, _t); }}'
        if m in ('hlt', 'ud2', 'int3'):
            return f'trap(0x{i.address:x}u, "{m}");'
        raise LiftError(f'unsupported {m} {i.op_str}')

    def emit(self):
        self.discover()
        lines = [f'/* {self.name} */', f'void f_{self.start:x}(void) {{']
        need_all = False
        for a in sorted(self.insns):
            i = self.insns[a]
            if a in self.targets: lines.append(f'L_{a:x}:;')
            if i is None:
                lines.append(f'  trap(0x{a:x}u, "undecodable");'); continue
            try:
                code = self.lift_insn(i)
            except LiftError as e:
                self.ctx.unsupported[str(e).split(' ')[0] + ' ' + (str(e).split(' ')[1] if len(str(e).split(' ')) > 1 else '')] += 1
                code = f'trap(0x{a:x}u, "unsupported: {i.mnemonic} {i.op_str}");'
            if code: lines.append(f'  {code}  /* {a:x}: {i.mnemonic} {i.op_str} */'.replace('*/ */', '*/'))
        lines.append(f'  trap(0x{self.end:x}u, "fell off end of {self.name}");')
        lines.append('}')
        return '\n'.join(lines)

# ---------------------------------------------------------------- image & driver
class Image:
    def __init__(self, m):
        self.base = 0x1000
        top = max(v + s for n, v, s, fo, fs in m.segments if n not in ('__PAGEZERO', '__LINKEDIT'))
        self.mem = bytearray(top - self.base)
        for n, vmaddr, vmsize, fileoff, filesize in m.segments:
            if n in ('__PAGEZERO', '__LINKEDIT'): continue
            self.mem[vmaddr - self.base: vmaddr - self.base + filesize] = m.data[fileoff:fileoff + filesize]

def cname(sym):
    return 'imp_' + ''.join(c if c.isalnum() else '_' for c in sym.lstrip('_'))

class Ctx:
    def __init__(self, m):
        import collections
        self.m = m; self.unsupported = collections.Counter()
        self.thunk_bx = m.name2addr['___i686.get_pc_thunk.bx']
        self.thunk_cx = m.name2addr['___i686.get_pc_thunk.cx']
        self.funcs = {}   # start -> (end, name)
        self.stubs = {}   # stub addr -> (kind, target)  kind: 'local' (f_addr) or 'import' (name)
        for a, n in m.stubs.items():
            self.stubs[a] = ('local', m.name2addr[n]) if n in m.name2addr else ('import', n)

    def call_expr(self, t):
        if t in self.funcs: return f'f_{t:x}()'
        if t in self.stubs:
            kind, v = self.stubs[t]
            return f'f_{v:x}()' if kind == 'local' else f'{cname(v)}()'
        return f'call_addr(0x{t:x}u)'

def main():
    binpath, outdir = sys.argv[1], sys.argv[2]
    os.makedirs(outdir, exist_ok=True)
    m = MachO(binpath); img = Image(m); ctx = Ctx(m)
    starts = {}
    for name, ntype, value in m.syms:
        if ntype & 0x0e == 0x0e and value: starts.setdefault(value, name)
    sects = [s for s in m.sections if s['sect'] in TEXT_SECTS and s['size']]
    for s in sects:
        inside = sorted(a for a in starts if s['addr'] <= a < s['addr'] + s['size'])
        for k, a in enumerate(inside):
            end = inside[k + 1] if k + 1 < len(inside) else s['addr'] + s['size']
            ctx.funcs[a] = (end, starts[a])
    print(f'{len(ctx.funcs)} functions, {len(ctx.stubs)} import stubs', file=sys.stderr)

    bodies = []
    for a in sorted(ctx.funcs):
        end, name = ctx.funcs[a]
        if a in (ctx.thunk_bx, ctx.thunk_cx): continue
        bodies.append(FuncLifter(img, a, end, name, ctx).emit())

    hdr = ['#include "rt.h"']
    hdr += [f'void f_{a:x}(void);' for a in sorted(ctx.funcs)]
    imports = sorted(set(v for k, v in ctx.stubs.values() if k == 'import'))
    hdr += [f'void {cname(n)}(void);' for n in imports]
    open(f'{outdir}/lifted.h', 'w').write('\n'.join(hdr) + '\n')

    chunks = 16; per = (len(bodies) + chunks - 1) // chunks
    for c in range(chunks):
        with open(f'{outdir}/lifted_{c:02d}.c', 'w') as f:
            f.write('/* Generated by lifter/lift.py from HID rastertofargoHDP5000 (i386). Do not edit. */\n')
            f.write('#include "lifted.h"\n\n')
            f.write('\n\n'.join(bodies[c * per:(c + 1) * per]) + '\n')

    # dispatcher + image data
    with open(f'{outdir}/lifted_dispatch.c', 'w') as f:
        f.write('#include "lifted.h"\n#include <stdio.h>\n#include <stdlib.h>\n\n')
        f.write('void call_addr(uint32_t a) {\n  switch (a) {\n')
        for a in sorted(ctx.funcs):
            if a == ctx.thunk_bx: f.write(f'  case 0x{a:x}u: EBX = RD32(ESP); ESP += 4; return;\n'); continue
            if a == ctx.thunk_cx: f.write(f'  case 0x{a:x}u: ECX = RD32(ESP); ESP += 4; return;\n'); continue
            f.write(f'  case 0x{a:x}u: f_{a:x}(); return;\n')
        for a, (kind, v) in sorted(ctx.stubs.items()):
            f.write(f'  case 0x{a:x}u: {"f_%x()" % v if kind == "local" else cname(v) + "()"}; return;\n')
        f.write('  default: fprintf(stderr, "call_addr: no function at 0x%x\\n", a); abort();\n  }\n}\n\n')
        f.write('const char *const import_names[] = {\n' + ''.join(f'  "{n}",\n' for n in imports) + '  0 };\n')
    with open(f'{outdir}/image_data.c', 'w') as f:
        f.write('#include <stdint.h>\n')
        f.write(f'const uint32_t IMAGE_BASE = 0x{img.base:x}u;\nconst uint32_t IMAGE_SIZE = {len(img.mem)}u;\n')
        f.write('const unsigned char IMAGE_DATA[] = {\n')
        data = bytes(img.mem)
        for k in range(0, len(data), 32):
            f.write(','.join(str(b) for b in data[k:k + 32]) + ',\n')
        f.write('};\n')
        ptrs = sorted(m.pointers.items())
        f.write('const uint32_t NL_PTR_ADDR[] = {' + ','.join(f'0x{a:x}u' for a, n in ptrs) + '};\n')
        f.write('const char *const NL_PTR_NAME[] = {' + ','.join(f'"{n}"' for a, n in ptrs) + '};\n')
        f.write(f'const int NL_PTR_COUNT = {len(ptrs)};\n')
        f.write('const uint32_t NL_PTR_LOCAL[] = {' + ','.join(f'0x{m.name2addr.get(n, 0):x}u' for a, n in ptrs) + '};\n')
        inits = []
        for s in m.sections:
            if s['sect'] in ('__mod_init_func', '__constructor') and s['size']:
                inits += struct.unpack_from(f'<{s["size"] // 4}I', m.data, s['off'])
        f.write('const uint32_t INIT_FUNCS[] = {' + ','.join(f'0x{a:x}u' for a in inits) + ', 0};\n')
        f.write(f'const uint32_t MAIN_ADDR = 0x{m.name2addr["_main"]:x}u;\n')
    if ctx.unsupported:
        print('unsupported instruction forms:', file=sys.stderr)
        for k, v in ctx.unsupported.most_common(): print(f'  {v:5d} {k}', file=sys.stderr)

if __name__ == '__main__':
    main()
