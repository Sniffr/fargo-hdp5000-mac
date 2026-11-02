"""Write a simple CR80 portrait test-card PDF (159x248 pt): colour blocks, photo-ish gradient strip, black text."""
import sys, zlib
W, H = 159, 248
ops = []
cols = [(1,1,0),(0,1,1),(1,0,1),(1,0,0),(0,1,0),(0,0,1)]
for k, (r, g, b) in enumerate(cols):
    ops.append(f'{r} {g} {b} rg {10 + k*23} 180 22 50 re f')
for k in range(60):            # grey ramp
    v = k / 59; ops.append(f'{v:.3f} g {10 + k*2.32:.2f} 140 2.4 30 re f')
ops.append('0 g BT /F1 18 Tf 14 100 Td (HDP5000) Tj ET')
ops.append('0 g BT /F1 9 Tf 14 84 Td (native driver test) Tj ET')
ops.append('0 0 0 rg 14 40 131 3 re f')
content = '\n'.join(ops).encode()
objs = [b'<< /Type /Catalog /Pages 2 0 R >>',
        b'<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
        f'<< /Type /Page /Parent 2 0 R /MediaBox [0 0 {W} {H}] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>'.encode(),
        b'<< /Length %d >>\nstream\n' % len(content) + content + b'\nendstream',
        b'<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>']
out = bytearray(b'%PDF-1.4\n'); offs = []
for i, o in enumerate(objs, 1):
    offs.append(len(out)); out += b'%d 0 obj\n' % i + o + b'\nendobj\n'
x = len(out)
out += b'xref\n0 %d\n0000000000 65535 f \n' % (len(objs) + 1) + b''.join(b'%010d 00000 n \n' % o for o in offs)
out += b'trailer\n<< /Size %d /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF\n' % (len(objs) + 1, x)
open(sys.argv[1], 'wb').write(out)
