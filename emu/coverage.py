"""Record which functions of the original filter execute (and how often) for a given job."""
import sys, os, collections
sys.path.insert(0, os.path.dirname(__file__))
from run_original import Emu, read_ppm
from unicorn import UC_HOOK_BLOCK
src, out, *opts = sys.argv[1:]
emu = Emu([read_ppm(p) for p in src.split(',')], ' '.join(opts), out)
starts = set(a for a in emu.m.addr2sym if a < 0x9e000)
hits = collections.Counter()
def blk(uc, addr, size, _):
    if addr in starts: hits[addr] += 1
emu.uc.hook_add(UC_HOOK_BLOCK, blk, begin=0x1000, end=0x8d000)
emu.run(['f', '1', 'u', 't', '1', ' '.join(opts)])
for a, n in sorted(hits.items(), key=lambda x: -x[1]):
    name = emu.m.addr2sym[a]
    if 'Icc' in name or 'icc' in name or name.startswith('__Z') and 'Icc' in name: continue
    print(f'{n:9d} {name}')
