"""Harder deterministic test cards: noise, photo-ish gradients with black text."""
import random, math, sys
W, H = 662, 1033
def save(path, px): open(path, 'wb').write(b'P6\n%d %d\n255\n' % (W, H) + bytes(px))
r = random.Random(5000)
px = bytearray(r.getrandbits(8) for _ in range(W * H * 3)); save(sys.argv[1] + '/noise.ppm', px)
px = bytearray(W * H * 3)
for y in range(H):
    for x in range(W):
        i = (y * W + x) * 3
        R = int(127 + 127 * math.sin(x / 50.0)); G = int(127 + 127 * math.sin(y / 70.0)); B = int(127 + 127 * math.cos((x + y) / 90.0))
        if 300 < y < 360 and (x // 12) % 3 != 2: R = G = B = 0          # "text" bars in pure black
        if 600 < y < 640 and 100 < x < 560: R = G = B = 0
        px[i:i+3] = bytes((R, G, B))
save(sys.argv[1] + '/photo_text.ppm', px)
