"""Decode the reassembled Fg command stream (experimental)."""
import struct, sys
sys.path.insert(0, '/Users/sidneymalingu/hdp/tools')
from prnparse import packets

def rle_decode(s, i, width):
    out = bytearray()
    while len(out) < width:
        c = s[i]; i += 1
        if c < 0x80: out += bytes([s[i]]) * (c + 1); i += 1
        else: n = c - 0x7f; out += s[i:i+n]; i += n
    return bytes(out), i

def stream(path):
    return b''.join(p for t, v, p in packets(open(path, 'rb').read()) if t == 'g')
