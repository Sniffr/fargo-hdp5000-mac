"""Minimal i386 Mach-O reader for the 2009 Fargo filter: segments, symbols, import stubs."""
import struct

class MachO:
    def __init__(self, path):
        self.data = d = open(path, 'rb').read()
        magic, cpu, sub, ftype, ncmds, sizeofcmds, flags = struct.unpack_from('<7I', d, 0)
        assert magic == 0xfeedface and cpu == 7, 'not i386 Mach-O'
        self.segments, self.sections, off = [], [], 28
        symoff = nsyms = stroff = indoff = nind = 0
        for _ in range(ncmds):
            cmd, size = struct.unpack_from('<II', d, off)
            if cmd == 0x1:  # LC_SEGMENT
                name = d[off+8:off+24].rstrip(b'\0').decode()
                vmaddr, vmsize, fileoff, filesize, maxprot, initprot, nsects, _ = struct.unpack_from('<8I', d, off+24)
                self.segments.append((name, vmaddr, vmsize, fileoff, filesize))
                s = off + 56
                for _ in range(nsects):
                    sect = d[s:s+16].rstrip(b'\0').decode(); seg = d[s+16:s+32].rstrip(b'\0').decode()
                    addr, ssize, soff, align, reloff, nreloc, sflags, r1, r2 = struct.unpack_from('<9I', d, s+32)
                    self.sections.append(dict(seg=seg, sect=sect, addr=addr, size=ssize, off=soff, flags=sflags, r1=r1, r2=r2))
                    s += 68
            elif cmd == 0x2:   # LC_SYMTAB
                symoff, nsyms, stroff, strsize = struct.unpack_from('<4I', d, off+8)
            elif cmd == 0xb:   # LC_DYSYMTAB
                v = struct.unpack_from('<18I', d, off+8); indoff, nind = v[12], v[13]
            elif cmd == 0x5:   # LC_UNIXTHREAD
                self.entry = struct.unpack_from('<16I', d, off+16)[10]
            off += size
        self.syms, self.addr2sym = [], {}
        for i in range(nsyms):
            strx, ntype, sect, desc, value = struct.unpack_from('<IBBhI', d, symoff + 12*i)
            name = d[stroff+strx:d.index(b'\0', stroff+strx)].decode()
            self.syms.append((name, ntype, value))
            if ntype & 0x0e == 0x0e and value: self.addr2sym.setdefault(value, name)
        self.name2addr = {n: v for n, t, v in self.syms if t & 0x0e == 0x0e and v}
        ind = struct.unpack_from(f'<{nind}I', d, indoff)
        self.stubs, self.pointers = {}, {}   # addr -> imported symbol name
        for s in self.sections:
            kind = s['flags'] & 0xff
            if kind == 0x8 and s['size']:                      # S_SYMBOL_STUBS (__jump_table)
                for k in range(s['size'] // s['r2']):
                    self.stubs[s['addr'] + k*s['r2']] = self.syms[ind[s['r1']+k]][0]
            elif kind in (0x6, 0x7) and s['size']:             # non-lazy / lazy pointers
                for k in range(s['size'] // 4):
                    idx = ind[s['r1']+k]
                    if idx & 0xc0000000 == 0: self.pointers[s['addr'] + 4*k] = self.syms[idx][0]

if __name__ == '__main__':
    import sys
    m = MachO(sys.argv[1])
    print('entry', hex(m.entry)); print(len(m.stubs), 'stubs,', len(m.pointers), 'pointers')
    for a, n in sorted(m.pointers.items()): print('ptr', hex(a), n)
