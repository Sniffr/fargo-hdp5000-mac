#!/usr/bin/env python3
"""Run the original 2009 i386 `rastertofargoHDP5000` CUPS filter under Unicorn.

Purpose: produce byte-exact reference output from HID's own code so the new
native driver can be verified against it. Only the ~100 libc/libcups/libstdc++
imports are reimplemented here (in Python); every instruction of the Fargo
code itself runs unmodified.

usage: run_original.py <input.rgb|.ppm> <out.prn> [cups options...]
   input is a binary PPM (P6), any size; it is fed to the filter as an 8-bit
   RGB CUPS raster page at 300 dpi. Several PPMs separated by ',' = several pages.
"""
import math, os, struct, sys, time
from unicorn import *
from unicorn.x86_const import *
sys.path.insert(0, os.path.dirname(__file__))
from macho import MachO

ROOT = os.path.expanduser('~/hdp/original/payload')
BIN = f'{ROOT}/usr/lib/cups/filter/rastertofargoHDP5000'
PPD = f'{ROOT}/usr/share/cups/model/HDP5000.ppd'
TRACE = os.environ.get('EMU_TRACE')

HEAP, HEAP_SIZE = 0x10000000, 0x30000000
STACK, STACK_SIZE = 0x7e000000, 0x01000000
MISC = 0x60000000            # FILE structs, trampolines, fake objects
PAGE = 0x1000

class Exit(Exception):
    def __init__(self, code): self.code = code

class Emu:
    def __init__(self, pages, options, out_path):
        self.m = m = MachO(BIN)
        self.uc = uc = Uc(UC_ARCH_X86, UC_MODE_32)
        for name, vmaddr, vmsize, fileoff, filesize in m.segments:
            if name in ('__PAGEZERO', '__LINKEDIT') or not vmsize: continue
            uc.mem_map(vmaddr, (vmsize + PAGE - 1) & ~(PAGE - 1))
            uc.mem_write(vmaddr, m.data[fileoff:fileoff + filesize])
        uc.mem_map(HEAP, HEAP_SIZE); self.brk = HEAP; self.sizes = {}
        uc.mem_map(STACK, STACK_SIZE)
        uc.mem_map(MISC, 0x100000); self.misc = MISC + 0x1000
        # trampoline: fldl (MISC) ; ret   -- used to return doubles in st(0)
        uc.mem_write(MISC, bytes.fromhex('dd 05') + struct.pack('<I', MISC + 0x800) + b'\xc3')
        self.fld_tramp = MISC
        self.out = open(out_path, 'wb')
        self.files = {}      # FILE* -> python file-like
        self.fds = {}
        sF = self.alloc_misc(88 * 3)
        self.files[sF] = None; self.files[sF + 88] = self.out; self.files[sF + 176] = sys.stderr.buffer
        self.stdout_file = sF + 88
        self.errno_addr = self.alloc_misc(4)
        self.empty_rep = self.alloc_misc(64)
        data_syms = {'___sF': sF, '_errno': self.errno_addr,
                     '__ZNSs4_Rep20_S_empty_rep_storageE': self.empty_rep,
                     '__ZNSs4_Rep11_S_terminalE': self.empty_rep + 12}
        for addr, name in m.pointers.items():
            v = m.name2addr.get(name) or data_syms.get(name) or 0
            uc.mem_write(addr, struct.pack('<I', v))
        # import stubs: local definitions get a direct jmp, others a python hook
        self.hooks = {}
        for addr, name in m.stubs.items():
            if name in m.name2addr:
                rel = (m.name2addr[name] - (addr + 5)) & 0xffffffff
                uc.mem_write(addr, b'\xe9' + struct.pack('<I', rel))
            else:
                fn = getattr(self, 'f' + name.lstrip('_'), None) or getattr(self, CXX.get(name, '-'), None)
                self.hooks[addr] = (name, fn)
        lo, hi = min(m.stubs), max(m.stubs) + 5
        uc.hook_add(UC_HOOK_CODE, self.on_stub, begin=lo, end=hi)
        uc.hook_add(UC_HOOK_MEM_INVALID, self.on_bad)
        self.pages = pages; self.page_i = -1; self.row = 0
        self.options = options
        self.rand_state = 1

    # ---------------- memory helpers ----------------
    def alloc_misc(self, n):
        a = self.misc; self.misc += (n + 15) & ~15; return a
    def malloc(self, n):
        n = max(int(n), 1); a = self.brk; self.brk += (n + 31) & ~15
        if self.brk > HEAP + HEAP_SIZE: raise MemoryError('emulated heap exhausted')
        self.sizes[a] = n; return a
    def r32(self, a): return struct.unpack('<I', self.uc.mem_read(a, 4))[0]
    def w32(self, a, v): self.uc.mem_write(a, struct.pack('<I', v & 0xffffffff))
    def cstr(self, a, maxlen=1 << 20):
        if not a: return None
        out = bytearray()
        while True:
            chunk = bytes(self.uc.mem_read(a + len(out), 64))
            z = chunk.find(b'\0')
            if z >= 0: out += chunk[:z]; return bytes(out)
            out += chunk
            if len(out) > maxlen: return bytes(out)
    def wstr(self, a):
        out = []
        while True:
            c = self.r32(a + 4 * len(out))
            if not c: return ''.join(out)
            out.append(chr(c))
    def put_cstr(self, a, b): self.uc.mem_write(a, b + b'\0')
    def put_wstr(self, a, s): self.uc.mem_write(a, b''.join(struct.pack('<I', ord(c)) for c in s) + b'\0' * 4)
    def arg(self, i): return self.r32(self.uc.reg_read(UC_X86_REG_ESP) + 4 + 4 * i)
    def argd(self, i):
        return struct.unpack('<d', self.uc.mem_read(self.uc.reg_read(UC_X86_REG_ESP) + 4 + 4 * i, 8))[0]

    # ---------------- dispatch ----------------
    def on_stub(self, uc, addr, size, _):
        name, fn = self.hooks.get(addr, (None, None))
        if name is None: return
        if fn is None:
            raise NotImplementedError(f'import {name} not implemented (called from {self.r32(uc.reg_read(UC_X86_REG_ESP)):#x})')
        ret = fn()
        if TRACE: print(f'  {name} -> {ret!r}', file=sys.stderr)
        esp = uc.reg_read(UC_X86_REG_ESP); ra = self.r32(esp)
        uc.reg_write(UC_X86_REG_ESP, esp + 4)
        if isinstance(ret, float):          # return in st(0) via trampoline
            uc.mem_write(MISC + 0x800, struct.pack('<d', ret))
            uc.reg_write(UC_X86_REG_ESP, esp)  # trampoline's ret pops ra
            uc.reg_write(UC_X86_REG_EIP, self.fld_tramp)
            return
        if ret is not None:
            uc.reg_write(UC_X86_REG_EAX, ret & 0xffffffff)
            if ret > 0xffffffff or ret < 0: uc.reg_write(UC_X86_REG_EDX, (ret >> 32) & 0xffffffff)
        uc.reg_write(UC_X86_REG_EIP, ra)

    def on_bad(self, uc, access, addr, size, value, _):
        eip = uc.reg_read(UC_X86_REG_EIP)
        print(f'invalid memory access {access} at {addr:#x} (eip={eip:#x} {self.m.addr2sym.get(eip, "")})', file=sys.stderr)
        return False

    def run(self, argv):
        uc = self.uc
        # static initializers (__mod_init_func / __constructor)
        inits = []
        for s in self.m.sections:
            if s['sect'] in ('__mod_init_func', '__constructor') and s['size']:
                inits += struct.unpack_from(f'<{s["size"] // 4}I', self.m.data, s['off'])
        for f in inits: self.call(f, [])
        # argv
        ptrs = []
        for a in argv:
            p = self.alloc_misc(len(a) + 1); self.put_cstr(p, a.encode()); ptrs.append(p)
        av = self.alloc_misc(4 * (len(ptrs) + 1))
        for i, p in enumerate(ptrs + [0]): self.w32(av + 4 * i, p)
        envp = self.alloc_misc(4); self.w32(envp, 0)
        try:
            rc = self.call(self.m.name2addr['_main'], [len(argv), av, envp])
        except Exit as e:
            rc = e.code
        self.out.close(); return rc

    def call(self, fn, args):
        uc = self.uc
        esp = uc.reg_read(UC_X86_REG_ESP) or STACK + STACK_SIZE - 0x1000
        esp = (esp - 4 * len(args) - 64) & ~15
        for i, a in enumerate(args): self.w32(esp + 4 + 4 * i, a)
        stop = self.alloc_misc(16); uc.mem_write(stop, b'\xf4')   # hlt sentinel
        self.w32(esp, stop)
        uc.reg_write(UC_X86_REG_ESP, esp)
        try:
            uc.emu_start(fn, stop)
        except UcError as e:
            if isinstance(getattr(self, '_exit', None), Exit): raise self._exit
            eip = uc.reg_read(UC_X86_REG_EIP)
            near = max((a for a in self.m.addr2sym if a <= eip), default=0)
            raise RuntimeError(f'{e} at eip={eip:#x} ({self.m.addr2sym.get(near)}+{eip - near:#x})')
        if getattr(self, '_exit', None): raise self._exit
        return uc.reg_read(UC_X86_REG_EAX)

    # ---------------- printf engine ----------------
    def fmt(self, f, argp, wide=False):
        """Format C printf string f (str) consuming args from memory at argp."""
        out = []; i = 0
        def nxt():
            nonlocal argp; v = self.r32(argp); argp += 4; return v
        while i < len(f):
            c = f[i]
            if c != '%': out.append(c); i += 1; continue
            j = i + 1; flags = ''
            while j < len(f) and f[j] in '-+ #0': flags += f[j]; j += 1
            width = ''
            if j < len(f) and f[j] == '*': width = str(nxt()); j += 1
            while j < len(f) and f[j].isdigit(): width += f[j]; j += 1
            prec = None
            if j < len(f) and f[j] == '.':
                j += 1; prec = ''
                if f[j] == '*': prec = str(nxt()); j += 1
                while j < len(f) and f[j].isdigit(): prec += f[j]; j += 1
            lmod = ''
            while j < len(f) and f[j] in 'hlLqjzt': lmod += f[j]; j += 1
            conv = f[j]; j += 1
            spec = '%' + flags + width + ('.' + prec if prec is not None else '')
            if conv == '%': out.append('%')
            elif conv in 'di':
                v = nxt()
                if lmod in ('ll', 'q'): v |= nxt() << 32; v -= (1 << 64) if v >> 63 else 0
                else: v -= (1 << 32) if v >> 31 else 0
                out.append((spec + 'd') % v)
            elif conv in 'uxXo':
                v = nxt()
                if lmod in ('ll', 'q'): v |= nxt() << 32
                out.append((spec + conv) % v)
            elif conv == 'c': out.append((spec + 'c') % chr(nxt() & (0xffffffff if wide else 0xff)))
            elif conv in 'sS':
                p = nxt()
                if (conv == 'S' or lmod == 'l') or (wide and lmod != 'h' and conv == 's'):
                    s = self.wstr(p) if p else '(null)'
                else:
                    s = self.cstr(p).decode('latin-1') if p else '(null)'
                out.append((spec + 's') % s)
            elif conv in 'feEgG':
                v = struct.unpack('<d', struct.pack('<II', nxt(), nxt()))[0]
                out.append((spec + conv) % v)
            elif conv == 'p': out.append('0x%x' % nxt())
            elif conv == 'n': pass
            else: out.append(f[i:j])
            i = j
        return ''.join(out), argp

    def cfmt(self, fp, argp): return self.fmt(self.cstr(fp).decode('latin-1'), argp)[0].encode('latin-1')

    # ---------------- libc ----------------
    def fmalloc(self): return self.malloc(self.arg(0))
    def fcalloc(self):
        n = self.arg(0) * self.arg(1); a = self.malloc(n); self.uc.mem_write(a, b'\0' * n); return a
    def frealloc(self):
        old, n = self.arg(0), self.arg(1); a = self.malloc(n)
        if old: self.uc.mem_write(a, bytes(self.uc.mem_read(old, min(self.sizes.get(old, n), n))))
        return a
    def ffree(self): return 0
    fZnwm = fZnam = fmalloc
    fZdlPv = fZdaPv = ffree
    def fmemcpy(self):
        d, s, n = self.arg(0), self.arg(1), self.arg(2)
        if n: self.uc.mem_write(d, bytes(self.uc.mem_read(s, n)))
        return d
    def fmemset(self):
        d, c, n = self.arg(0), self.arg(1), self.arg(2)
        if n: self.uc.mem_write(d, bytes([c & 0xff]) * n)
        return d
    def fstrcpy(self): self.put_cstr(self.arg(0), self.cstr(self.arg(1))); return self.arg(0)
    def fstrncpy(self):
        d, s, n = self.arg(0), self.cstr(self.arg(1)), self.arg(2)
        self.uc.mem_write(d, (s[:n] + b'\0' * n)[:n]); return d
    def fstrcat(self):
        d = self.arg(0); self.put_cstr(d, self.cstr(d) + self.cstr(self.arg(1))); return d
    @staticmethod
    def _cmp(a, b): return (a > b) - (a < b)
    def fstrcmp(self): return self._cmp(self.cstr(self.arg(0)), self.cstr(self.arg(1)))
    def fstrncmp(self):
        n = self.arg(2); return self._cmp(self.cstr(self.arg(0))[:n], self.cstr(self.arg(1))[:n])
    def fstrcasecmp(self): return self._cmp(self.cstr(self.arg(0)).lower(), self.cstr(self.arg(1)).lower())
    def fstrstr(self):
        h, n = self.cstr(self.arg(0)), self.cstr(self.arg(1)); k = h.find(n)
        return self.arg(0) + k if k >= 0 else 0
    def fstrerror(self):
        p = self.alloc_misc(32); self.put_cstr(p, b'error'); return p
    def fatoi(self):
        s = self.cstr(self.arg(0)).strip(); k = 0
        while k < len(s) and (s[k:k+1].isdigit() or (k == 0 and s[k:k+1] in b'+-')): k += 1
        try: return int(s[:k])
        except ValueError: return 0
    def _strtol(self, signed):
        p, endp, base = self.arg(0), self.arg(1), self.arg(2)
        s = self.cstr(p); t = s.lstrip(); k = len(s) - len(t); j = 0
        neg = t[:1] == b'-'
        if t[:1] in b'+-': j = 1
        if base in (0, 16) and t[j:j+2].lower() == b'0x': j += 2; base = 16
        if base == 0: base = 8 if t[j:j+1] == b'0' else 10
        v = 0; st = j
        while j < len(t):
            ch = t[j:j+1].lower()
            d = int(ch, 36) if ch.isalnum() else 99
            if d >= base: break
            v = v * base + d; j += 1
        if endp: self.w32(endp, p + (k + j if j > st else 0))
        return -v if neg else v
    def fstrtol(self): return self._strtol(True)
    def fstrtoul(self): return self._strtol(False)
    def ftolower(self): c = self.arg(0); return c + 32 if 65 <= c <= 90 else c
    def fisprint(self): return int(32 <= self.arg(0) < 127)
    def fisxdigit(self): return int(chr(self.arg(0) & 0xff) in '0123456789abcdefABCDEF')
    def fgetenv(self):
        name = self.cstr(self.arg(0)).decode()
        val = {'CUPS_SERVERROOT': '/etc/cups', 'CUPS_DATADIR': '/usr/share/cups'}.get(name)
        if name == 'PPD': val = PPD
        if val is None: return 0
        p = self.alloc_misc(len(val) + 1); self.put_cstr(p, val.encode()); return p
    def ferror(self): return self.errno_addr
    def fsprintf(self):
        s = self.cfmt(self.arg(1), self.uc.reg_read(UC_X86_REG_ESP) + 12); self.put_cstr(self.arg(0), s); return len(s)
    def fvsprintf(self):
        s = self.cfmt(self.arg(1), self.arg(2)); self.put_cstr(self.arg(0), s); return len(s)
    def fswprintf(self):
        f = self.wstr(self.arg(2)); s, _ = self.fmt(f, self.uc.reg_read(UC_X86_REG_ESP) + 16, wide=True)
        s = s[:self.arg(1) - 1]; self.put_wstr(self.arg(0), s); return len(s)
    def fmbstowcs(self):
        s = self.cstr(self.arg(1)).decode('latin-1')[:self.arg(2)]
        if self.arg(0): self.put_wstr(self.arg(0), s)
        return len(s)
    def fmbtowc(self):
        p = self.arg(1)
        if not p: return 0
        c = self.uc.mem_read(p, 1)[0]
        if self.arg(0): self.w32(self.arg(0), c)
        return 1 if c else 0
    def fwcslen(self): return len(self.wstr(self.arg(0)))
    def fwcscpy(self): self.put_wstr(self.arg(0), self.wstr(self.arg(1))); return self.arg(0)
    def fwcsncpy(self):
        s = self.wstr(self.arg(1))[:self.arg(2)]; d = self.arg(0); n = self.arg(2)
        self.uc.mem_write(d, b''.join(struct.pack('<I', ord(c)) for c in s) + b'\0' * 4 * (n - len(s))); return d
    def fwcscat(self): d = self.arg(0); self.put_wstr(d, self.wstr(d) + self.wstr(self.arg(1))); return d
    def fwcsncat(self): d = self.arg(0); self.put_wstr(d, self.wstr(d) + self.wstr(self.arg(1))[:self.arg(2)]); return d
    def fwcscmp(self): return self._cmp(self.wstr(self.arg(0)), self.wstr(self.arg(1)))
    def fwcsrchr(self):
        s = self.wstr(self.arg(0)); k = s.rfind(chr(self.arg(1))); return self.arg(0) + 4 * k if k >= 0 else 0
    def fsrand(self): self.rand_state = self.arg(0); return 0
    def frand(self):   # deterministic LCG so runs are reproducible
        self.rand_state = (self.rand_state * 1103515245 + 12345) & 0x7fffffff; return self.rand_state
    def ftime(self):
        if self.arg(0): self.w32(self.arg(0), 1255000000)
        return 1255000000
    def fctime(self):
        p = self.alloc_misc(32); self.put_cstr(p, b'Thu Oct  8 12:00:00 2009\n'); return p
    def _tm(self):
        p = self.alloc_misc(48)
        self.uc.mem_write(p, struct.pack('<9i', 0, 0, 12, 8, 9, 109, 4, 280, 0)); return p
    fgmtime = flocaltime = _tm
    def fsleep(self): return 0
    def fsigset(self): return 0
    def fexit(self):
        self._exit = Exit(self.arg(0)); self.uc.emu_stop(); return 0
    def faccess(self):
        p = self.cstr(self.arg(0)).decode(); return 0 if os.path.exists(self._path(p)) else -1
    def fdlopen(self): return 0
    def fdlsym(self): return 0
    def fpow(self): return math.pow(self.argd(0), self.argd(2))
    def fsin(self): return math.sin(self.argd(0))
    def fcos(self): return math.cos(self.argd(0))
    def fatan2(self): return math.atan2(self.argd(0), self.argd(2))
    def flog10(self):
        x = self.argd(0); return math.log10(x) if x > 0 else -math.inf

    # files -------------------------------------------------------------
    def _path(self, p):
        if p.startswith('/usr/share/') or p.startswith('/usr/lib/'): return ROOT + p
        if p.endswith('HDP5000.ppd'): return PPD
        return p
    def new_file(self, obj):
        a = self.alloc_misc(88); self.files[a] = obj; return a
    def ffopen(self):
        p = self._path(self.cstr(self.arg(0)).decode()); mode = self.cstr(self.arg(1)).decode()
        if 'w' in mode or 'a' in mode:
            if p.startswith('/var/log') or p.startswith('/tmp'):
                return self.new_file(open(os.devnull, 'wb'))
        try: return self.new_file(open(p, mode.replace('t', '') + ('b' if 'b' not in mode else '')))
        except OSError: return 0
    def ftmpfile(self):
        import tempfile; return self.new_file(tempfile.TemporaryFile())
    def ffclose(self):
        f = self.files.pop(self.arg(0), None)
        if f not in (None, self.out, sys.stderr.buffer): f.close()
        return 0
    def ffflush(self):
        f = self.files.get(self.arg(0))
        if f: f.flush()
        return 0
    def ffileno(self): return 100 + (self.arg(0) & 0xffff)
    def ffchmod(self): return 0
    def ffwrite(self):
        p, sz, n, fp = self.arg(0), self.arg(1), self.arg(2), self.arg(3)
        self.files[fp].write(bytes(self.uc.mem_read(p, sz * n))) if sz * n else None; return n
    def ffread(self):
        p, sz, n, fp = self.arg(0), self.arg(1), self.arg(2), self.arg(3)
        b = self.files[fp].read(sz * n)
        if b: self.uc.mem_write(p, b)
        return len(b) // sz if sz else 0
    def ffseek(self): self.files[self.arg(0)].seek(struct.unpack('<i', struct.pack('<I', self.arg(1)))[0], self.arg(2)); return 0
    def fftell(self): return self.files[self.arg(0)].tell()
    def ffputc(self): self.files[self.arg(1)].write(bytes([self.arg(0) & 0xff])); return self.arg(0) & 0xff
    def ffputs(self): self.files[self.arg(1)].write(self.cstr(self.arg(0))); return 0
    def fputchar(self): self.out.write(bytes([self.arg(0) & 0xff])); return self.arg(0)
    def fputs(self): sys.stderr.buffer.write(self.cstr(self.arg(0)) + b'\n'); return 0
    def ffprintf(self):
        s = self.cfmt(self.arg(1), self.uc.reg_read(UC_X86_REG_ESP) + 12)
        f = self.files.get(self.arg(0)); (f or sys.stderr.buffer).write(s); return len(s)
    def fvfprintf(self):
        s = self.cfmt(self.arg(1), self.arg(2))
        f = self.files.get(self.arg(0)); (f or sys.stderr.buffer).write(s); return len(s)
    def fopen(self):
        p = self.cstr(self.arg(0)).decode()
        fd = 50 + len(self.fds); self.fds[fd] = p; return fd
    def fclose(self): return 0
    def fread(self): return 0

    # CUPS ------------------------------------------------------------------
    def fcupsParseOptions(self):
        s = self.cstr(self.arg(0)).decode() if self.arg(0) else ''
        self.opts = {}
        import shlex
        for tok in shlex.split(s):
            k, _, v = tok.partition('=')
            if not _: v = 'false' if k.startswith('no') else 'true'; k = k[2:] if k.startswith('no') else k
            self.opts[k.lower()] = v
        self.w32(self.arg(2), 0x1234); return len(self.opts)
    def fcupsGetOption(self):
        k = self.cstr(self.arg(0)).decode().lower()
        if k not in self.opts: return 0
        p = self.alloc_misc(len(self.opts[k]) + 1); self.put_cstr(p, self.opts[k].encode()); return p
    def fppdOpenFile(self):
        self.ppd_defaults = {}
        for line in open(PPD, encoding='latin-1'):
            if line.startswith('*Default'):
                k, _, v = line[8:].partition(':'); self.ppd_defaults[k.strip().lower()] = v.strip()
        self.ppd_opt_cache = {}
        return self.alloc_misc(256)
    def fppdFindOption(self):
        k = self.cstr(self.arg(1)).decode().lower()     # CUPS matches keywords case-insensitively
        if k not in self.ppd_defaults: return 0
        if k not in self.ppd_opt_cache:
            o = self.alloc_misc(256); self.uc.mem_write(o, b'\0' * 256)
            self.put_cstr(o + 1, k.encode()[:40]); self.put_cstr(o + 42, self.ppd_defaults[k].encode()[:40])
            self.ppd_opt_cache[k] = o
        return self.ppd_opt_cache[k]
    def fppdClose(self): return 0
    def fcupsRasterOpen(self): return 0x4242
    def fcupsRasterClose(self): return 0
    def fcupsRasterReadHeader(self):
        self.page_i += 1
        if self.page_i >= len(self.pages): return 0
        w, h, _ = self.pages[self.page_i]; self.row = 0
        hdr = bytearray(420)
        def u(off, v): struct.pack_into('<I', hdr, off, v)
        u(276, 300); u(280, 300)                  # HWResolution
        u(284, 0); u(288, 0); u(292, round(w * 72 / 300)); u(296, round(h * 72 / 300))
        u(340, 1)                                  # NumCopies
        u(352, round(w * 72 / 300)); u(356, round(h * 72 / 300))   # PageSize (pt)
        u(372, w); u(376, h); u(384, 8); u(388, 24); u(392, w * 3)
        u(396, 0); u(400, 1)                       # chunky, CUPS_CSPACE_RGB
        self.uc.mem_write(self.arg(1), bytes(hdr)); return 1
    def fcupsRasterReadPixels(self):
        w, h, data = self.pages[self.page_i]; n = self.arg(2)
        chunk = data[self.row * w * 3: self.row * w * 3 + n]; self.row += max(1, n // (w * 3))
        self.uc.mem_write(self.arg(1), chunk.ljust(n, b'\xff')); return n

    # C++ runtime -----------------------------------------------------------
    def fkeymgr(self): return 0
    def nop0(self): return 0
    def cxx_exchange_and_add(self):
        p, v = self.arg(0), self.arg(1); old = self.r32(p); self.w32(p, old + v); return old
    # GCC 4.0 COW std::string: object = char*; rep (length, capacity, refcount) precedes chars
    def _str_new(self, b):
        rep = self.malloc(12 + len(b) + 1)
        self.uc.mem_write(rep, struct.pack('<IIi', len(b), len(b), 0) + b + b'\0'); return rep + 12
    def _str_get(self, obj):
        p = self.r32(obj); n = self.r32(p - 12); return bytes(self.uc.mem_read(p, n))
    def cxx_str_ctor(self): self.w32(self.arg(0), self._str_new(self.cstr(self.arg(1)))); return 0
    def cxx_str_append_cstr_n(self):
        o = self.arg(0); self.w32(o, self._str_new(self._str_get(o) + bytes(self.uc.mem_read(self.arg(1), self.arg(2))))); return o
    def cxx_str_append_str(self):
        o = self.arg(0); self.w32(o, self._str_new(self._str_get(o) + self._str_get(self.arg(1)))); return o
    def cxx_str_assign_cstr_n(self):
        o = self.arg(0); self.w32(o, self._str_new(bytes(self.uc.mem_read(self.arg(1), self.arg(2))))); return o
    def cxx_str_reserve(self): return 0
    def cxx_rep_destroy(self): return 0
    def cxx_unhandled(self):
        raise RuntimeError('C++ exception path reached in original filter')
    # std::_List_node_base { next, prev }
    def cxx_list_hook(self):
        node, pos = self.arg(0), self.arg(1); prev = self.r32(pos + 4)
        self.w32(node, pos); self.w32(node + 4, prev); self.w32(prev, node); self.w32(pos + 4, node); return 0
    def cxx_list_unhook(self):
        node = self.arg(0); nx, pv = self.r32(node), self.r32(node + 4)
        self.w32(pv, nx); self.w32(nx + 4, pv); return 0
    # red-black tree node: color, parent, left, right
    def cxx_rb_increment(self):
        x = self.arg(0)
        if self.r32(x + 12):
            x = self.r32(x + 12)
            while self.r32(x + 8): x = self.r32(x + 8)
        else:
            y = self.r32(x + 4)
            while x == self.r32(y + 12): x = y; y = self.r32(y + 4)
            if self.r32(x + 12) != y: x = y
        return x
    def cxx_rb_decrement(self):
        x = self.arg(0)
        if self.r32(x) == 0 and self.r32(self.r32(x + 4) + 4) == x: return self.r32(x + 12)
        if self.r32(x + 8):
            y = self.r32(x + 8)
            while self.r32(y + 12): y = self.r32(y + 12)
            return y
        y = self.r32(x + 4)
        while x == self.r32(y + 8): x = y; y = self.r32(y + 4)
        return y
    def cxx_rb_insert_rebalance(self):
        insert_left, x, p, header = self.arg(0), self.arg(1), self.arg(2), self.arg(3)
        R = self.r32; W = self.w32
        RED, BLACK = 0, 1
        W(x + 4, p); W(x + 8, 0); W(x + 12, 0); W(x, RED)
        if insert_left:
            W(p + 8, x)
            if p == header: W(header + 4, x); W(header + 12, x)
            elif p == R(header + 8): W(header + 8, x)
        else:
            W(p + 12, x)
            if p == R(header + 12): W(header + 12, x)
        root = header + 4
        def rot_left(x):
            y = R(x + 12); W(x + 12, R(y + 8))
            if R(y + 8): W(R(y + 8) + 4, x)
            W(y + 4, R(x + 4))
            if x == R(root): W(root, y)
            elif x == R(R(x + 4) + 8): W(R(x + 4) + 8, y)
            else: W(R(x + 4) + 12, y)
            W(y + 8, x); W(x + 4, y)
        def rot_right(x):
            y = R(x + 8); W(x + 8, R(y + 12))
            if R(y + 12): W(R(y + 12) + 4, x)
            W(y + 4, R(x + 4))
            if x == R(root): W(root, y)
            elif x == R(R(x + 4) + 12): W(R(x + 4) + 12, y)
            else: W(R(x + 4) + 8, y)
            W(y + 12, x); W(x + 4, y)
        while x != R(root) and R(R(x + 4)) == RED:
            xp = R(x + 4); xpp = R(xp + 4)
            if xp == R(xpp + 8):
                y = R(xpp + 12)
                if y and R(y) == RED:
                    W(xp, BLACK); W(y, BLACK); W(xpp, RED); x = xpp
                else:
                    if x == R(xp + 12): x = xp; rot_left(x); xp = R(x + 4); xpp = R(xp + 4)
                    W(xp, BLACK); W(xpp, RED); rot_right(xpp)
            else:
                y = R(xpp + 8)
                if y and R(y) == RED:
                    W(xp, BLACK); W(y, BLACK); W(xpp, RED); x = xpp
                else:
                    if x == R(xp + 8): x = xp; rot_right(x); xp = R(x + 4); xpp = R(xp + 4)
                    W(xp, BLACK); W(xpp, RED); rot_left(xpp)
        W(R(root), BLACK); return 0

CXX = {
    '__ZN9__gnu_cxx18__exchange_and_addEPVii': 'cxx_exchange_and_add',
    '__ZNSs4_Rep10_M_destroyERKSaIcE': 'cxx_rep_destroy',
    '__ZNSs6appendEPKcm': 'cxx_str_append_cstr_n',
    '__ZNSs6appendERKSs': 'cxx_str_append_str',
    '__ZNSs6assignEPKcm': 'cxx_str_assign_cstr_n',
    '__ZNSs7reserveEm': 'cxx_str_reserve',
    '__ZNSsC1EPKcRKSaIcE': 'cxx_str_ctor',
    '__ZNSt15_List_node_base4hookEPS_': 'cxx_list_hook',
    '__ZNSt15_List_node_base6unhookEv': 'cxx_list_unhook',
    '__ZSt18_Rb_tree_incrementPSt18_Rb_tree_node_base': 'cxx_rb_increment',
    '__ZSt18_Rb_tree_decrementPSt18_Rb_tree_node_base': 'cxx_rb_decrement',
    '__ZSt29_Rb_tree_insert_and_rebalancebPSt18_Rb_tree_node_baseS0_RS_': 'cxx_rb_insert_rebalance',
    '___keymgr_dwarf2_register_sections': 'nop0',
    '__keymgr_get_and_lock_processwide_ptr': 'nop0',
    '__keymgr_get_and_lock_processwide_ptr_2': 'nop0',
    '__keymgr_set_and_unlock_processwide_ptr': 'nop0',
    '___cxa_begin_catch': 'cxx_unhandled', '___cxa_end_catch': 'nop0',
    '___cxa_rethrow': 'cxx_unhandled', '___cxa_call_unexpected': 'cxx_unhandled',
    '__Unwind_Resume': 'cxx_unhandled',
    '___error': 'ferror',
}

def read_ppm(path):
    d = open(path, 'rb').read()
    toks, i = [], 0
    while len(toks) < 4:
        while d[i:i+1].isspace(): i += 1
        if d[i:i+1] == b'#':
            while d[i:i+1] != b'\n': i += 1
            continue
        j = i
        while not d[j:j+1].isspace(): j += 1
        toks.append(d[i:j]); i = j
    assert toks[0] == b'P6', 'need binary PPM (P6)'
    w, h = int(toks[1]), int(toks[2])
    return w, h, d[i+1:i+1+w*h*3]

if __name__ == '__main__':
    if len(sys.argv) < 3: sys.exit(__doc__)
    pages = [read_ppm(p) for p in sys.argv[1].split(',')]
    opts = ' '.join(sys.argv[3:])
    emu = Emu(pages, opts, sys.argv[2])
    t = time.time()
    rc = emu.run(['rastertofargoHDP5000', '1', 'user', 'title', '1', opts])
    print(f'exit={rc} in {time.time() - t:.1f}s -> {sys.argv[2]} ({os.path.getsize(sys.argv[2])} bytes)', file=sys.stderr)
    sys.exit(rc)
