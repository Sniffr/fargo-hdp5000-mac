#!/usr/bin/env python3
"""Convert one or more binary PPMs into an uncompressed CUPS raster stream (RaS3),
8-bit RGB chunky @300dpi -- the same page description the emulator feeds the original.
usage: ppm2raster.py out.ras page1.ppm [page2.ppm ...]"""
import struct, sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'emu'))
def read_ppm(path):
    d = open(path, 'rb').read(); toks, i = [], 0
    while len(toks) < 4:
        while d[i:i+1].isspace(): i += 1
        if d[i:i+1] == b'#':
            while d[i:i+1] != b'\n': i += 1
            continue
        j = i
        while not d[j:j+1].isspace(): j += 1
        toks.append(d[i:j]); i = j
    w, h = int(toks[1]), int(toks[2]); return w, h, d[i+1:i+1+w*h*3]
def header(w, h):
    hdr = bytearray(1796)
    def u(off, v): struct.pack_into('<I', hdr, off, v)
    u(276, 300); u(280, 300)
    u(292, round(w * 72 / 300)); u(296, round(h * 72 / 300))
    u(340, 1)
    u(352, round(w * 72 / 300)); u(356, round(h * 72 / 300))
    u(372, w); u(376, h); u(384, 8); u(388, 24); u(392, w * 3)
    u(396, 0); u(400, 1)
    u(420, 1)   # cupsNumColors
    return bytes(hdr)
with open(sys.argv[1], 'wb') as f:
    f.write(b'3SaR')   # little-endian "RaS3" sync word
    for p in sys.argv[2:]:
        w, h, px = read_ppm(p); f.write(header(w, h)); f.write(px)
