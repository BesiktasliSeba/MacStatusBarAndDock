// SystemStats.h -- the memory and CPU numbers our Control Center tiles show (the RAM & CPU module, ccmodule/; the tile drawn over Memory Magic,
// statusbar/StatusBar.x), plain C so the Mac test (tools/test-systemstats.sh) runs this very code. One definition everywhere:
//  - Available RAM = the free, inactive and speculative pages, counted themselves: what apps can get without anything being compressed or
//    quit. Used = the rest of the physical memory (active, wired, the compressor's). Taken as total minus active + wired + compressed until
//    1.7.6, that read 1.2 GB too little on the M1 (15.6.1) from 31 Oct: after a jetsam storm its kernel's wired count stayed 81k pages above
//    what the iPad has (every counter together 1.24 GiB over its memory, the other iPads within 0.1 %), so a counter's error never moves
//    Available now. Memory Magic's "Free RAM" is only the free pages (~700 MB on the 17.5 iPad while about 1.7-1.8 GB were available),
//    which is why ours differs from it.
//  - CPU = busy ticks (user + system + nice) over all ticks between two samples, every core together; user and system on their own too.
#ifndef MSBD_SYSTEM_STATS_H
#define MSBD_SYSTEM_STATS_H
#include <stdint.h>
#include <stdbool.h>
#include <sys/sysctl.h>
#include <mach/mach.h>
#include <mach/mach_host.h>

typedef struct {
    uint64_t total, used, available, wired, compressed, active, inactive, freeBytes;   // bytes
} MSBDMemory;

// From page counts (pure: the Mac test feeds it numbers). total = the physical memory in bytes, page = the size of a counted page, freeCount =
// the free pages without the speculative ones (as vm_stat's "Pages free" prints them; MSBDFreeWithoutSpeculative).
static inline MSBDMemory MSBDMemoryFromCounts(uint64_t total, uint64_t page, uint64_t active, uint64_t inactive, uint64_t speculative, uint64_t wired, uint64_t compressed, uint64_t freeCount) {
    MSBDMemory m = {0};
    m.total = total;
    m.active = active * page; m.inactive = inactive * page; m.wired = wired * page; m.compressed = compressed * page; m.freeBytes = freeCount * page;
    uint64_t available = m.freeBytes + m.inactive + speculative * page;
    m.available = available < total ? available : total;
    m.used = total - m.available;
    return m;
}
// The kernel's free_count already holds the speculative pages (vm_stat takes them out before it prints "Pages free"): counted again beside
// speculative they made Available 1.3-1.4 GB too large on the M1 (1.7.7 code review, part two).
static inline uint64_t MSBDFreeWithoutSpeculative(uint64_t freeCount, uint64_t speculative) { return freeCount > speculative ? freeCount - speculative : 0; }
static inline bool MSBDMemoryNow(MSBDMemory *out) {
    vm_statistics64_data_t vm; mach_msg_type_number_t n = HOST_VM_INFO64_COUNT;
    mach_port_t host = mach_host_self();
    kern_return_t kr = host_statistics64(host, HOST_VM_INFO64, (host_info64_t)&vm, &n);
    mach_port_deallocate(mach_task_self(), host);
    if (kr != KERN_SUCCESS) return false;
    uint64_t total = 0; size_t len = sizeof(total);
    if (sysctlbyname("hw.memsize", &total, &len, NULL, 0) != 0 || !total) return false;
    uint64_t page = vm_kernel_page_size;   // (the counters are in kernel pages)
    if (!page) return false;
    *out = MSBDMemoryFromCounts(total, page, vm.active_count, vm.inactive_count, vm.speculative_count, vm.wire_count, vm.compressor_page_count, MSBDFreeWithoutSpeculative(vm.free_count, vm.speculative_count));
    return true;
}

typedef struct { uint64_t user, system, nice, idle; unsigned cores; } MSBDCPUTicks;
static inline bool MSBDCPUTicksNow(MSBDCPUTicks *t) {
    processor_info_array_t info = NULL; mach_msg_type_number_t count = 0; natural_t cores = 0;
    mach_port_t host = mach_host_self();
    kern_return_t kr = host_processor_info(host, PROCESSOR_CPU_LOAD_INFO, &cores, &info, &count);
    mach_port_deallocate(mach_task_self(), host);
    if (kr != KERN_SUCCESS || !info) return false;
    MSBDCPUTicks s = {0};
    for (natural_t i = 0; i < cores; i++) {
        integer_t *c = info + i * CPU_STATE_MAX;
        s.user += (uint32_t)c[CPU_STATE_USER]; s.system += (uint32_t)c[CPU_STATE_SYSTEM]; s.nice += (uint32_t)c[CPU_STATE_NICE]; s.idle += (uint32_t)c[CPU_STATE_IDLE];
    }
    s.cores = cores;
    vm_deallocate(mach_task_self(), (vm_address_t)info, count * sizeof(integer_t));
    *t = s;
    return true;
}
// The load between two samples, 0...1 (user and system on their own when asked); -1 when the samples do not make one (no time between them,
// a counter that went back -- a core went to sleep and its counters were reset).
static inline double MSBDCPULoadBetween(MSBDCPUTicks a, MSBDCPUTicks b, double *user, double *system) {
    if (b.user < a.user || b.system < a.system || b.nice < a.nice || b.idle < a.idle) return -1.0;
    uint64_t du = b.user - a.user, ds = b.system - a.system, dn = b.nice - a.nice, di = b.idle - a.idle, all = du + ds + dn + di;
    if (!all) return -1.0;
    if (user) *user = (double)(du + dn) / (double)all;
    if (system) *system = (double)ds / (double)all;
    double load = (double)(du + ds + dn) / (double)all;
    return load > 1.0 ? 1.0 : load;
}
// "820 MB" / "1.9 GB" / "11.6 GB", into buf: gigabytes with one decimal at every size (1.7.0, KT: RAM & CPU's tile reads "11.6 GB" as the tile
// drawn over Memory Magic's does, not "12 GB"; its panel and Activity Monitor write the same numbers the same way)
#include <stdio.h>
static inline void MSBDFormatBytes(uint64_t bytes, char *buf, size_t size) {
    double mb = (double)bytes / 1048576.0;
    if (mb < 1000.0) snprintf(buf, size, "%.0f MB", mb);
    else snprintf(buf, size, "%.1f GB", mb / 1024.0);
}
#endif
