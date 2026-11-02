"""Generate deterministic RGB test cards (binary PPM) at 300 dpi CR80 (662x1033)."""
import sys, math
W, H = 662, 1033
def pattern(kind):
    px = bytearray(W * H * 3)
    for y in range(H):
        for x in range(W):
            if kind == 'white': r = g = b = 255
            elif kind == 'black': r = g = b = 0
            elif kind == 'bars':     # colour bars top, grey ramp middle, hue sweep bottom
                if y < H // 3:
                    r, g, b = [(255,255,255),(255,255,0),(0,255,255),(0,255,0),(255,0,255),(255,0,0),(0,0,255),(0,0,0)][x * 8 // W]
                elif y < 2 * H // 3: r = g = b = x * 255 // (W - 1)
                else:
                    h = x / W * 6; c = int(255 * (1 - abs(h % 2 - 1)))
                    r, g, b = [(255,c,0),(c,255,0),(0,255,c),(0,c,255),(c,0,255),(255,0,c)][int(h) % 6]
                    v = 1 - (y - 2 * H // 3) / (H / 3); r, g, b = int(r * v), int(g * v), int(b * v)
            elif kind == 'text':     # black-only shapes on white (K panel extraction)
                r = g = b = 0 if ((x // 40 + y // 40) % 2 == 0 and 100 < y < 600) or (700 < y < 720) else 255
            else: raise SystemExit('unknown pattern')
            i = (y * W + x) * 3; px[i:i+3] = bytes((r, g, b))
    return b'P6\n%d %d\n255\n' % (W, H) + bytes(px)
for kind in sys.argv[2:]:
    open(f'{sys.argv[1]}/{kind}.ppm', 'wb').write(pattern(kind))
