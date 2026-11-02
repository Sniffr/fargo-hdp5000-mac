import sys, struct; sys.path.insert(0,'/Users/sidneymalingu/hdp/tools')
from fgstream import *
s=stream(sys.argv[1]); W=int(sys.argv[2]) if len(sys.argv)>2 else 768
i=0
while i < len(s):
    op, ln = struct.unpack_from('<II', s, i)
    if op == 0x10:
        j=i; lines=0; reps=0; hdrs={}
        while j < len(s) and struct.unpack_from('<I', s, j)[0] == 0x10:
            a,b = struct.unpack_from('<IH', s, j+4); hdrs[(a,b)]=hdrs.get((a,b),0)+1
            row, j = rle_decode(s, j+10, W); lines+=1; reps+=b
        print(f'{i:#8x} {lines} lines, sum(field)={reps}, hdr variants={sorted(hdrs.items())}')
        i = j; continue
    print(f'{i:#8x} op={op:#x} len={ln} body={s[i+8:i+8+ln].hex(" ")}')
    i += 8 + ln
