// ProcList.h -- the process snapshot our Activity Monitor window (ActivityMonitor.h) shows, included into StatusBar.x before it. Plain reads, the
// same ones the RAM & CPU tile and the start-up CPU sampler already make (sysctl KERN_PROC_ALL, proc_pid_rusage, proc_pidinfo, proc_pidpath): one
// DMProcInfo per process with its pid, parent, user, name, and the figures when they can be read as the user SpringBoard runs as. %CPU is not stored
// here; the window keeps the previous snapshot and works it out with common/ProcSample.h, as macOS's Activity Monitor does between two refreshes.
#ifndef MSBD_PROC_LIST_H
#define MSBD_PROC_LIST_H
#import <Foundation/Foundation.h>
#import <sys/sysctl.h>
#import <mach/mach_time.h>
#include "../common/ProcSample.h"

// libproc pieces the iOS SDK leaves out (declared by hand, like proc_pid_rusage near the top of StatusBar.x; identical externs are harmless).
extern int proc_pidpath(int pid, void *buffer, uint32_t buffersize);
extern int proc_pidinfo(int pid, int flavor, uint64_t arg, void *buffer, int buffersize);
#define MSBD_PROC_PIDTASKINFO 4
struct MSBDProcTaskInfo {
    uint64_t pti_virtual_size, pti_resident_size, pti_total_user, pti_total_system, pti_threads_user, pti_threads_system;
    int32_t pti_policy, pti_faults, pti_pageins, pti_cow_faults, pti_messages_sent, pti_messages_received,
            pti_syscalls_mach, pti_syscalls_unix, pti_csw, pti_threadnum, pti_numrunning, pti_priority;
};

@interface DMProcInfo : NSObject
@property (nonatomic) int pid, ppid, uid;
@property (nonatomic, copy) NSString *name;          // the executable's last path component (or the short comm name); never nil: "(<pid>)" without one
@property (nonatomic) uint64_t cpuNs;                // cumulative CPU time (user + system), nanoseconds; 0 when not readable
@property (nonatomic) uint64_t footprint, resident, disk;   // bytes; 0 when not readable
@property (nonatomic) int threads;                   // -1 when not readable
@property (nonatomic) BOOL haveStats;                // the figures above were read (else the process shows by name only, "–")
@property (nonatomic) double cpuPercent;             // filled by the window from two snapshots; -1 until then
@end
@implementation DMProcInfo
- (NSString *)name { return _name.length ? _name : [NSString stringWithFormat:@"(%d)", _pid]; }   // (the window's rows, sort and search take it as is)
@end

// A name from the bytes the kernel gives (a path's last component, or p_comm), read as UTF-8 that is never refused (common/ProcSample.h
// MSBDProcNameUTF8: a character p_comm's 16-byte cut split is left out, any other stray byte is U+FFFD). nil only when nothing is left.
static NSString *DMProcNameFrom(const char *bytes, size_t len) {
    char buf[3 * 1024 + 1];   // (len <= 1024 here: every byte broken = 3 bytes each)
    if (MSBDProcNameUTF8(bytes, len < 1024 ? len : 1024, buf, sizeof buf) == 0) return nil;
    return [NSString stringWithUTF8String:buf];
}

// One snapshot of every process. Figures are filled where the user SpringBoard runs as may read them; where it may not, haveStats is NO and the
// process still appears by name. Any thread (the window reads it on a queue of its own: ActivityMonitor.h); a 1-5 s timer's worth while the window
// is visible.
static NSArray<DMProcInfo *> *DMProcListSnapshot(void) {
    static mach_timebase_info_data_t tb; static dispatch_once_t once; dispatch_once(&once, ^{ mach_timebase_info(&tb); });   // (any thread: read once, whole)
    int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0 }; size_t len = 0;
    if (sysctl(mib, 4, NULL, &len, NULL, 0) != 0 || !len) return @[];
    struct kinfo_proc *procs = malloc(len);
    if (!procs || sysctl(mib, 4, procs, &len, NULL, 0) != 0) { free(procs); return @[]; }
    size_t n = len / sizeof(struct kinfo_proc);
    NSMutableArray<DMProcInfo *> *out = [NSMutableArray arrayWithCapacity:n];
    for (size_t i = 0; i < n; i++) {
        int pid = procs[i].kp_proc.p_pid; if (pid <= 0) continue;
        DMProcInfo *e = [DMProcInfo new];
        e.pid = pid; e.ppid = procs[i].kp_eproc.e_ppid; e.uid = procs[i].kp_eproc.e_ucred.cr_uid;
        e.threads = -1; e.cpuPercent = -1.0;
        char path[1024]; path[0] = 0;
        NSString *name = nil;
        if (proc_pidpath(pid, path, sizeof path) > 0) { const char *base = strrchr(path, '/'); base = base ? base + 1 : path; name = DMProcNameFrom(base, strlen(base)); }
        if (!name.length) name = DMProcNameFrom(procs[i].kp_proc.p_comm, strnlen(procs[i].kp_proc.p_comm, sizeof procs[i].kp_proc.p_comm));
        e.name = name;   // (nil: nothing readable at all -- the getter's "(<pid>)")
        struct rusage_info_v2 ri; memset(&ri, 0, sizeof ri);
        if (proc_pid_rusage(pid, RUSAGE_INFO_V2, (rusage_info_t *)&ri) == 0) {
            e.haveStats = YES;
            e.cpuNs = MSBDMachTicksToNs(ri.ri_user_time + ri.ri_system_time, tb.numer, tb.denom);
            e.footprint = ri.ri_phys_footprint; e.resident = ri.ri_resident_size;
            e.disk = ri.ri_diskio_bytesread + ri.ri_diskio_byteswritten;
            struct MSBDProcTaskInfo ti; memset(&ti, 0, sizeof ti);
            if (proc_pidinfo(pid, MSBD_PROC_PIDTASKINFO, 0, &ti, sizeof ti) == (int)sizeof ti) e.threads = ti.pti_threadnum;
        }
        [out addObject:e];
    }
    free(procs);
    return out;
}
#endif
