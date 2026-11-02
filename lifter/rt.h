/* Runtime for code recompiled from the i386 HDP5000 filter (see lift.py).
 * Guest state: flat 32-bit address space at MEM, registers, flags, SSE, x87. */
#ifndef HDP_RT_H
#define HDP_RT_H
#include <stdint.h>
#include <string.h>
#include <math.h>

typedef union { float f[4]; double d[2]; uint32_t u[4]; int32_t i[4]; uint64_t q[2]; } xmm_t;

extern uint8_t *MEM;
extern uint32_t EAX, EBX, ECX, EDX, ESI, EDI, EBP, ESP;
extern uint8_t CF, ZF, SF, OF, PF;
extern xmm_t XMM[8];
extern double FPU[8];
extern int FTOP;

void call_addr(uint32_t a);
void trap(uint32_t a, const char *why) __attribute__((noreturn));

/* memory */
static inline uint32_t RD32(uint32_t a) { uint32_t v; memcpy(&v, MEM + a, 4); return v; }
static inline uint32_t RD16(uint32_t a) { uint16_t v; memcpy(&v, MEM + a, 2); return v; }
static inline uint32_t RD8(uint32_t a)  { return MEM[a]; }
static inline uint64_t RD64(uint32_t a) { uint64_t v; memcpy(&v, MEM + a, 8); return v; }
static inline float RDF32(uint32_t a)   { float v; memcpy(&v, MEM + a, 4); return v; }
static inline double RDF64(uint32_t a)  { double v; memcpy(&v, MEM + a, 8); return v; }
static inline xmm_t RDX(uint32_t a)     { xmm_t v; memcpy(&v, MEM + a, 16); return v; }
static inline void WR32(uint32_t a, uint32_t v) { memcpy(MEM + a, &v, 4); }
static inline void WR16(uint32_t a, uint32_t v) { uint16_t w = (uint16_t)v; memcpy(MEM + a, &w, 2); }
static inline void WR8(uint32_t a, uint32_t v)  { MEM[a] = (uint8_t)v; }
static inline void WR64(uint32_t a, uint64_t v) { memcpy(MEM + a, &v, 8); }
static inline void WRF32(uint32_t a, float v)   { memcpy(MEM + a, &v, 4); }
static inline void WRF64(uint32_t a, double v)  { memcpy(MEM + a, &v, 8); }
static inline void WRX(uint32_t a, xmm_t v)     { memcpy(MEM + a, &v, 16); }

static inline void PUSH(uint32_t v) { ESP -= 4; WR32(ESP, v); }
static inline uint32_t POP(void) { uint32_t v = RD32(ESP); ESP += 4; return v; }

/* flags */
static inline void SZP(uint32_t r, int bits) {
    uint32_t m = bits == 32 ? 0xffffffffu : ((1u << bits) - 1);
    r &= m; ZF = r == 0; SF = (r >> (bits - 1)) & 1; PF = !__builtin_parity(r & 0xff);
}
#define DEF_ARITH(B, M) \
static inline uint32_t ADD##B(uint32_t a, uint32_t b) { uint32_t r = (a + b) & M; \
    CF = r < (a & M); OF = (((a ^ r) & (b ^ r)) >> (B - 1)) & 1; SZP(r, B); return r; } \
static inline uint32_t SUB##B(uint32_t a, uint32_t b) { uint32_t r = (a - b) & M; \
    CF = (a & M) < (b & M); OF = (((a ^ b) & (a ^ r)) >> (B - 1)) & 1; SZP(r, B); return r; } \
static inline uint32_t ADC##B(uint32_t a, uint32_t b) { uint32_t c = CF; uint64_t w = (uint64_t)(a & M) + (b & M) + c; \
    uint32_t r = (uint32_t)w & M; CF = (w >> B) & 1; OF = (((a ^ r) & (b ^ r)) >> (B - 1)) & 1; SZP(r, B); return r; } \
static inline uint32_t SBB##B(uint32_t a, uint32_t b) { uint32_t c = CF; uint32_t r = (a - b - c) & M; \
    CF = (uint64_t)(a & M) < (uint64_t)(b & M) + c; OF = (((a ^ b) & (a ^ r)) >> (B - 1)) & 1; SZP(r, B); return r; } \
static inline void LOGIC##B(uint32_t r) { CF = 0; OF = 0; SZP(r, B); } \
static inline uint32_t INC##B(uint32_t a) { uint32_t r = (a + 1) & M; OF = r == (1u << (B - 1)); SZP(r, B); return r; } \
static inline uint32_t DEC##B(uint32_t a) { uint32_t r = (a - 1) & M; OF = (a & M) == (1u << (B - 1)); SZP(r, B); return r; } \
static inline uint32_t NEG##B(uint32_t a) { uint32_t r = (0 - a) & M; CF = (a & M) != 0; OF = (a & M) == (1u << (B - 1)); SZP(r, B); return r; } \
static inline uint32_t SHL##B(uint32_t a, uint32_t n) { n &= 31; if (!n) return a & M; a &= M; \
    uint32_t r = n >= B ? 0 : (a << n) & M; CF = n <= B ? (a >> (B - n)) & 1 : 0; OF = ((r >> (B - 1)) & 1) ^ CF; SZP(r, B); return r; } \
static inline uint32_t SHR##B(uint32_t a, uint32_t n) { n &= 31; if (!n) return a & M; a &= M; \
    uint32_t r = n >= B ? 0 : a >> n; CF = (a >> (n - 1)) & 1; OF = (a >> (B - 1)) & 1; SZP(r, B); return r; } \
static inline uint32_t SAR##B(uint32_t a, uint32_t n) { n &= 31; if (!n) return a & M; \
    int32_t s = B == 32 ? (int32_t)a : (B == 16 ? (int16_t)a : (int8_t)a); \
    uint32_t r = (uint32_t)(s >> (n >= B ? B - 1 : n)) & M; CF = (uint32_t)(s >> (n - 1 >= B ? B - 1 : n - 1)) & 1; OF = 0; SZP(r, B); return r; } \
static inline uint32_t ROL##B(uint32_t a, uint32_t n) { n &= 31; a &= M; n %= B; if (!n) return a; \
    uint32_t r = ((a << n) | (a >> (B - n))) & M; CF = r & 1; return r; } \
static inline uint32_t ROR##B(uint32_t a, uint32_t n) { n &= 31; a &= M; n %= B; if (!n) return a; \
    uint32_t r = ((a >> n) | (a << (B - n))) & M; CF = (r >> (B - 1)) & 1; return r; }
DEF_ARITH(8, 0xffu)
DEF_ARITH(16, 0xffffu)
DEF_ARITH(32, 0xffffffffu)

static inline uint32_t IMUL32(uint32_t a, uint32_t b) {
    int64_t r = (int64_t)(int32_t)a * (int32_t)b; CF = OF = r != (int32_t)r; return (uint32_t)r; }
static inline uint32_t IMUL16(uint32_t a, uint32_t b) {
    int32_t r = (int16_t)a * (int16_t)b; CF = OF = r != (int16_t)r; return (uint32_t)r & 0xffff; }
static inline void IMUL1_32(uint32_t b) {
    int64_t r = (int64_t)(int32_t)EAX * (int32_t)b; EAX = (uint32_t)r; EDX = (uint32_t)((uint64_t)r >> 32); CF = OF = r != (int32_t)r; }
static inline void MUL1_32(uint32_t b) {
    uint64_t r = (uint64_t)EAX * b; EAX = (uint32_t)r; EDX = (uint32_t)(r >> 32); CF = OF = EDX != 0; }
static inline void IMUL1_8(uint32_t b) {
    int16_t r = (int16_t)(int8_t)EAX * (int8_t)b; EAX = (EAX & 0xffff0000u) | (uint16_t)r; CF = OF = r != (int8_t)r; }
static inline void MUL1_8(uint32_t b) {
    uint16_t r = (uint16_t)((EAX & 0xff) * (b & 0xff)); EAX = (EAX & 0xffff0000u) | r; CF = OF = (r >> 8) != 0; }
static inline void IDIV32(uint32_t b) {
    int64_t n = (int64_t)(((uint64_t)EDX << 32) | EAX); if (!b) trap(0, "divide by zero");
    int64_t q = n / (int32_t)b, r = n % (int32_t)b; EAX = (uint32_t)q; EDX = (uint32_t)r; }
static inline void UDIV32(uint32_t b) {
    uint64_t n = ((uint64_t)EDX << 32) | EAX; if (!b) trap(0, "divide by zero");
    EAX = (uint32_t)(n / b); EDX = (uint32_t)(n % b); }
static inline void UDIV8(uint32_t b) {
    uint32_t n = EAX & 0xffff; b &= 0xff; if (!b) trap(0, "divide by zero");
    EAX = (EAX & 0xffff0000u) | ((n % b) << 8) | ((n / b) & 0xff); }
static inline void IDIV8(uint32_t b) {
    int32_t n = (int16_t)(EAX & 0xffff); int32_t d = (int8_t)b; if (!d) trap(0, "divide by zero");
    EAX = (EAX & 0xffff0000u) | (((uint32_t)(n % d) & 0xff) << 8) | ((uint32_t)(n / d) & 0xff); }

static inline uint32_t CVTT(double v) {   /* SSE truncating conversion; out of range -> 0x80000000 */
    if (!(v > -2147483649.0 && v < 2147483648.0)) return 0x80000000u;
    return (uint32_t)(int32_t)v;
}
static inline void UCOMI(double a, double b) {
    OF = SF = 0;
    if (a != a || b != b) { ZF = PF = CF = 1; return; }
    PF = 0; ZF = a == b; CF = a < b;
}

/* x87 stack (doubles; the original only uses it for float returns and a few ops) */
static inline void FPUSH(double v) { FTOP = (FTOP - 1) & 7; FPU[FTOP] = v; }
static inline void FPOP(void) { FTOP = (FTOP + 1) & 7; }
static inline double FST(int k) { return FPU[(FTOP + k) & 7]; }
static inline void FSTSET(int k, double v) { FPU[(FTOP + k) & 7] = v; }

/* string ops (DF is always clear in this code) */
static inline void STRMOVS(int n, int rep) {
    if (!rep) { memmove(MEM + EDI, MEM + ESI, n); ESI += n; EDI += n; return; }
    while (ECX) { memmove(MEM + EDI, MEM + ESI, n); ESI += n; EDI += n; ECX--; }
}
static inline void STRSTOS(int n, int rep) {
    uint32_t cnt = rep ? ECX : 1;
    for (uint32_t k = 0; k < cnt; k++) {
        if (n == 1) WR8(EDI, EAX); else if (n == 2) WR16(EDI, EAX); else WR32(EDI, EAX);
        EDI += n;
    }
    if (rep) ECX = 0;
}
static inline void REPNE_SCASB(void) {
    uint8_t al = EAX & 0xff;
    while (ECX) { uint8_t b = MEM[EDI]; EDI++; ECX--; SUB8(al, b); if (b == al) break; }
}
static inline void REPE_CMPSB(void) {
    while (ECX) { uint8_t a = MEM[ESI], b = MEM[EDI]; ESI++; EDI++; ECX--; SUB8(a, b); if (a != b) break; }
}
#endif
