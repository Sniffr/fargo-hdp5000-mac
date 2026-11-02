#!/usr/bin/env python3
"""Split a Fargo HDP5000 .prn job into its packets.
Packet: 'F' <type:1> <ver:u16le> <len:u16le> <payload:len> 'e' 'P'."""
import struct, sys

def packets(data):
    i = 0
    while i < len(data):
        if data[i:i+1] == b'\x1b':          # raw ESC command (calibration files)
            yield ('ESC', 0, data[i+1:]); return
        if data[i:i+1] != b'F':
            raise ValueError(f'bad packet start at {i:#x}: {data[i:i+8].hex()}')
        t = chr(data[i+1]); ver, ln = struct.unpack_from('<HH', data, i+2)
        p = data[i+6:i+6+ln]
        if data[i+6+ln:i+8+ln] != b'eP':
            raise ValueError(f'missing eP trailer at {i+6+ln:#x}')
        yield (t, ver, p); i += 8 + ln

if __name__ == '__main__':
    data = open(sys.argv[1], 'rb').read()
    run = None
    for t, ver, p in packets(data):
        if t == 'g' and len(p) == 512:      # collapse image chunks
            run = (run or 0) + 1; continue
        if run: print(f'  ... {run} x Fg[512] image chunks'); run = None
        print(f'F{t} v{ver} len={len(p):4d}  {p[:64].hex(" ")}')
    if run: print(f'  ... {run} x Fg[512] image chunks')
