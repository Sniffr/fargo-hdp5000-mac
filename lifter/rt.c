/* Native runtime for the recompiled HDP5000 filter.
 *
 * Provides the guest address space, loads the original image, and implements
 * the ~100 libc / libcups / libstdc++ functions the original imported.  Guest
 * pointers are 32-bit offsets into MEM; strings and wide strings can be used
 * in place because guest and host share byte order and sizeof(wchar_t) == 4.
 */
#include "rt.h"
#include <cups/cups.h>
#include <cups/raster.h>
#include <errno.h>
#include <fcntl.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>
#include <wchar.h>
#include <ctype.h>

uint8_t *MEM;
uint32_t EAX, EBX, ECX, EDX, ESI, EDI, EBP, ESP;
uint8_t CF, ZF, SF, OF, PF;
xmm_t XMM[8];
double FPU[8];
int FTOP;

extern const uint32_t IMAGE_BASE, IMAGE_SIZE, MAIN_ADDR;
extern const unsigned char IMAGE_DATA[];
extern const uint32_t NL_PTR_ADDR[], NL_PTR_LOCAL[], INIT_FUNCS[];
extern const char *const NL_PTR_NAME[];
extern const int NL_PTR_COUNT;

#define HEAP_BASE  0x10000000u
#define HEAP_END   0x50000000u
#define MISC_BASE  0x60000000u
#define MISC_END   0x6f000000u
#define STACK_TOP  0x7f000000u

static uint32_t heap_brk = HEAP_BASE, misc_brk = MISC_BASE;
static int debug_enabled;

void trap(uint32_t a, const char *why) {
    fprintf(stderr, "ERROR: HDP5000 filter internal fault at 0x%x: %s\n", a, why);
    exit(1);
}

/* ------------------------------------------------------------ allocation */
/* size header in front of every block so realloc can copy */
static uint32_t g_malloc(uint32_t n) {
    uint32_t a = (heap_brk + 15) & ~15u;
    if (n == 0) n = 1;
    if ((uint64_t)a + 16 + n > HEAP_END) trap(0, "guest heap exhausted");
    WR32(a, n); heap_brk = a + 16 + n; return a + 16;
}
static uint32_t misc_alloc(uint32_t n) {
    uint32_t a = (misc_brk + 15) & ~15u; misc_brk = a + n;
    if (misc_brk > MISC_END) trap(0, "misc area exhausted");
    memset(MEM + a, 0, n); return a;
}
static uint32_t guest_strdup(const char *s) {
    uint32_t a = misc_alloc((uint32_t)strlen(s) + 1); strcpy((char *)MEM + a, s); return a;
}

#define ARG(i) RD32(ESP + 4 + 4 * (i))
#define ARGD(i) RDF64(ESP + 4 + 4 * (i))
#define GSTR(p) ((char *)(MEM + (p)))
#define GWSTR(p) ((wchar_t *)(MEM + (p)))
#define RET(v) do { EAX = (uint32_t)(v); ESP += 4; return; } while (0)
#define RETF(v) do { FPUSH((double)(v)); ESP += 4; return; } while (0)

/* ------------------------------------------------------------ FILE mapping */
#define MAX_FILES 64
static struct { uint32_t g; FILE *h; } files[MAX_FILES];
static uint32_t sF;   /* guest ___sF: stdin, stdout, stderr (88 bytes each) */

static FILE *hostfile(uint32_t g) {
    for (int k = 0; k < MAX_FILES; k++) if (files[k].g == g) return files[k].h;
    return NULL;
}
static uint32_t newfile(FILE *h) {
    if (!h) return 0;
    for (int k = 0; k < MAX_FILES; k++)
        if (!files[k].g) { files[k].g = misc_alloc(88); files[k].h = h; return files[k].g; }
    trap(0, "too many open files");
}

/* ------------------------------------------------------------ printf engine */
/* Formats guest format string `fmt` with guest varargs at `ap` into a host buffer. */
static size_t gfmt(char *out, size_t cap, const char *fmt, uint32_t ap, int wide_fmt) {
    size_t n = 0;
    #define EMIT(s) do { size_t _l = strlen(s); if (n + _l < cap) { memcpy(out + n, s, _l); } n += _l; } while (0)
    for (const char *p = fmt; *p; ) {
        if (*p != '%') { char c[2] = { *p++, 0 }; EMIT(c); continue; }
        char spec[32]; int k = 0; spec[k++] = *p++;
        while (*p && strchr("-+ #0", *p) && k < 20) spec[k++] = *p++;
        if (*p == '*') { k += snprintf(spec + k, sizeof spec - k, "%d", (int32_t)RD32(ap)); ap += 4; p++; }
        while (*p >= '0' && *p <= '9' && k < 24) spec[k++] = *p++;
        if (*p == '.') {
            spec[k++] = *p++;
            if (*p == '*') { k += snprintf(spec + k, sizeof spec - k, "%d", (int32_t)RD32(ap)); ap += 4; p++; }
            while (*p >= '0' && *p <= '9' && k < 28) spec[k++] = *p++;
        }
        int lmod = 0, hmod = 0;
        while (*p && strchr("hlLqjzt", *p)) { if (*p == 'l' || *p == 'q' || *p == 'L') lmod++; if (*p == 'h') hmod++; p++; }
        char conv = *p ? *p++ : 0; char buf[1024];
        buf[0] = 0;
        switch (conv) {
        case '%': strcpy(buf, "%"); break;
        case 'd': case 'i': {
            if (lmod >= 2) { uint64_t v = RD64(ap); ap += 8; spec[k++] = 'l'; spec[k++] = 'l'; spec[k++] = 'd'; spec[k] = 0; snprintf(buf, sizeof buf, spec, (long long)v); }
            else { int32_t v = (int32_t)RD32(ap); ap += 4; spec[k++] = 'd'; spec[k] = 0; snprintf(buf, sizeof buf, spec, v); }
            break; }
        case 'u': case 'x': case 'X': case 'o': {
            if (lmod >= 2) { uint64_t v = RD64(ap); ap += 8; spec[k++] = 'l'; spec[k++] = 'l'; spec[k++] = conv; spec[k] = 0; snprintf(buf, sizeof buf, spec, (unsigned long long)v); }
            else { uint32_t v = RD32(ap); ap += 4; spec[k++] = conv; spec[k] = 0; snprintf(buf, sizeof buf, spec, v); }
            break; }
        case 'c': { uint32_t v = RD32(ap); ap += 4;
            if (wide_fmt || lmod) { char mb[8]; int l = wctomb(mb, (wchar_t)v); mb[l > 0 ? l : 0] = 0; spec[k++] = 's'; spec[k] = 0; snprintf(buf, sizeof buf, spec, mb); }
            else { spec[k++] = 'c'; spec[k] = 0; snprintf(buf, sizeof buf, spec, (int)(v & 0xff)); }
            break; }
        case 's': case 'S': { uint32_t v = RD32(ap); ap += 4;
            int wide = conv == 'S' || lmod || (wide_fmt && !hmod);
            if (!v) { strcpy(buf, "(null)"); break; }
            if (wide) { spec[k++] = 'l'; spec[k++] = 's'; spec[k] = 0; snprintf(buf, sizeof buf, spec, GWSTR(v)); }
            else { spec[k++] = 's'; spec[k] = 0; snprintf(buf, sizeof buf, spec, GSTR(v)); }
            break; }
        case 'f': case 'F': case 'e': case 'E': case 'g': case 'G': {
            double v = RDF64(ap); ap += 8; spec[k++] = conv; spec[k] = 0; snprintf(buf, sizeof buf, spec, v); break; }
        case 'p': { uint32_t v = RD32(ap); ap += 4; snprintf(buf, sizeof buf, "0x%x", v); break; }
        case 'n': ap += 4; break;
        default: break;
        }
        EMIT(buf);
    }
    if (cap) out[n < cap ? n : cap - 1] = 0;
    return n;
    #undef EMIT
}

/* wide format: convert the guest wide format to multibyte, format, convert back */
static size_t gwfmt(wchar_t *out, size_t cap, const wchar_t *wfmt, uint32_t ap) {
    char fmt[4096], tmp[8192];
    wcstombs(fmt, wfmt, sizeof fmt - 1); fmt[sizeof fmt - 1] = 0;
    gfmt(tmp, sizeof tmp, fmt, ap, 1);
    size_t n = mbstowcs(out, tmp, cap ? cap - 1 : 0);
    if (n == (size_t)-1) n = 0;
    if (cap) out[n] = 0;
    return n;
}

static void guest_write(uint32_t gfile, const char *s, size_t n) {
    FILE *f = hostfile(gfile);
    if (!f) f = stderr;
    if (f == stderr && !debug_enabled && n >= 6 && !strncmp(s, "DEBUG:", 6)) return;
    fwrite(s, 1, n, f);
}

/* ------------------------------------------------------------ libc shims */
void imp_malloc(void)  { RET(g_malloc(ARG(0))); }
void imp_Znwm(void)    { RET(g_malloc(ARG(0))); }
void imp_Znam(void)    { RET(g_malloc(ARG(0))); }
void imp_calloc(void)  { uint32_t n = ARG(0) * ARG(1); uint32_t a = g_malloc(n); memset(MEM + a, 0, n); RET(a); }
void imp_realloc(void) {
    uint32_t old = ARG(0), n = ARG(1), a = g_malloc(n);
    if (old) { uint32_t on = RD32(old - 16); memcpy(MEM + a, MEM + old, on < n ? on : n); }
    RET(a);
}
void imp_free(void)  { RET(0); }
void imp_ZdlPv(void) { RET(0); }
void imp_ZdaPv(void) { RET(0); }
void imp_memcpy(void) { memmove(MEM + ARG(0), MEM + ARG(1), ARG(2)); RET(ARG(0)); }
void imp_memset(void) { memset(MEM + ARG(0), (int)ARG(1), ARG(2)); RET(ARG(0)); }
void imp_strcpy(void) { strcpy(GSTR(ARG(0)), GSTR(ARG(1))); RET(ARG(0)); }
void imp_strncpy(void) { strncpy(GSTR(ARG(0)), GSTR(ARG(1)), ARG(2)); RET(ARG(0)); }
void imp_strcat(void) { strcat(GSTR(ARG(0)), GSTR(ARG(1))); RET(ARG(0)); }
void imp_strcmp(void) { RET(strcmp(GSTR(ARG(0)), GSTR(ARG(1)))); }
void imp_strncmp(void) { RET(strncmp(GSTR(ARG(0)), GSTR(ARG(1)), ARG(2))); }
void imp_strcasecmp(void) { RET(strcasecmp(GSTR(ARG(0)), GSTR(ARG(1)))); }
void imp_strstr(void) { char *r = strstr(GSTR(ARG(0)), GSTR(ARG(1))); RET(r ? (uint32_t)((uint8_t *)r - MEM) : 0); }
void imp_strerror(void) { static uint32_t g; if (!g) g = misc_alloc(128);
    snprintf(GSTR(g), 128, "%s", strerror((int)ARG(0))); RET(g); }
void imp_atoi(void) { RET(atoi(GSTR(ARG(0)))); }
void imp_strtol(void) { char *e; long v = strtol(GSTR(ARG(0)), &e, (int)ARG(2));
    if (ARG(1)) WR32(ARG(1), (uint32_t)((uint8_t *)e - MEM)); RET((uint32_t)(int32_t)v); }
void imp_strtoul(void) { char *e; unsigned long v = strtoul(GSTR(ARG(0)), &e, (int)ARG(2));
    if (ARG(1)) WR32(ARG(1), (uint32_t)((uint8_t *)e - MEM)); RET((uint32_t)v); }
void imp_tolower(void) { RET(tolower((int)ARG(0))); }
void imp_isprint(void) { int c = (int)ARG(0); RET(c >= 32 && c < 127); }
void imp_isxdigit(void) { RET(isxdigit((int)ARG(0) & 0xff) != 0); }
void imp_getenv(void) {
    const char *v = getenv(GSTR(ARG(0)));
    RET(v ? guest_strdup(v) : 0);
}
static uint32_t errno_addr;
void imp_error(void) { RET(errno_addr); }   /* ___error() */
void imp_sprintf(void) { char buf[16384]; size_t n = gfmt(buf, sizeof buf, GSTR(ARG(1)), ESP + 12, 0); strcpy(GSTR(ARG(0)), buf); RET(n); }
void imp_vsprintf(void) { char buf[16384]; size_t n = gfmt(buf, sizeof buf, GSTR(ARG(1)), ARG(2), 0); strcpy(GSTR(ARG(0)), buf); RET(n); }
void imp_swprintf(void) { size_t n = gwfmt(GWSTR(ARG(0)), ARG(1), GWSTR(ARG(2)), ESP + 16); RET(n); }
void imp_fprintf(void) { char buf[16384]; size_t n = gfmt(buf, sizeof buf, GSTR(ARG(1)), ESP + 12, 0); guest_write(ARG(0), buf, n); RET(n); }
void imp_vfprintf(void) { char buf[16384]; size_t n = gfmt(buf, sizeof buf, GSTR(ARG(1)), ARG(2), 0); guest_write(ARG(0), buf, n); RET(n); }
void imp_puts(void) { if (debug_enabled) { fputs(GSTR(ARG(0)), stderr); fputc('\n', stderr); } RET(0); }
void imp_putchar(void) { fputc((int)ARG(0), stdout); RET(ARG(0) & 0xff); }
void imp_mbstowcs(void) { RET(mbstowcs(ARG(0) ? GWSTR(ARG(0)) : NULL, GSTR(ARG(1)), ARG(2))); }
void imp_mbtowc(void) { if (!ARG(1)) RET(0); wchar_t w; int r = mbtowc(&w, GSTR(ARG(1)), ARG(2)); if (r >= 0 && ARG(0)) WR32(ARG(0), (uint32_t)w); RET(r); }
void imp_wcslen(void) { RET(wcslen(GWSTR(ARG(0)))); }
void imp_wcscpy(void) { wcscpy(GWSTR(ARG(0)), GWSTR(ARG(1))); RET(ARG(0)); }
void imp_wcsncpy(void) { wcsncpy(GWSTR(ARG(0)), GWSTR(ARG(1)), ARG(2)); RET(ARG(0)); }
void imp_wcscat(void) { wcscat(GWSTR(ARG(0)), GWSTR(ARG(1))); RET(ARG(0)); }
void imp_wcsncat(void) { wcsncat(GWSTR(ARG(0)), GWSTR(ARG(1)), ARG(2)); RET(ARG(0)); }
void imp_wcscmp(void) { RET(wcscmp(GWSTR(ARG(0)), GWSTR(ARG(1)))); }
void imp_wcsrchr(void) { wchar_t *r = wcsrchr(GWSTR(ARG(0)), (wchar_t)ARG(1)); RET(r ? (uint32_t)((uint8_t *)r - MEM) : 0); }
static uint32_t rand_state = 1;            /* deterministic, matches the reference emulator */
void imp_srand(void) { rand_state = ARG(0); RET(0); }
void imp_rand(void) { rand_state = (rand_state * 1103515245u + 12345u) & 0x7fffffffu; RET(rand_state); }
void imp_time(void) { uint32_t t = (uint32_t)time(NULL); if (ARG(0)) WR32(ARG(0), t); RET(t); }
void imp_ctime(void) { static uint32_t g; if (!g) g = misc_alloc(64); time_t t = (time_t)RD32(ARG(0));
    snprintf(GSTR(g), 64, "%s", ctime(&t)); RET(g); }
static void put_tm(uint32_t g, struct tm *tm) {
    int32_t v[9] = { tm->tm_sec, tm->tm_min, tm->tm_hour, tm->tm_mday, tm->tm_mon, tm->tm_year, tm->tm_wday, tm->tm_yday, tm->tm_isdst };
    memcpy(MEM + g, v, sizeof v);
}
void imp_gmtime(void) { static uint32_t g; if (!g) g = misc_alloc(64); time_t t = (time_t)RD32(ARG(0)); put_tm(g, gmtime(&t)); RET(g); }
void imp_localtime(void) { static uint32_t g; if (!g) g = misc_alloc(64); time_t t = (time_t)RD32(ARG(0)); put_tm(g, localtime(&t)); RET(g); }
void imp_sleep(void) { RET(0); }
void imp_sigset(void) { RET(0); }
void imp_exit(void) { fflush(stdout); exit((int)ARG(0)); }
static const char *remap(const char *path, char *buf, size_t cap);
void imp_access(void) { char buf[1024]; RET(access(remap(GSTR(ARG(0)), buf, sizeof buf), (int)ARG(1)) == 0 ? 0 : (uint32_t)-1); }
void imp_dlopen(void) { RET(0); }
void imp_dlsym(void) { RET(0); }
void imp_pow(void) { RETF(pow(ARGD(0), ARGD(2))); }
void imp_sin(void) { RETF(sin(ARGD(0))); }
void imp_cos(void) { RETF(cos(ARGD(0))); }
void imp_atan2(void) { RETF(atan2(ARGD(0), ARGD(2))); }
void imp_log10(void) { RETF(log10(ARGD(0))); }

/* files */
#ifndef HDP5000_DATADIR
#define HDP5000_DATADIR "/Library/Printers/Fargo/HDP5000"
#endif
/* The 2009 driver installed its data under /usr/share (read-only on modern macOS). */
static const char *remap(const char *path, char *buf, size_t cap) {
    static const char *const from[] = { "/usr/share/cups/profiles/", "/usr/share/fargo/HDP5000/" };
    static const char *const to[] = { "profiles/", "" };
    const char *dir = getenv("HDP5000_DATADIR"); if (!dir) dir = HDP5000_DATADIR;
    for (int k = 0; k < 2; k++)
        if (!strncmp(path, from[k], strlen(from[k]))) {
            snprintf(buf, cap, "%s/%s%s", dir, to[k], path + strlen(from[k])); return buf;
        }
    return path;
}
void imp_fopen(void) {
    char buf[1024];
    const char *path = remap(GSTR(ARG(0)), buf, sizeof buf), *mode = GSTR(ARG(1));
    if (!strncmp(path, "/var/log/", 9) && (strchr(mode, 'w') || strchr(mode, 'a')))
        RET(newfile(debug_enabled ? fdopen(dup(2), "w") : fopen("/dev/null", "w")));
    RET(newfile(fopen(path, mode)));
}
void imp_tmpfile(void) { RET(newfile(tmpfile())); }
void imp_fclose(void) {
    uint32_t g = ARG(0);
    for (int k = 0; k < MAX_FILES; k++)
        if (files[k].g == g) { if (files[k].h != stdout && files[k].h != stderr && files[k].h != stdin) fclose(files[k].h); files[k].g = 0; files[k].h = NULL; }
    RET(0);
}
void imp_fflush(void) { FILE *f = hostfile(ARG(0)); if (f) fflush(f); RET(0); }
void imp_fileno(void) { FILE *f = hostfile(ARG(0)); RET(f ? fileno(f) : (uint32_t)-1); }
void imp_fchmod(void) { RET(0); }
void imp_fwrite(void) { FILE *f = hostfile(ARG(3)); size_t n = f ? fwrite(MEM + ARG(0), ARG(1), ARG(2), f) : 0; RET(n); }
void imp_fread(void) { FILE *f = hostfile(ARG(3)); size_t n = f ? fread(MEM + ARG(0), ARG(1), ARG(2), f) : 0; RET(n); }
void imp_fseek(void) { FILE *f = hostfile(ARG(0)); RET(f ? fseek(f, (int32_t)ARG(1), (int)ARG(2)) : -1); }
void imp_ftell(void) { FILE *f = hostfile(ARG(0)); RET(f ? (uint32_t)ftell(f) : (uint32_t)-1); }
void imp_fputc(void) { FILE *f = hostfile(ARG(1)); if (f) fputc((int)ARG(0), f); RET(ARG(0) & 0xff); }
void imp_fputs(void) { const char *s = GSTR(ARG(0)); guest_write(ARG(1), s, strlen(s)); RET(0); }
void imp_open(void) { char buf[1024]; RET(open(remap(GSTR(ARG(0)), buf, sizeof buf), (int)ARG(1) & 3)); }
void imp_close(void) { RET(close((int)ARG(0))); }
void imp_read(void) { RET(read((int)ARG(0), MEM + ARG(1), ARG(2))); }

/* ------------------------------------------------------------ CUPS shims */
static cups_raster_t *raster;
void imp_cupsRasterOpen(void) { raster = cupsRasterOpen((int)ARG(0), CUPS_RASTER_READ); RET(raster ? 0x4242 : 0); }
void imp_cupsRasterClose(void) { if (raster) cupsRasterClose(raster); raster = NULL; RET(0); }
void imp_cupsRasterReadHeader(void) {
    cups_page_header2_t h;
    if (!raster || !cupsRasterReadHeader2(raster, &h)) RET(0);
    /* the v1 header (420 bytes) is a layout-identical prefix of the v2 header */
    memcpy(MEM + ARG(1), &h, 420);
    RET(1);
}
void imp_cupsRasterReadPixels(void) { RET(raster ? cupsRasterReadPixels(raster, MEM + ARG(1), ARG(2)) : 0); }

static int num_opts; static cups_option_t *opts;
void imp_cupsParseOptions(void) {
    num_opts = cupsParseOptions(ARG(0) ? GSTR(ARG(0)) : "", 0, &opts);
    WR32(ARG(2), 0x1234); RET(num_opts);
}
void imp_cupsGetOption(void) {
    const char *v = cupsGetOption(GSTR(ARG(0)), num_opts, opts);
    RET(v ? guest_strdup(v) : 0);
}

/* PPD: only option defaults are needed (guest ppd_option_t: keyword @1, defchoice @42) */
#define MAX_PPD_OPTS 256
static struct { char key[41]; char def[41]; uint32_t g; } ppd_opts[MAX_PPD_OPTS];
static int n_ppd_opts;
void imp_ppdOpenFile(void) {
    FILE *f = fopen(GSTR(ARG(0)), "r");
    if (!f) RET(0);
    char line[1024]; n_ppd_opts = 0;
    while (fgets(line, sizeof line, f) && n_ppd_opts < MAX_PPD_OPTS) {
        if (strncmp(line, "*Default", 8)) continue;
        char *colon = strchr(line, ':'); if (!colon) continue;
        *colon = 0; char *v = colon + 1;
        while (*v == ' ' || *v == '\t') v++;
        v[strcspn(v, "\r\n")] = 0;
        snprintf(ppd_opts[n_ppd_opts].key, 41, "%s", line + 8);
        snprintf(ppd_opts[n_ppd_opts].def, 41, "%s", v);
        ppd_opts[n_ppd_opts].g = 0; n_ppd_opts++;
    }
    fclose(f);
    RET(misc_alloc(256));
}
void imp_ppdFindOption(void) {
    const char *k = GSTR(ARG(1));
    for (int i = 0; i < n_ppd_opts; i++)
        if (!strcasecmp(ppd_opts[i].key, k)) {
            if (!ppd_opts[i].g) {
                uint32_t g = misc_alloc(256);
                strcpy(GSTR(g + 1), ppd_opts[i].key); strcpy(GSTR(g + 42), ppd_opts[i].def);
                ppd_opts[i].g = g;
            }
            RET(ppd_opts[i].g);
        }
    RET(0);
}
void imp_ppdClose(void) { RET(0); }

/* ------------------------------------------------------------ C++ runtime shims */
void imp_keymgr_dwarf2_register_sections(void) { RET(0); }
void imp_keymgr_get_and_lock_processwide_ptr(void) { RET(0); }
void imp_keymgr_get_and_lock_processwide_ptr_2(void) { RET(0); }
void imp_keymgr_set_and_unlock_processwide_ptr(void) { RET(0); }
void imp_cxa_begin_catch(void) { trap(0, "C++ exception (begin_catch)"); }
void imp_cxa_end_catch(void) { RET(0); }
void imp_cxa_rethrow(void) { trap(0, "C++ exception (rethrow)"); }
void imp_cxa_call_unexpected(void) { trap(0, "C++ exception (unexpected)"); }
void imp_Unwind_Resume(void) { trap(0, "C++ exception (unwind)"); }
void imp_ZN9__gnu_cxx18__exchange_and_addEPVii(void) { uint32_t p = ARG(0), old = RD32(p); WR32(p, old + ARG(1)); RET(old); }
/* GCC 4.0 COW std::string: object holds char*; rep {len, cap, refcount} precedes chars */
static uint32_t str_new(const uint8_t *b, uint32_t n) {
    uint32_t rep = g_malloc(12 + n + 1);
    WR32(rep, n); WR32(rep + 4, n); WR32(rep + 8, 0); memcpy(MEM + rep + 12, b, n); MEM[rep + 12 + n] = 0;
    return rep + 12;
}
static void str_append(uint32_t obj, const uint8_t *b, uint32_t n) {
    uint32_t p = RD32(obj), len = RD32(p - 12);
    uint8_t *tmp = malloc(len + n + 1); memcpy(tmp, MEM + p, len); memcpy(tmp + len, b, n);
    WR32(obj, str_new(tmp, len + n)); free(tmp);
}
void imp_ZNSsC1EPKcRKSaIcE(void) { const char *s = GSTR(ARG(1)); WR32(ARG(0), str_new((const uint8_t *)s, (uint32_t)strlen(s))); RET(0); }
void imp_ZNSs6appendEPKcm(void) { str_append(ARG(0), MEM + ARG(1), ARG(2)); RET(ARG(0)); }
void imp_ZNSs6appendERKSs(void) { uint32_t p = RD32(ARG(1)); str_append(ARG(0), MEM + p, RD32(p - 12)); RET(ARG(0)); }
void imp_ZNSs6assignEPKcm(void) { WR32(ARG(0), str_new(MEM + ARG(1), ARG(2))); RET(ARG(0)); }
void imp_ZNSs7reserveEm(void) { RET(0); }
void imp_ZNSs4_Rep10_M_destroyERKSaIcE(void) { RET(0); }
void imp_ZNSt15_List_node_base4hookEPS_(void) {
    uint32_t node = ARG(0), pos = ARG(1), prev = RD32(pos + 4);
    WR32(node, pos); WR32(node + 4, prev); WR32(prev, node); WR32(pos + 4, node); RET(0);
}
void imp_ZNSt15_List_node_base6unhookEv(void) {
    uint32_t node = ARG(0), nx = RD32(node), pv = RD32(node + 4);
    WR32(pv, nx); WR32(nx + 4, pv); RET(0);
}
/* red-black tree node: color @0, parent @4, left @8, right @12 */
#define P(x) RD32((x) + 4)
#define L(x) RD32((x) + 8)
#define Rr(x) RD32((x) + 12)
void imp_ZSt18_Rb_tree_incrementPSt18_Rb_tree_node_base(void) {
    uint32_t x = ARG(0);
    if (Rr(x)) { x = Rr(x); while (L(x)) x = L(x); }
    else { uint32_t y = P(x); while (x == Rr(y)) { x = y; y = P(y); } if (Rr(x) != y) x = y; }
    RET(x);
}
void imp_ZSt18_Rb_tree_decrementPSt18_Rb_tree_node_base(void) {
    uint32_t x = ARG(0);
    if (RD32(x) == 0 && P(P(x)) == x) RET(Rr(x));
    if (L(x)) { uint32_t y = L(x); while (Rr(y)) y = Rr(y); RET(y); }
    uint32_t y = P(x); while (x == L(y)) { x = y; y = P(y); } RET(y);
}
static uint32_t rb_root_slot;
static void rb_rot_left(uint32_t x) {
    uint32_t y = Rr(x); WR32(x + 12, L(y));
    if (L(y)) WR32(L(y) + 4, x);
    WR32(y + 4, P(x));
    if (x == RD32(rb_root_slot)) WR32(rb_root_slot, y);
    else if (x == L(P(x))) WR32(P(x) + 8, y); else WR32(P(x) + 12, y);
    WR32(y + 8, x); WR32(x + 4, y);
}
static void rb_rot_right(uint32_t x) {
    uint32_t y = L(x); WR32(x + 8, Rr(y));
    if (Rr(y)) WR32(Rr(y) + 4, x);
    WR32(y + 4, P(x));
    if (x == RD32(rb_root_slot)) WR32(rb_root_slot, y);
    else if (x == Rr(P(x))) WR32(P(x) + 12, y); else WR32(P(x) + 8, y);
    WR32(y + 12, x); WR32(x + 4, y);
}
void imp_ZSt29_Rb_tree_insert_and_rebalancebPSt18_Rb_tree_node_baseS0_RS_(void) {
    uint32_t left = ARG(0), x = ARG(1), p = ARG(2), header = ARG(3);
    enum { RED = 0, BLACK = 1 };
    WR32(x + 4, p); WR32(x + 8, 0); WR32(x + 12, 0); WR32(x, RED);
    if (left) {
        WR32(p + 8, x);
        if (p == header) { WR32(header + 4, x); WR32(header + 12, x); }
        else if (p == L(header)) WR32(header + 8, x);
    } else {
        WR32(p + 12, x);
        if (p == Rr(header)) WR32(header + 12, x);
    }
    rb_root_slot = header + 4;
    while (x != RD32(rb_root_slot) && RD32(P(x)) == RED) {
        uint32_t xp = P(x), xpp = P(xp);
        if (xp == L(xpp)) {
            uint32_t y = Rr(xpp);
            if (y && RD32(y) == RED) { WR32(xp, BLACK); WR32(y, BLACK); WR32(xpp, RED); x = xpp; }
            else {
                if (x == Rr(xp)) { x = xp; rb_rot_left(x); xp = P(x); xpp = P(xp); }
                WR32(xp, BLACK); WR32(xpp, RED); rb_rot_right(xpp);
            }
        } else {
            uint32_t y = L(xpp);
            if (y && RD32(y) == RED) { WR32(xp, BLACK); WR32(y, BLACK); WR32(xpp, RED); x = xpp; }
            else {
                if (x == L(xp)) { x = xp; rb_rot_right(x); xp = P(x); xpp = P(xp); }
                WR32(xp, BLACK); WR32(xpp, RED); rb_rot_left(xpp);
            }
        }
    }
    WR32(RD32(rb_root_slot), BLACK);
    RET(0);
}

/* ------------------------------------------------------------ startup */
static void guest_call(uint32_t fn, int argc, const uint32_t *argv) {
    uint32_t sentinel_esp = ESP;
    for (int k = argc - 1; k >= 0; k--) PUSH(argv[k]);
    PUSH(0xdeadbeefu);           /* fake return address */
    call_addr(fn);
    ESP = sentinel_esp;
}

int main(int argc, char **argv) {
    debug_enabled = getenv("HDP5000_DEBUG") != NULL;
    MEM = mmap(NULL, 1ull << 32, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0);
    if (MEM == MAP_FAILED) { perror("ERROR: mmap"); return 1; }
    memcpy(MEM + IMAGE_BASE, IMAGE_DATA, IMAGE_SIZE);
    ESP = STACK_TOP - 0x1000;

    sF = misc_alloc(88 * 3);
    files[0].g = sF; files[0].h = stdin;
    files[1].g = sF + 88; files[1].h = stdout;
    files[2].g = sF + 176; files[2].h = stderr;
    errno_addr = misc_alloc(16);
    uint32_t empty_rep = misc_alloc(64);
    for (int k = 0; k < NL_PTR_COUNT; k++) {
        const char *n = NL_PTR_NAME[k]; uint32_t v = NL_PTR_LOCAL[k];
        if (!strcmp(n, "___sF")) v = sF;
        else if (!strcmp(n, "_errno")) v = errno_addr;
        else if (!strcmp(n, "__ZNSs4_Rep20_S_empty_rep_storageE")) v = empty_rep;
        else if (!strcmp(n, "__ZNSs4_Rep11_S_terminalE")) v = empty_rep + 12;
        WR32(NL_PTR_ADDR[k], v);
    }
    for (int k = 0; INIT_FUNCS[k]; k++) guest_call(INIT_FUNCS[k], 0, NULL);

    /* argv/envp in guest memory */
    uint32_t gargv = misc_alloc(4 * (argc + 1));
    for (int k = 0; k < argc; k++) WR32(gargv + 4 * k, guest_strdup(argv[k]));
    uint32_t genvp = misc_alloc(4);
    uint32_t args[3] = { (uint32_t)argc, gargv, genvp };
    guest_call(MAIN_ADDR, 3, args);
    fflush(stdout);
    return (int)EAX;
}
