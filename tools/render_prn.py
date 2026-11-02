"""Render each panel of an HDP5000 .prn job to a PGM (convert to PNG with sips)."""
import sys, struct, os; sys.path.insert(0, os.path.dirname(__file__))
from fgstream import stream, rle_decode
W = 768
def write_png(path, w, h, gray):
    import zlib
    raw = b''.join(b'\0' + gray[y*w:(y+1)*w] for y in range(h))
    def chunk(t, d): return struct.pack('>I', len(d)) + t + d + struct.pack('>I', zlib.crc32(t + d))
    with open(path, 'wb') as f:
        f.write(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 0, 0, 0, 0))
                + chunk(b'IDAT', zlib.compress(raw, 9)) + chunk(b'IEND', b''))
def line_hdr_size(s):
    # 2009 jobs: 10-byte line header; 2012 filter: 12 (two extra bytes = first two dots)
    i = s.find(b'\x0f\x00\x00\x00\x16\x00\x00\x00')
    if i < 0: return 12
    i += 8 + 22                      # first scan line follows the first panel header
    for h in (12, 10):
        try:
            _, j = rle_decode(s, i + h, W)
            if s[j:j+4] in (b'\x10\x00\x00\x00', b'\x0f\x00\x00\x00', b'\x11\x00\x00\x00'): return h
        except IndexError: pass
    return 10
def panels(s):
    i = 0; cur = None; H = line_hdr_size(s)
    while i < len(s):
        op, ln = struct.unpack_from('<II', s, i)
        if op == 0x10:
            rep = struct.unpack_from('<H', s, i+8)[0]
            row, i = rle_decode(s, i+H, W); cur[1].extend([row]*rep); continue
        if op == 0x0f:
            if cur: yield cur
            cur = (s[i+8:i+8+ln], [])
        i += 8 + ln
    if cur: yield cur
if __name__ == '__main__':
    src, outdir = sys.argv[1], sys.argv[2]; os.makedirs(outdir, exist_ok=True)
    base = os.path.basename(src)[:-4]
    for n, (hdr, rows) in enumerate(panels(stream(src))):
        p = f'{outdir}/{base}_p{n}.png'
        write_png(p, W, len(rows), b''.join(rows))
        print(p, len(rows), hdr.hex(' '))
