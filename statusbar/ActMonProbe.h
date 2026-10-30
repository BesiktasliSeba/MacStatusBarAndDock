// ActMonProbe.h -- DEBUG BUILDS ONLY (included under #if DEBUG): the read-only groundwork for our Activity Monitor feature (the Mac-style process
// window, 1.7.0 research). It reads the process list and each process's figures the same way the RAM & CPU tile reads the whole device, logs them
// in an Activity-Monitor-shaped table, and -- the point of the probe -- reports how many processes SpringBoard could read each figure for, so phase 2
// sees on the real devices (A12Z 18.5, iPad 2 16.7.7, later 17.5) exactly which columns are available to code running inside SpringBoard and which
// are not. Nothing here changes what SpringBoard does: it only reads and logs. Trigger: `actmon` (one snapshot, ~1 s apart for the %CPU deltas).
//
// What it reads, all per the same user SpringBoard runs as (mobile), no extra rights:
//   - the process list: sysctl KERN_PROC_ALL (pid, ppid, name, uid) -- the same call DMCPUSample and DMSSHSessionActive already make;
//   - CPU time, physical footprint, resident size, disk I/O, started-at: proc_pid_rusage(RUSAGE_INFO_V2) -- the same call DMFootprintBytes makes;
//   - thread count and a resident-size cross-check: proc_pidinfo(PROC_PIDTASKINFO);
//   - the executable path: proc_pidpath.
// %CPU is worked out by common/ProcSample.h from two rusage readings an interval apart, as macOS's Activity Monitor does.
#import <sys/sysctl.h>
#import <mach/mach_time.h>
#include "../common/ProcSample.h"

// The libproc declarations and struct MSBDProcTaskInfo live in ProcList.h (included earlier in StatusBar.x); this probe reuses them.

// pid -> cumulative CPU time in nanoseconds (user + system from rusage, via the device's timebase), for the two-sample %CPU.
static NSDictionary<NSNumber *, NSNumber *> *DMActMonCPUNanos(void) {
    static mach_timebase_info_data_t tb; if (!tb.denom) mach_timebase_info(&tb);
    int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0 }; size_t len = 0;
    if (sysctl(mib, 4, NULL, &len, NULL, 0) != 0 || !len) return @{};
    struct kinfo_proc *procs = malloc(len);
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    if (procs && sysctl(mib, 4, procs, &len, NULL, 0) == 0)
        for (size_t i = 0; i < len / sizeof(struct kinfo_proc); i++) {
            int pid = procs[i].kp_proc.p_pid; if (pid <= 0) continue;
            struct rusage_info_v2 ri; memset(&ri, 0, sizeof(ri));
            if (proc_pid_rusage(pid, RUSAGE_INFO_V2, (rusage_info_t *)&ri) != 0) continue;
            out[@(pid)] = @(MSBDMachTicksToNs(ri.ri_user_time + ri.ri_system_time, tb.numer, tb.denom));
        }
    free(procs);
    return out;
}

// One Activity-Monitor-shaped snapshot into the log: a first CPU-time reading, an interval, then the full table and the readability counts.
static void DMActMonProbe(void) {
    NSDictionary<NSNumber *, NSNumber *> *before = DMActMonCPUNanos();
    uint64_t wallThen = mach_absolute_time();
    DMLog([NSString stringWithFormat:@"[actmon] first reading: %lu processes; sampling 1 s for %%CPU...", (unsigned long)before.count]);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        static mach_timebase_info_data_t tb; if (!tb.denom) mach_timebase_info(&tb);
        uint64_t wallNs = MSBDMachTicksToNs(mach_absolute_time() - wallThen, tb.numer, tb.denom);
        int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0 }; size_t len = 0;
        if (sysctl(mib, 4, NULL, &len, NULL, 0) != 0 || !len) { DMLog(@"[actmon] the process list could not be read"); return; }
        struct kinfo_proc *procs = malloc(len);
        if (!procs || sysctl(mib, 4, procs, &len, NULL, 0) != 0) { free(procs); DMLog(@"[actmon] the process list could not be read"); return; }
        size_t n = len / sizeof(struct kinfo_proc);
        NSUInteger total = 0, rusageOK = 0, taskinfoOK = 0, pathOK = 0;
        NSUInteger mobileTotal = 0, mobileRU = 0, rootTotal = 0, rootRU = 0;   // (the owner split: how much a root helper would add)
        NSMutableArray *rows = [NSMutableArray array];
        for (size_t i = 0; i < n; i++) {
            int pid = procs[i].kp_proc.p_pid; if (pid <= 0) continue;
            total++;
            int ppid = procs[i].kp_eproc.e_ppid, uid = procs[i].kp_eproc.e_ucred.cr_uid;
            if (uid == 0) rootTotal++; else mobileTotal++;
            char comm[MAXCOMLEN + 1]; memcpy(comm, procs[i].kp_proc.p_comm, MAXCOMLEN); comm[MAXCOMLEN] = 0;
            struct rusage_info_v2 ri; memset(&ri, 0, sizeof(ri));
            BOOL haveRU = proc_pid_rusage(pid, RUSAGE_INFO_V2, (rusage_info_t *)&ri) == 0;
            if (haveRU) { rusageOK++; if (uid == 0) rootRU++; else mobileRU++; }
            struct MSBDProcTaskInfo ti; memset(&ti, 0, sizeof(ti));
            BOOL haveTI = proc_pidinfo(pid, MSBD_PROC_PIDTASKINFO, 0, &ti, sizeof(ti)) == (int)sizeof(ti);
            if (haveTI) taskinfoOK++;
            char path[1024]; path[0] = 0; BOOL havePath = proc_pidpath(pid, path, sizeof(path)) > 0;
            if (havePath) pathOK++;
            uint64_t cpuNow = haveRU ? MSBDMachTicksToNs(ri.ri_user_time + ri.ri_system_time, tb.numer, tb.denom) : 0;
            NSNumber *cpuThen = before[@(pid)];
            double pct = (haveRU && cpuThen) ? MSBDProcCPUPercent(cpuThen.unsignedLongLongValue, cpuNow, wallNs) : -1.0;
            char pctBuf[16], memBuf[32], resBuf[32], diskBuf[32]; MSBDFormatPercent(pct, pctBuf, sizeof pctBuf);
            MSBDFormatBytes(ri.ri_phys_footprint, memBuf, sizeof memBuf); MSBDFormatBytes(ri.ri_resident_size, resBuf, sizeof resBuf);
            MSBDFormatBytes(ri.ri_diskio_bytesread + ri.ri_diskio_byteswritten, diskBuf, sizeof diskBuf);   // (the Disk tab: rusage carries it, no helper)
            NSString *name = havePath ? [@(path) lastPathComponent] : @(comm);
            [rows addObject:@[ @(pct < 0 ? 0.0 : pct),
                [NSString stringWithFormat:@"%5d %5d  %-5s cpu %6s  mem %9s  res %9s  disk %9s  thr %3d  %@",
                    pid, ppid, uid == 0 ? "root" : "mob", pctBuf, memBuf, resBuf, diskBuf, haveTI ? ti.pti_threadnum : -1, name] ]];
        }
        free(procs);
        [rows sortUsingComparator:^NSComparisonResult(NSArray *a, NSArray *b) { return [b[0] compare:a[0]]; }];
        DMLog([NSString stringWithFormat:@"[actmon] ==== process table (by %%CPU), interval %.0f ms ====", wallNs / 1e6]);
        DMLog(@"[actmon]   pid  ppid   uid  %CPU        memory(footprint)  resident    disk(r+w)   thr  name");
        for (NSUInteger i = 0; i < rows.count; i++) DMLog([NSString stringWithFormat:@"[actmon] %@", rows[i][1]]);
        // The feasibility line: what fraction of processes each source answered for, from inside SpringBoard, as the user it runs as.
        DMLog([NSString stringWithFormat:@"[actmon] ==== readable from SpringBoard: list %lu; proc_pid_rusage %lu/%lu; proc_pidinfo(taskinfo) %lu/%lu; proc_pidpath %lu/%lu ====",
            (unsigned long)total, (unsigned long)rusageOK, (unsigned long)total, (unsigned long)taskinfoOK, (unsigned long)total, (unsigned long)pathOK, (unsigned long)total]);
        // The owner split: mobile-owned processes are what SpringBoard can read without a helper; the root-owned gap is what a read-only helper adds.
        DMLog([NSString stringWithFormat:@"[actmon] ==== by owner: mobile %lu procs, rusage %lu; root %lu procs, rusage %lu (the root gap = what a helper would add) ====",
            (unsigned long)mobileTotal, (unsigned long)mobileRU, (unsigned long)rootTotal, (unsigned long)rootRU]);
    });
}
