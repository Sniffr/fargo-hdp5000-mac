"""List the non-scanline records of a job (and per-panel line counts)."""
import sys, struct, os
sys.path.insert(0, os.path.dirname(__file__))
from fgstream import stream, rle_decode
from render_prn import line_hdr_size
def records(path):
    s = stream(path); H = line_hdr_size(s); i = 0; out = []; lines = 0
    while i < len(s):
        op, ln = struct.unpack_from('<II', s, i)
        if op == 0x10:
            lines += struct.unpack_from('<H', s, i + 8)[0]; _, i = rle_decode(s, i + H, 768); continue
        if lines: out.append(('lines', lines)); lines = 0
        out.append((op, s[i+8:i+8+ln].hex(' '))); i += 8 + ln
    return out
if __name__ == '__main__':
    for r in records(sys.argv[1]): print(r)
