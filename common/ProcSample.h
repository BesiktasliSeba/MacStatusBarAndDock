// ProcSample.h -- the per-process arithmetic behind our Activity Monitor feature (the process list it shows), kept as plain C so the Mac test
// (tools/test-procsample.c) runs this very code. No system calls here: the feature feeds it numbers it has already read, the same way
// common/SystemStats.h holds the whole-device memory/CPU maths for the RAM & CPU tile.
//
// macOS's Activity Monitor shows each process's "% CPU": the share of one core the process used between two refreshes. We compute it the same way,
// from the process's cumulative CPU time (user + system, in nanoseconds, as proc_pid_rusage reports it) at two moments and the wall-clock time
// between them. 100% is one core fully busy; a process using several cores at once reads above 100%, exactly as Activity Monitor shows it.
#ifndef MSBD_PROC_SAMPLE_H
#define MSBD_PROC_SAMPLE_H
#include <stdint.h>
#include <stdbool.h>
#include <stdio.h>

// %CPU of ONE core between two cumulative CPU-time readings (nanoseconds) over a wall interval (nanoseconds). Returns -1 when the two readings do
// not make a measurement: no time passed, or the counter went backwards (a process that exited and a new one took its pid between samples).
static inline double MSBDProcCPUPercent(uint64_t cpuNsThen, uint64_t cpuNsNow, uint64_t wallNsBetween) {
    if (wallNsBetween == 0 || cpuNsNow < cpuNsThen) return -1.0;
    return (double)(cpuNsNow - cpuNsThen) * 100.0 / (double)wallNsBetween;
}

// A whole process's CPU time from the two halves proc_pid_rusage gives (ri_user_time + ri_system_time), both nanoseconds.
static inline uint64_t MSBDProcCPUTime(uint64_t userNs, uint64_t systemNs) { return userNs + systemNs; }

// Activity Monitor writes "% CPU" with one decimal (e.g. "4.3", "127.0"), and "0.0" for an idle process. Into buf.
static inline void MSBDFormatPercent(double percent, char *buf, size_t size) {
    if (percent < 0.0) { snprintf(buf, size, "-"); return; }
    snprintf(buf, size, "%.1f", percent);
}

// mach_absolute_time ticks -> nanoseconds, given the timebase (numer/denom from mach_timebase_info). Pure so the Mac test can check it; the device
// passes its own timebase. On Apple silicon numer==denom==1 (ticks are already nanoseconds), but we never assume that.
static inline uint64_t MSBDMachTicksToNs(uint64_t ticks, uint32_t numer, uint32_t denom) {
    if (denom == 0) return 0;
    return ticks * (uint64_t)numer / (uint64_t)denom;
}

// A process's name (len bytes at in, or up to a NUL) as UTF-8 that is always valid, into out (always NUL-terminated; returns the bytes written).
// The kernel's short name (p_comm, the name when proc_pidpath can't be read) is cut at 16 bytes and can end inside a character of several bytes,
// and a path's bytes need not be UTF-8 at all: Foundation reads either as no string (nil), and one nil name in the window's row arrays threw inside
// SpringBoard. So a character cut at the end is left out, and anything else that is not UTF-8 becomes one U+FFFD (the replacement character) per
// broken sequence, as a Mac's lossy reading shows it. Well-formed UTF-8 is copied as it is. out holds 3 * len + 1 bytes at most (every byte broken).
static inline size_t MSBDProcNameUTF8(const char *in, size_t len, char *out, size_t size) {
    if (!out || !size) return 0;
    const unsigned char *s = (const unsigned char *)in;
    size_t i = 0, o = 0;
    while (s && i < len && s[i]) {
        unsigned c = s[i]; size_t n = 0; unsigned lo = 0x80, hi = 0xBF;   // (the sequence's length; the allowed range of its second byte)
        if (c < 0x80) n = 1;
        else if (c >= 0xC2 && c <= 0xDF) n = 2;
        else if (c == 0xE0) { n = 3; lo = 0xA0; }                          // (no overlong forms)
        else if ((c >= 0xE1 && c <= 0xEC) || c == 0xEE || c == 0xEF) n = 3;
        else if (c == 0xED) { n = 3; hi = 0x9F; }                          // (no UTF-16 surrogates)
        else if (c == 0xF0) { n = 4; lo = 0x90; }
        else if (c >= 0xF1 && c <= 0xF3) n = 4;
        else if (c == 0xF4) { n = 4; hi = 0x8F; }                          // (nothing past U+10FFFF)
        size_t k = n ? 1 : 0;   // (how many bytes of it are well-formed)
        while (k && k < n && i + k < len && s[i + k] && s[i + k] >= (k == 1 ? lo : 0x80) && s[i + k] <= (k == 1 ? hi : 0xBF)) k++;
        if (n && k == n) {
            if (o + n >= size) break;   // (no room for the whole character: the name ends before it)
            for (size_t j = 0; j < n; j++) out[o++] = (char)s[i + j];
            i += n;
            continue;
        }
        if (k && (i + k >= len || !s[i + k])) break;   // (the start of a character cut off at the end: left out)
        if (o + 3 >= size) break;
        out[o++] = (char)0xEF; out[o++] = (char)0xBF; out[o++] = (char)0xBD;   // (U+FFFD)
        i += k ? k : 1;
    }
    out[o] = 0;
    return o;
}

#endif
