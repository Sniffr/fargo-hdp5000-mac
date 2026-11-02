"""Capture input/output of _ripCompressPLineHorz while running the original filter."""
import sys, struct, os, pickle
sys.path.insert(0, os.path.dirname(__file__))
from run_original import Emu, read_ppm
from unicorn import UC_HOOK_CODE
from unicorn.x86_const import *
src, out, *opts = sys.argv[1:]
emu = Emu([read_ppm(p) for p in src.split(',')], ' '.join(opts), out)
fn = emu.m.name2addr['_ripCompressPLineHorz']
calls = []; pending = {}
def on_entry(uc, addr, size, _):
    esp = uc.reg_read(UC_X86_REG_ESP); ra = emu.r32(esp)
    a = [emu.r32(esp + 4 + 4*i) for i in range(4)]
    pending[ra] = (a, bytes(uc.mem_read(a[0], 8 + 768)))
    uc.hook_add(UC_HOOK_CODE, on_ret, begin=ra, end=ra, user_data=ra)
def on_ret(uc, addr, size, ra):
    if ra not in pending: return
    a, before = pending.pop(ra); n = uc.reg_read(UC_X86_REG_EAX)
    after = bytes(uc.mem_read(a[0], max(n & 0xfff, 16) + 4))
    calls.append((a[1:], before, n, after))
emu.uc.hook_add(UC_HOOK_CODE, on_entry, begin=fn, end=fn)
emu.run(['f', '1', 'u', 't', '1', ' '.join(opts)])
pickle.dump(calls, open(out + '.calls.pkl', 'wb'))
print(len(calls), 'calls')
for c in calls[:3]:
    print('args', c[0], 'ret', hex(c[2])); print(' in ', c[1][:40].hex(' ')); print(' out', c[3][:40].hex(' '))
